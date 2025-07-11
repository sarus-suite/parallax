# Helper functions
# setup - creates an isolated store for podman and parallax
# teardown - cleans stores

export PODMAN_BINARY="${PODMAN_BINARY:-/mnt/nfs/git/podman/bin/podman}"
export PARALLAX_BINARY="${PARALLAX_BINARY:-/mnt/nfs/git/parallax/parallax}"
export MOUNT_PROGRAM_PATH="/mnt/nfs/git/parallax/scripts/parallax-mount-program.sh"
export PODMAN_RUN_OPTIONS="--security-opt seccomp=unconfined"

setup() {
  # Seting up temp dirs and env vars
  export PODMAN_ROOT="$(mktemp -d)"
  export PODMAN_RUNROOT="$(mktemp -d)"
  export RO_STORAGE="$(mktemp -d)"
  export CLEAN_ROOT="$(mktemp -d)"
  export MKSQUASHFS_PATH="$(command -v mksquashfs)"

  mkdir -p "$PODMAN_ROOT"
  mkdir -p "$PODMAN_RUNROOT"
  mkdir -p "$RO_STORAGE"
  mkdir -p "$CLEAN_ROOT"
}

teardown() {
  # Podman to teardown the temporal dirs and resolve file permissions
  "$PODMAN_BINARY" \
	  --root "$PODMAN_ROOT" \
	  --runroot "$PODMAN_RUNROOT" \
	  --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
	  rmi --all

  rm -rf "$PODMAN_ROOT"
  rm -rf "$PODMAN_RUNROOT"
  rm -rf "$RO_STORAGE"
  rm -rf "$CLEAN_ROOT"

  unset PODMAN_ROOT PODMAN_RUNROOT RO_STORAGE CLEAN_ROOT MOUNT_PROGRAM_PATH MKSQUASHFS_PATH
}
