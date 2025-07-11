load helpers.bash

@test "mv3 double migration handled" {
run \
	"$PODMAN_BINARY" \
		--root "$PODMAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		pull busybox:latest

# first migration
run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$PODMAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--migrate \
		--image busybox:latest
[ "$status" -eq 0 ]
[[ "$output" =~ "Migration successfully completed" ]]

# sanity check
run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		run --rm $PODMAN_RUN_OPTIONS busybox:latest echo ok
[ "$status" -eq 0 ]
[ "$output" = "ok" ]

# second migration should be stopped early with exit 0
run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$PODMAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--migrate \
		--image busybox:latest
[ "$status" -eq 0 ]
[[ "$output" =~ "Nothing to do." ]]

# Remove
run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$CLEAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--rmi \
		--image busybox:latest
}

