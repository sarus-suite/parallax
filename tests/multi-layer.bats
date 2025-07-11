load helpers.bash

@test "mv3 + inspect ubuntu:latest for multi-layers, envs, and cmd" {
run \
	"$PODMAN_BINARY" \
		--root "$PODMAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		pull ubuntu:latest

run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$PODMAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--migrate \
		--image ubuntu:latest
[ "$status" -eq 0 ]
[[ "$output" =~ "Migration successfully completed" ]]

# Inspect entrypoint
run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		image inspect --format '{{json .Config.Env}}' ubuntu:latest
[ "$status" -eq 0 ]
[[ "$output" =~ "PATH" ]]

# inspect Cmd
run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		image inspect --format '{{json .Config.Cmd}}' ubuntu:latest
[ "$status" -eq 0 ]
[[ "$output" =~ "bash" ]]

# test run
run \
	"$PODMAN_BINARY" \
		--root "$CLEAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		--storage-opt additionalimagestore=$RO_STORAGE \
		--storage-opt mount_program=$MOUNT_PROGRAM_PATH \
		run --rm $PODMAN_RUN_OPTIONS ubuntu:latest cat /etc/os-release
[ "$status" -eq 0 ]
[[ "$output" =~ "ubuntu" ]]

run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$CLEAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--rmi \
		--image ubuntu:latest
}
