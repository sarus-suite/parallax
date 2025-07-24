load helpers.bash

@test "mv + run + rmi of multiple images" {
# Pulling images
run \
	"$PODMAN_BINARY" \
		--root "$PODMAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		pull busybox:latest

run \
    "$PODMAN_BINARY" \
        --root "$PODMAN_ROOT" \
        --runroot "$PODMAN_RUNROOT" \
        pull alpine:latest

run \
    "$PODMAN_BINARY" \
        --root "$PODMAN_ROOT" \
        --runroot "$PODMAN_RUNROOT" \
        pull ubuntu:latest

# Migration of images
run \
    "$PARALLAX_BINARY" \
        --podmanRoot "$PODMAN_ROOT" \
        --roStoragePath "$RO_STORAGE" \
        --mksquashfsPath "$MKSQUASHFS_PATH" \
        --log-level info \
        --migrate \
        --image ubuntu:latest
[[ "$output" =~ "Migration successfully completed" ]]

run \
    "$PARALLAX_BINARY" \
        --podmanRoot "$PODMAN_ROOT" \
        --roStoragePath "$RO_STORAGE" \
        --mksquashfsPath "$MKSQUASHFS_PATH" \
        --log-level info \
        --migrate \
        --image alpine:latest
[[ "$output" =~ "Migration successfully completed" ]]

run \
    "$PARALLAX_BINARY" \
        --podmanRoot "$PODMAN_ROOT" \
        --roStoragePath "$RO_STORAGE" \
        --mksquashfsPath "$MKSQUASHFS_PATH" \
        --log-level info \
        --migrate \
        --image busybox:latest
[[ "$output" =~ "Migration successfully completed" ]]

# check for squash files
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

# Run the migrated images
run \
    "$PODMAN_BINARY" \
        --root "$CLEAN_ROOT" \
        --runroot "$PODMAN_RUNROOT" \
        --storage-opt additionalimagestore=$RO_STORAGE \
        --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
        run --rm $PODMAN_RUN_OPTIONS busybox:latest echo ok
[ "$status" -eq 0 ]
[ "$output" = "ok" ]

run \
    "$PODMAN_BINARY" \
        --root "$CLEAN_ROOT" \
        --runroot "$PODMAN_RUNROOT" \
        --storage-opt additionalimagestore=$RO_STORAGE \
        --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
        run --rm $PODMAN_RUN_OPTIONS alpine:latest echo ok
[ "$status" -eq 0 ]
[ "$output" = "ok" ]

run \
    "$PODMAN_BINARY" \
        --root "$CLEAN_ROOT" \
        --runroot "$PODMAN_RUNROOT" \
        --storage-opt additionalimagestore=$RO_STORAGE \
        --storage-opt mount_program=$MOUNT_PROGRAM_PATH \
        run --rm $PODMAN_RUN_OPTIONS ubuntu:latest echo ok
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
    "$PARALLAX_BINARY" \
        --podmanRoot "$CLEAN_ROOT" \
        --roStoragePath "$RO_STORAGE" \
        --mksquashfsPath "$MKSQUASHFS_PATH" \
        --log-level info \
        --rmi \
        --image alpine:latest

run \
    "$PARALLAX_BINARY" \
        --podmanRoot "$CLEAN_ROOT" \
        --roStoragePath "$RO_STORAGE" \
        --mksquashfsPath "$MKSQUASHFS_PATH" \
        --log-level info \
        --rmi \
        --image ubuntu:latest

# No image should be left in rostorage
run \
	ls "$RO_STORAGE"/overlay/**/*.squash
[ "$status" -ne 0 ] # Exit 2 is no match

}

