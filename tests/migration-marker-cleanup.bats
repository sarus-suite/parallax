load helpers.bash

@test "mv3 marker is cleaned up before user deletes storage roots" {
run \
	"$PODMAN_BINARY" \
		--root "$PODMAN_ROOT" \
		--runroot "$PODMAN_RUNROOT" \
		pull busybox:latest
assert_success

run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$PODMAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--migrate \
		--image busybox:latest
assert_success
assert_output --partial "Migration successfully completed"

run find "$RO_STORAGE" -name '.migrationv3-*' -print -quit
assert_success
[ -n "$output" ]
marker_path="$output"

run test -f "$marker_path"
assert_success

run \
	"$PARALLAX_BINARY" \
		--podmanRoot "$CLEAN_ROOT" \
		--roStoragePath "$RO_STORAGE" \
		--mksquashfsPath "$MKSQUASHFS_PATH" \
		--log-level info \
		--rmi \
		--image busybox:latest
assert_success

run find "$RO_STORAGE" -name '.migrationv3-*' -print -quit
assert_success
[ -z "$output" ]

run rm -rf "$PODMAN_ROOT"
assert_success

run rm -rf "$PODMAN_RUNROOT"
assert_success

run rm -rf "$RO_STORAGE"
assert_success

run rm -rf "$CLEAN_ROOT"
assert_success
}
