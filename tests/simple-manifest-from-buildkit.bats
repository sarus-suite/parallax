load helpers.bash

@test "mv3 + run hello-world:linux (a docker buildkit generated image)" {
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
		--log-level info \
		--migrate \
		--image docker.io/library/hello-world:linux
[ "$status" -eq 0 ]
[[ "$output" =~ "Migration successfully completed" ]]

run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		run --rm --security-opt seccomp=unconfined docker.io/library/hello-world:linux
[ "$status" -eq 0 ]
# check exit-code is happy happy

  
run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$CLEAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--rmi \
		--image docker.io/library/hello-world:linux
}

