#!/usr/bin/env bats

# These tests deliberately hold writers inside mksquashfs or rsync. Assertions
# observe readiness/log messages rather than assuming migration timing.
setup() {
  export PODMAN_BINARY="${PODMAN_BINARY:-$(command -v podman)}"
  export PARALLAX_BINARY="${PARALLAX_BINARY:-$BATS_TEST_DIRNAME/../dist/parallax}"
  export PODMAN_ROOT="$BATS_TEST_TMPDIR/source"
  export PODMAN_RUNROOT="$BATS_TEST_TMPDIR/run"
  export RO_STORAGE="$BATS_TEST_TMPDIR/store"
  export REAL_MKSQUASHFS="$(command -v mksquashfs)"
  export REAL_RSYNC="$(command -v rsync)"
  export GATE="$BATS_TEST_TMPDIR/gate"
  mkdir -p "$PODMAN_ROOT" "$PODMAN_RUNROOT" "$RO_STORAGE" "$GATE" "$BATS_TEST_TMPDIR/bin"
  writer_pids=()

  cat > "$BATS_TEST_TMPDIR/bin/mksquashfs" <<'EOF'
#!/bin/sh
if [ -n "$PARALLAX_TEST_GATE" ]; then
  touch "$PARALLAX_TEST_GATE/entered"
  while [ ! -e "$PARALLAX_TEST_GATE/release" ]; do sleep 0.05; done
  if [ -e "$PARALLAX_TEST_GATE/fail" ]; then
    echo 'injected mksquashfs failure' >&2
    exit 41
  fi
fi
source=$1
destination=$2
shift 2
exec "$REAL_MKSQUASHFS" "$source" "$destination" -processors 1 "$@"
EOF
  cat > "$BATS_TEST_TMPDIR/bin/rsync" <<'EOF'
#!/bin/sh
for arg do last=$arg; done
if [ "$PARALLAX_TEST_FAIL_WRITEBACK" = 1 ] && [ "$last" = "$RO_STORAGE/" ]; then
  touch "$GATE/writeback-entered"
  while [ ! -e "$GATE/writeback-release" ]; do sleep 0.05; done
  echo 'injected rsync write-back failure' >&2
  exit 42
fi
exec "$REAL_RSYNC" "$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/mksquashfs" "$BATS_TEST_TMPDIR/bin/rsync"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # A local, single-UID image avoids registry dependencies and subordinate-ID
  # requirements. These tests check store consistency, not container execution.
  mkdir -p "$BATS_TEST_TMPDIR/rootfs"
  echo payload > "$BATS_TEST_TMPDIR/rootfs/payload"
  tar --owner=0 --group=0 -C "$BATS_TEST_TMPDIR/rootfs" -cf "$BATS_TEST_TMPDIR/rootfs.tar" .
  run "$PODMAN_BINARY" --root "$PODMAN_ROOT" --runroot "$PODMAN_RUNROOT" import "$BATS_TEST_TMPDIR/rootfs.tar" docker.io/library/busybox:latest
  if [ "$status" -ne 0 ]; then
    echo "$output" >&2
    return 1
  fi
  run "$PODMAN_BINARY" --root "$PODMAN_ROOT" --runroot "$PODMAN_RUNROOT" tag docker.io/library/busybox:latest localhost/concurrent-other:latest
  [ "$status" -eq 0 ]
}

