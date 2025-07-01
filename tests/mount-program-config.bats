#!/usr/bin/env bats
# tests for parallax-mount-program.sh configuration and functional behavior

setup() {
  # Create working dirs and bins
  TEST_DIR="$(mktemp -d)"
  export PARALLAX_MP_LOGFILE="$TEST_DIR/mp.log"
  export PARALLAX_MP_LOGLEVEL="DEBUG"
  export PATH="$TEST_DIR/bin:$PATH"

  mkdir -p "$TEST_DIR/bin"

  # Create dummy lower, upper, work, and mountpoint dirs
  LOWERDIR="$TEST_DIR/lowerdir"
  UPPERRDIR="$TEST_DIR/upperdir"
  WORKDIR="$TEST_DIR/workdir"
  MNTPOINT="$TEST_DIR/mnt"
  mkdir -p "$LOWERDIR" "$UPPERRDIR" "$WORKDIR" "$MNTPOINT"

  # Copy mount program into test directory
  cp "$PWD/scripts/parallax-mount-program.sh" "$TEST_DIR/"
  chmod +x "$TEST_DIR/parallax-mount-program.sh"

  echo '#!/usr/bin/env bash
  echo custom-fuse-overlayfs
  ' > "$TEST_DIR/bin/custom-fuse-overlayfs"
  chmod +x "$TEST_DIR/bin/custom-fuse-overlayfs"

  echo '#!/usr/bin/env bash
  echo custom-squashfuse
  ' > "$TEST_DIR/bin/custom-squashfuse"
  chmod +x "$TEST_DIR/bin/custom-squashfuse"

  echo '#!/usr/bin/env bash
  echo env-fuse-overlayfs
  ' > "$TEST_DIR/bin/env-fuse-overlayfs"
  chmod +x "$TEST_DIR/bin/env-fuse-overlayfs"

  echo '#!/usr/bin/env bash
  echo env-squashfuse
  ' > "$TEST_DIR/bin/env-squashfuse"
  chmod +x "$TEST_DIR/bin/env-squashfuse"
}

teardown() {
  umount "$MNTPOINT" >/dev/null 2>&1 || true
  sleep 5
  rm -rf "$TEST_DIR"
}

@test "Config file overrides for mount program tools setup" {
  # Prepare a real but dummy squash image for lowerdir
  mkdir -p "$LOWERDIR/content"
  echo "hello" > "$LOWERDIR/content/file.txt"
  mksquashfs "$LOWERDIR/content" "${LOWERDIR}.squash" -noappend -no-progress >/dev/null

  # Test config file to override commands
  cat <<EOF > "$TEST_DIR/parallax-mount.conf"
PARALLAX_MP_SQUASHFUSE_CMD="custom-squashfuse"
PARALLAX_MP_FUSE_OVERLAYFS_CMD="custom-fuse-overlayfs"
EOF

  # Run mount program using config
  run env PARALLAX_MP_CONFIG="$TEST_DIR/parallax-mount.conf" \
      bash -x "$TEST_DIR/parallax-mount-program.sh" \
      --lowerdir="$LOWERDIR" --upperdir="$UPPERRDIR" \
      --workdir="$WORKDIR" "$MNTPOINT"

  # We should expect to see the custom commands in output
  [[ "$output" =~ custom-squashfuse ]] || {
    echo "=== MOUNT-PROG STDOUT/ERR ==="
    echo "$output"
    echo "============================="
    return 1
  }
  [[ "$output" =~ custom-fuse-overlayfs ]]
}

@test "ENV vars override defaults when no config file is passed" {
  # Prepare a real but dummy squash image for lowerdir
  mkdir -p "$LOWERDIR/content"
  echo "world" > "$LOWERDIR/content/file2.txt"
  mksquashfs "$LOWERDIR/content" "${LOWERDIR}.squash" -noappend -no-progress >/dev/null

  # Unset any config
  rm -f "$TEST_DIR/parallax-mount.conf"

  # Override commands via ENV VARs
  export PARALLAX_MP_SQUASHFUSE_CMD="env-squashfuse"
  export PARALLAX_MP_FUSE_OVERLAYFS_CMD="env-fuse-overlayfs"

  # Run mount program
  run bash -x "$TEST_DIR/parallax-mount-program.sh" \
      --lowerdir="$LOWERDIR" --upperdir="$UPPERRDIR" \
      --workdir="$WORKDIR" "$MNTPOINT"

  # Check env override
  [[ "$output" =~ env-squashfuse ]]
  [[ "$output" =~ env-fuse-overlayfs ]]
}

@test "watcher unmounts on deletion of etc directory" {
  # Skip if we don't have real binaries
  command -v squashfuse >/dev/null || skip "needs squashfuse"
  command -v fuse-overlayfs >/dev/null || skip "needs fuse-overlayfs"
  command -v inotifywait >/dev/null || skip "needs inotifywait"

  # Build a real squashfs image containing an /etc directory
  mkdir -p "$LOWERDIR/content/etc"
  echo "keep me" > "$LOWERDIR/content/etc/important.conf"
  mksquashfs "$LOWERDIR/content" "${LOWERDIR}.squash" -noappend -no-progress >/dev/null

  # Launch the mount program in background
  bash -x "$TEST_DIR/parallax-mount-program.sh" \
    --lowerdir="$LOWERDIR" \
    --upperdir="$UPPERRDIR" \
    --workdir="$WORKDIR" \
    "$MNTPOINT" &
  pid=$!

  # Give it a moment to finish mounting
  sleep 3
  run mountpoint -q "$MNTPOINT"
  [ "$status" -eq 0 ]

  # Now simulate container teardown by deleting the etc directory
  rm -rf "$MNTPOINT/etc"

  # Wait up to 5s for the watcher to catch the delete and exit
  for i in $(seq 1 5); do
    mountpoint -q "$MNTPOINT" && sleep 1 || break
  done

  # The mount program should exit cleanly once it sees the delete
  wait $pid
  [ "$?" -eq 0 ]

  # And the overlay mount should be gone
  ! mountpoint -q "$MNTPOINT"
}

