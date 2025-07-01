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
      "-o lowerdir=$LOWERDIR,upperdir=$UPPERRDIR,workdir=$WORKDIR" \
	  "$MNTPOINT"

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
      "-o lowerdir=$LOWERDIR,upperdir=$UPPERRDIR,workdir=$WORKDIR" \
	  "$MNTPOINT"

  # Check env override
  [[ "$output" =~ env-squashfuse ]]
  [[ "$output" =~ env-fuse-overlayfs ]]
}


@test "falls back to PATH defaults when no config/env" {
  LOWERDIR="$TEST_DIR/lowerdir"
  UPPERRDIR="$TEST_DIR/upperdir"
  WORKDIR="$TEST_DIR/workdir"
  MNTPOINT="$TEST_DIR/mnt"
  mkdir -p "$LOWERDIR" "$UPPERRDIR" "$WORKDIR" "$MNTPOINT"

  # Remove config and unset vars
  rm -f "$TEST_DIR/parallax-mount.conf"
  unset PARALLAX_MP_SQUASHFUSE_CMD PARALLAX_MP_FUSE_OVERLAYFS_CMD

  # Restrict PATH so only stub squashfuse is found
  export PATH="$TEST_DIR/bin"

  # Provide only squashfuse stub, omitting fuse-overlayfs
  mv "$TEST_DIR/bin/env-squashfuse" "$TEST_DIR/bin/squashfuse"

  run bash -x "$TEST_DIR/parallax-mount-program.sh" \
      "-o lowerdir=$LOWERDIR,upperdir=$UPPERRDIR,workdir=$WORKDIR" \
      "$MNTPOINT"

  [ "$status" -ne 0 ]
  [[ "$output" =~ "fuse-overlayfs not found" ]] || [[ "$output" =~ "command not found" ]]
  [[ ! "$output" =~ squashfuse-from-path ]]
}