teardown() {
  touch "$GATE/release" "$GATE/writeback-release"
  for pid in "${writer_pids[@]}"; do wait "$pid" || true; done
  if [ -z "${BATS_TEST_COMPLETED:-}" ]; then
    for logfile in "$BATS_TEST_TMPDIR"/*.log; do
      [ ! -f "$logfile" ] || cat "$logfile" >&3
    done
  fi
  "$PODMAN_BINARY" --root "$PODMAN_ROOT" --runroot "$PODMAN_RUNROOT" rmi --all >/dev/null 2>&1 || true
}

writer() {
  "$PARALLAX_BINARY" --"$1" --image "$2" \
    --podmanRoot "$PODMAN_ROOT" --roStoragePath "$RO_STORAGE" \
    --mksquashfsPath "$BATS_TEST_TMPDIR/bin/mksquashfs" --lock-timeout "${3:-30s}"
}

wait_for_file() {
  local attempt
  for ((attempt=0; attempt<600; attempt++)); do
    [ ! -e "$1" ] || return 0
    sleep 0.05
  done
  echo "Timed out waiting for $1" >&2
  return 1
}

wait_for_waiter() {
  local attempt
  for ((attempt=0; attempt<600; attempt++)); do
    if grep -q 'Waiting for image store lock' "$1"; then return 0; fi
    sleep 0.05
  done
  echo "Writer did not wait for lock: $1" >&2
  return 1
}

start_gated_migration() {
  PARALLAX_TEST_GATE="$GATE" writer migrate busybox:latest > "$BATS_TEST_TMPDIR/first.log" 2>&1 &
  first=$!
  writer_pids+=("$first")
  wait_for_file "$GATE/entered"
}

assert_exists() {
  run "$PARALLAX_BINARY" --exists --image "$1" --roStoragePath "$RO_STORAGE"
  [ "$status" -eq 0 ]
}

@test "concurrent migrations of different images preserve both" {
  start_gated_migration
  writer migrate localhost/concurrent-other:latest > "$BATS_TEST_TMPDIR/second.log" 2>&1 &
  second=$!; writer_pids+=("$second")
  wait_for_waiter "$BATS_TEST_TMPDIR/second.log"
  touch "$GATE/release"
  wait "$first"
  wait "$second"
  assert_exists busybox:latest
  assert_exists localhost/concurrent-other:latest
}

@test "concurrent migration of the same image publishes once" {
  start_gated_migration
  writer migrate busybox:latest > "$BATS_TEST_TMPDIR/second.log" 2>&1 &
  second=$!; writer_pids+=("$second")
  wait_for_waiter "$BATS_TEST_TMPDIR/second.log"
  touch "$GATE/release"
  wait "$first"
  wait "$second"
  grep -q 'Nothing to do' "$BATS_TEST_TMPDIR/second.log"
  [ "$(find "$RO_STORAGE/squash" -type f -name '*.squash' | wc -l)" -eq 1 ]
  assert_exists busybox:latest
}

@test "rmi waits behind migration and preserves an unrelated image" {
  run writer migrate localhost/concurrent-other:latest
  [ "$status" -eq 0 ]
  start_gated_migration
  writer rmi busybox:latest > "$BATS_TEST_TMPDIR/second.log" 2>&1 &
  second=$!; writer_pids+=("$second")
  wait_for_waiter "$BATS_TEST_TMPDIR/second.log"
  touch "$GATE/release"
  wait "$first"
  wait "$second"
  assert_exists localhost/concurrent-other:latest
  run "$PARALLAX_BINARY" --exists --image busybox:latest --roStoragePath "$RO_STORAGE"
  [ "$status" -eq 1 ]
  [ "$(find "$RO_STORAGE/squash" -type f -name '*.squash' | wc -l)" -eq 1 ]
}

@test "writer timeout leaves the holder intact and permits a later writer" {
  start_gated_migration
  run writer migrate localhost/concurrent-other:latest 150ms
  [ "$status" -ne 0 ]
  [[ "$output" == *'image store lock timeout'* ]]
  [[ "$output" == *'150ms'* ]]
  touch "$GATE/release"
  wait "$first"
  run writer migrate localhost/concurrent-other:latest
  [ "$status" -eq 0 ]
  assert_exists busybox:latest
  assert_exists localhost/concurrent-other:latest
}

@test "migration failure returns an error and releases the store lock" {
  touch "$GATE/fail"
  start_gated_migration
  touch "$GATE/release"
  if wait "$first"; then
    echo "Writer unexpectedly succeeded" >&2
    return 1
  fi
  grep -q 'injected mksquashfs failure' "$BATS_TEST_TMPDIR/first.log"
  ! grep -q 'Migration successfully completed' "$BATS_TEST_TMPDIR/first.log"
  run writer migrate localhost/concurrent-other:latest 0
  [ "$status" -eq 0 ]
  assert_exists localhost/concurrent-other:latest
}

@test "write-back holds the lock and propagates failure before releasing it" {
  PARALLAX_TEST_FAIL_WRITEBACK=1 writer migrate busybox:latest > "$BATS_TEST_TMPDIR/first.log" 2>&1 &
  first=$!; writer_pids+=("$first")
  wait_for_file "$GATE/writeback-entered"
  run writer rmi busybox:latest 150ms
  [ "$status" -ne 0 ]
  [[ "$output" == *'image store lock timeout'* ]]
  touch "$GATE/writeback-release"
  if wait "$first"; then
    echo "Writer unexpectedly succeeded" >&2
    return 1
  fi
  grep -q 'injected rsync write-back failure' "$BATS_TEST_TMPDIR/first.log"
  ! grep -q 'Migration successfully completed' "$BATS_TEST_TMPDIR/first.log"
  run writer migrate localhost/concurrent-other:latest 0
  [ "$status" -eq 0 ]
  assert_exists localhost/concurrent-other:latest
}

@test "migration and write-back failures are both reported" {
  touch "$GATE/fail"
  PARALLAX_TEST_FAIL_WRITEBACK=1 start_gated_migration
  touch "$GATE/release" "$GATE/writeback-release"
  if wait "$first"; then
    echo "Writer unexpectedly succeeded" >&2
    return 1
  fi
  grep -q 'injected mksquashfs failure' "$BATS_TEST_TMPDIR/first.log"
  grep -q 'injected rsync write-back failure' "$BATS_TEST_TMPDIR/first.log"
  ! grep -q 'Migration successfully completed' "$BATS_TEST_TMPDIR/first.log"
  run writer migrate localhost/concurrent-other:latest 0
  [ "$status" -eq 0 ]
}
