load helpers.bash

@test "migrate with custom mksquashfs compression level 3" {
run \
	"$PODMAN_BINARY" \
		--root "$PODMAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		pull docker.io/library/hello-world:linux

run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$PODMAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--mksquashfs-opts "-noappend -comp zstd -Xcompression-level 3 -noD -no-xattrs -e security.capability" \
		--log-level info \
		--migrate \
		--image docker.io/library/hello-world:linux
[ "$status" -eq 0 ]
[[ "$output" =~ "Migration successfully completed" ]]

run \
	ls "$RO_STORAGE"/overlay/**/*.squash
[ "$status" -eq 0 ]

# Inspect squashfs metadata
run \
	bash -c 'SQUASH_FILE=$(ls "$RO_STORAGE"/overlay/**/*.squash | head -n1) && unsquashfs -s "$SQUASH_FILE"'
[ "$status" -eq 0 ]
[[ "$output" =~ "Compression zstd" ]]
[[ "$output" =~ "level 3" ]]

run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		run --rm --security-opt seccomp=unconfined docker.io/library/hello-world:linux
[ "$status" -eq 0 ]
[[ "$output" =~ "Hello from Docker!" ]]

run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$CLEAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--rmi \
		--image docker.io/library/hello-world:linux
}
