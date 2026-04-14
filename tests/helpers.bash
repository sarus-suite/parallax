# Helper functions
# setup - creates an isolated store for podman and parallax
# teardown - cleans stores

export PODMAN_BINARY="${PODMAN_BINARY:-/mnt/nfs/git/podman/bin/podman}"
export PARALLAX_BINARY="${PARALLAX_BINARY:-/mnt/nfs/git/parallax/parallax}"
export MOUNT_PROGRAM_PATH="${MOUNT_PROGRAM_PATH:-/mnt/nfs/git/parallax/scripts/parallax-mount-program.sh}"
export PODMAN_RUN_OPTIONS="${PODMAN_RUN_OPTIONS:---security-opt seccomp=unconfined}"

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  # Seting up temp dirs and env vars
  export PODMAN_ROOT="$(mktemp -d)"
  export PODMAN_RUNROOT="$(mktemp -d)"
  export RO_STORAGE="$(mktemp -d)"
  export CLEAN_ROOT="$(mktemp -d)"
  export MKSQUASHFS_PATH="$(command -v mksquashfs)"
  export PARALLAX_MP_LOGFILE="${BATS_TEST_TMPDIR:-$(mktemp -d)}/mount_program.log"

  mkdir -p "$PODMAN_ROOT"
  mkdir -p "$PODMAN_RUNROOT"
  mkdir -p "$RO_STORAGE"
  mkdir -p "$CLEAN_ROOT"
}

teardown() {
  if [ -z "${BATS_TEST_COMPLETED:-}" ] && [ -s "${PARALLAX_MP_LOGFILE:-}" ]; then
    echo "# mount-program log: ${PARALLAX_MP_LOGFILE}" >&3
    sed 's/^/# mp: /' "$PARALLAX_MP_LOGFILE" >&3 || true
  fi

  "${PODMAN_BINARY}" unshare chmod -R u+rwX "${PODMAN_ROOT}" 2>/dev/null || true
  "${PODMAN_BINARY}" unshare chmod -R u+rwX "${PODMAN_RUNROOT}" 2>/dev/null || true
  "${PODMAN_BINARY}" unshare chmod -R u+rwX "${RO_STORAGE}" 2>/dev/null || true
  "${PODMAN_BINARY}" unshare chmod -R u+rwX "${CLEAN_ROOT}" 2>/dev/null || true

  # Podman to teardown the temporal dirs and resolve file permissions
  "$PODMAN_BINARY" \
	  --root "$PODMAN_ROOT" \
	  --runroot "$PODMAN_RUNROOT" \
	  --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
	  rmi --all || true

  rm -rf "$PODMAN_ROOT"
  rm -rf "$PODMAN_RUNROOT"
  rm -rf "$RO_STORAGE"
  rm -rf "$CLEAN_ROOT"
  if [ -n "${PARALLAX_MP_TMPDIR:-}" ]; then
    rm -rf "$PARALLAX_MP_TMPDIR"
  fi

  unset PODMAN_ROOT PODMAN_RUNROOT RO_STORAGE CLEAN_ROOT MOUNT_PROGRAM_PATH MKSQUASHFS_PATH PARALLAX_MP_LOGFILE PARALLAX_MP_TMPDIR
}
