load helpers.bash

@test "Either -migrate or -rmi is specified" {
  run \
    "$PARALLAX_BINARY"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Must specify either -migrate or -rmi" ]]
}

@test "Fails if both -migrate and -rmi are passed" {
  run \
    "$PARALLAX_BINARY" -migrate -rmi -image ubuntu:latest
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Must specify either -migrate or -rmi" ]]
}

@test "Fails if --image is missing" {
  run \
    "$PARALLAX_BINARY" -migrate
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Must specify -image" ]]
}

@test "Checks version" {
  run \
    "$PARALLAX_BINARY" -version
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Parallax version" ]]
}

@test "Usage is printed" {
  run \
    "$PARALLAX_BINARY" -help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "OCI image migration tool" ]]
  [[ "$output" =~ "Usage" ]]
  [[ "$output" =~ "-migrate" ]]
  [[ "$output" =~ "-image" ]]
}

@test "Checks unknown flag message" {
  run \
    "$PARALLAX_BINARY" -unknownflag
  [ "$status" -ne 0 ]
  [[ "$output" =~ "flag provided but not defined" ]]
}

@test "Fails migration when --roStoragePath directory is non-empty" {
  # Populate the storage dir with a dummy file
  # This way the directory is neither empty or with a store structure
  touch "$RO_STORAGE/dummy-file"

  run "$PARALLAX_BINARY" \
    --podmanRoot "$PODMAN_ROOT" \
    --roStoragePath "$RO_STORAGE" \
    --mksquashfsPath "$MKSQUASHFS_PATH" \
    --log-level info \
    --migrate \
    --image ubuntu:latest

  # Expect a non-zero exit code and a validation error
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Storage validation failed" ]]
}

@test "Advanced --roStoragePath directory is initialized" {
  # Populate the storage dir with a dummy file
  # This way the directory is neither empty or with a store structure
  touch "$RO_STORAGE/dummy-file"

  run "$PARALLAX_BINARY" \
    --podmanRoot "$PODMAN_ROOT" \
    --roStoragePath "$RO_STORAGE" \
    --mksquashfsPath "$MKSQUASHFS_PATH" \
    --log-level info \
    --migrate \
    --image alpine:latest

  # Expect a non-zero exit code and a validation error
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Storage validation failed" ]]

  # Bootstrap RO_STORAGE with a pulled image, this satisfies the dir structure validation
  run "$PODMAN_BINARY" \
    --root "$RO_STORAGE" \
    --runroot "$PODMAN_RUNROOT" \
    pull alpine:latest
  [ "$status" -eq 0 ]

  run "$PODMAN_BINARY" \
    --root "$PODMAN_ROOT" \
    --runroot "$PODMAN_RUNROOT" \
    pull ubuntu:latest
  [ "$status" -eq 0 ]

  # Now migration should pass check, and also complete a ubuntu migration
  run "$PARALLAX_BINARY" \
    --podmanRoot "$PODMAN_ROOT" \
    --roStoragePath "$RO_STORAGE" \
    --mksquashfsPath "$MKSQUASHFS_PATH" \
    --log-level info \
    --migrate \
    --image ubuntu:latest

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Migration successfully completed" ]]
}

@test "Fails RMI when --roStoragePath directory is non-empty" {
  # Populate the storage dir with a dummy file
  # This way the directory is neither empty or with a store structure
  touch "$RO_STORAGE/dummy-file"

  run "$PARALLAX_BINARY" \
    --podmanRoot "$PODMAN_ROOT" \
    --roStoragePath "$RO_STORAGE" \
    --mksquashfsPath "$MKSQUASHFS_PATH" \
    --log-level info \
    --rmi \
    --image ubuntu:latest

  # Expect a non-zero exit code and a validation error
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Storage validation failed" ]]
}

