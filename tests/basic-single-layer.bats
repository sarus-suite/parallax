load helpers.bash

# Testing the migration of an image with a simple single-layer manifest
# validating that squashing, mount, run, and remove work
@test "mv3 + run busybox:latest" {
# pull simple image
run \
	"$PODMAN_BINARY" \
		--root "$PODMAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		pull busybox:latest

# try a migration
run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$PODMAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--migrate \
		--image busybox:latest
[[ "$output" =~ "Migration successfully completed" ]]

# check for squash file
run \
	ls "$RO_STORAGE"/overlay/**/*.squash
[ "$status" -eq 0 ] # Exit 0 is match found

run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		images

# Lets try running the migrated image
run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		run --rm --security-opt seccomp=unconfined busybox:latest echo ok
[ "$status" -eq 0 ]
[ "$output" = "ok" ]

# try a removal
run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$CLEAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--rmi \
		--image busybox:latest

run \
	ls "$RO_STORAGE"/overlay/**/*.squash
[ "$status" -ne 0 ] # Exit 2 is no match

}

