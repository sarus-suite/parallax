load helpers.bash

@test "mv3 + run alpine:latest" {  
# pull multi-arch image
run \
	"$PODMAN_BINARY" \
		--root "$PODMAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		pull alpine:latest

# migrate
run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$PODMAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--migrate \
		--image alpine:latest
[ "$status" -eq 0 ]
[[ "$output" =~ "Migration successfully completed" ]]

# run a simple command, this should pass if migration handled multi-arch manifest
run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		run --rm $PODMAN_RUN_OPTIONS alpine:latest echo ok
[ "$status" -eq 0 ]
[ "$output" = "ok" ]

# remove
run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$CLEAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--rmi \
		--image alpine:latest
}

