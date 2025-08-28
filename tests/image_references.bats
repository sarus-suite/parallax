load helpers.bash

# These tests are used to validate that different ways to reference iamges work
# pull image with ref
# migrates it using ref with parallax
# basic run check
# removes the image
# verify we are clear

### Helpers
pull_image() {
  local ref="$1"
  echo "$PODMAN_BINARY" \
       --root "$PODMAN_ROOT" \
       --runroot "$PODMAN_RUNROOT" \
       pull "$ref"
}

migrate_image() {
  local ref="$1"
  echo "$PARALLAX_BINARY" \
       --podmanRoot "$PODMAN_ROOT" \
       --roStoragePath "$RO_STORAGE" \
       --mksquashfsPath "$MKSQUASHFS_PATH" \
       --log-level info \
       --migrate \
       --image "$ref"
}

run_image() {
  local ref="$1"
  echo "$PODMAN_BINARY" \
       --root "$CLEAN_ROOT" \
       --runroot "$PODMAN_RUNROOT" \
       --storage-opt additionalimagestore="$RO_STORAGE" \
       --storage-opt mount_program="$MOUNT_PROGRAM_PATH" \
       run --rm $PODMAN_RUN_OPTIONS "$ref" echo ok
}

rmi_image() {
  local ref="$1"
  echo "$PARALLAX_BINARY" \
       --podmanRoot "$CLEAN_ROOT" \
       --roStoragePath "$RO_STORAGE" \
       --mksquashfsPath "$MKSQUASHFS_PATH" \
       --log-level info \
       --rmi \
       --image "$ref"
}

list_squash_files() {
  echo ls "$RO_STORAGE"/overlay/**/*.squash
}

### Tests

@test "image name: alpine" {
  run pull_image "alpine"
  [ "$status" -eq 0 ]

  run migrate_image "alpine"
  [ "$status" -eq 0 ]
  assert_output "Migration successfully completed"

  run run_image "alpine"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run rmi_image "alpine"
  [ "$status" -eq 0 ]

  run list_squash_files
  [ "$status" -ne 0 ]
}

@test "image name: alpine:latest" {
  run pull_image "alpine:latest"
  [ "$status" -eq 0 ]

  run migrate_image "alpine:latest"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Migration successfully completed" || "$output" =~ "Nothing to do." ]]

  run run_image "alpine:latest"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run rmi_image "alpine:latest"
  [ "$status" -eq 0 ]

  run list_squash_files
  [ "$status" -ne 0 ]
}

