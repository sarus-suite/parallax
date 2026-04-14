load helpers.bash

list_temp_lowerdirs() {
  find "$PARALLAX_MP_TMPDIR" -mindepth 1 -maxdepth 1 -type d -name 'lowerdir.*' | sort
}

wait_for_lowerdir_count() {
  local expected_count="$1"
  local tries="${2:-100}"
  local delay="${3:-0.1}"
  local actual_count

  for _ in $(seq 1 "$tries"); do
    actual_count="$(list_temp_lowerdirs | wc -l | tr -d ' ')"
    if [ "$actual_count" -eq "$expected_count" ]; then
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

wait_for_mountpoint() {
  local path="$1"
  local tries="${2:-100}"
  local delay="${3:-0.1}"

  for _ in $(seq 1 "$tries"); do
    if mountpoint -q "$path"; then
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

@test "same migrated image runs in parallel with isolated lowerdir mounts and cleanup" {
  export PARALLAX_MP_TMPDIR
  PARALLAX_MP_TMPDIR="$(mktemp -d)"

  run \
    "$PODMAN_BINARY" \
      --root "$PODMAN_ROOT" \
      --runroot "$PODMAN_RUNROOT" \
      pull busybox:latest
  assert_success

  run \
    "$PARALLAX_BINARY" \
      --podmanRoot "$PODMAN_ROOT" \
      --roStoragePath "$RO_STORAGE" \
      --mksquashfsPath "$MKSQUASHFS_PATH" \
      --log-level info \
      --migrate \
      --image busybox:latest
  assert_success
  assert_output --partial "Migration successfully completed"

  run \
    "$PODMAN_BINARY" \
      --root "$CLEAN_ROOT" \
      --runroot "$PODMAN_RUNROOT" \
      --storage-opt additionalimagestore=$RO_STORAGE \
      --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
      run -d --name same-image-one $PODMAN_RUN_OPTIONS busybox:latest sh -c 'sleep 5'
  assert_success

  run \
    "$PODMAN_BINARY" \
      --root "$CLEAN_ROOT" \
      --runroot "$PODMAN_RUNROOT" \
      --storage-opt additionalimagestore=$RO_STORAGE \
      --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
      run -d --name same-image-two $PODMAN_RUN_OPTIONS busybox:latest sh -c 'sleep 5'
  assert_success

  run wait_for_lowerdir_count 2
  assert_success

  run list_temp_lowerdirs
  assert_success
  local lowerdirs=()
  mapfile -t lowerdirs <<<"$output"
  assert_equal "${#lowerdirs[@]}" "2"

  local lowerdir_one
  local lowerdir_two
  lowerdir_one="${lowerdirs[0]}"
  lowerdir_two="${lowerdirs[1]}"
  run test -n "$lowerdir_one"
  assert_success
  run test -n "$lowerdir_two"
  assert_success
  run test "$lowerdir_one" != "$lowerdir_two"
  assert_success

  run wait_for_mountpoint "$lowerdir_one"
  assert_success
  run wait_for_mountpoint "$lowerdir_two"
  assert_success

  run test -d "$lowerdir_one/etc"
  assert_success
  run test -d "$lowerdir_two/etc"
  assert_success

  run \
    "$PODMAN_BINARY" \
      --root "$CLEAN_ROOT" \
      --runroot "$PODMAN_RUNROOT" \
      --storage-opt additionalimagestore=$RO_STORAGE \
      --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
      inspect same-image-one same-image-two --format '{{.State.Running}}'
  assert_success
  assert_equal "$(printf '%s\n' "$output" | grep -c '^true$')" "2"

  run \
    "$PODMAN_BINARY" \
      --root "$CLEAN_ROOT" \
      --runroot "$PODMAN_RUNROOT" \
      --storage-opt additionalimagestore=$RO_STORAGE \
      --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
      wait same-image-one same-image-two
  assert_success
  assert_equal "$(printf '%s\n' "$output" | grep -c '^0$')" "2"

  run wait_for_lowerdir_count 0 150 0.1
  assert_success

  run \
    "$PODMAN_BINARY" \
      --root "$CLEAN_ROOT" \
      --runroot "$PODMAN_RUNROOT" \
      --storage-opt additionalimagestore=$RO_STORAGE \
      --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
      ps --all --format '{{.Names}} {{.Status}}'
  assert_success
  assert_line --partial "same-image-one Exited"
  assert_line --partial "same-image-two Exited"

  run \
    "$PODMAN_BINARY" \
      --root "$CLEAN_ROOT" \
      --runroot "$PODMAN_RUNROOT" \
      --storage-opt additionalimagestore=$RO_STORAGE \
      --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
      rm same-image-one same-image-two
  assert_success
}
