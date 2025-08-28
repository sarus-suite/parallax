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
  "$PODMAN_BINARY" \
    --root "$PODMAN_ROOT" \
    --runroot "$PODMAN_RUNROOT" \
    pull "$ref"
}

migrate_image() {
  local ref="$1"
  "$PARALLAX_BINARY" \
    --podmanRoot "$PODMAN_ROOT" \
    --roStoragePath "$RO_STORAGE" \
    --mksquashfsPath "$MKSQUASHFS_PATH" \
    --log-level info \
    --migrate \
    --image "$ref"
}

run_image() {
  local ref="$1"
  "$PODMAN_BINARY" \
    --root "$CLEAN_ROOT" \
    --runroot "$PODMAN_RUNROOT" \
    --storage-opt additionalimagestore="$RO_STORAGE" \
    --storage-opt mount_program="$MOUNT_PROGRAM_PATH" \
    run --rm $PODMAN_RUN_OPTIONS "$ref" echo ok
}

rmi_image() {
  local ref="$1"
  "$PARALLAX_BINARY" \
    --podmanRoot "$CLEAN_ROOT" \
    --roStoragePath "$RO_STORAGE" \
    --mksquashfsPath "$MKSQUASHFS_PATH" \
    --log-level info \
    --rmi \
    --image "$ref"
}

list_squash_files() {
  ls "$RO_STORAGE"/overlay/**/*.squash
}


setup_registries_conf_with_alpine_alias() {
  local confdir
  confdir="$(mktemp -d)"
  local conffile="$confdir/my-registries.conf"

  cat >"$conffile" <<'EOF'
unqualified-search-registries = ["public.ecr.aws"]
short-name-mode = "enforcing"

[aliases]
"alpine" = "public.ecr.aws/docker/library/alpine"
EOF

  export CONTAINERS_REGISTRIES_CONF="$conffile"
  export PODMAN_REGISTRIES_CONF_DIR="$confdir" # keep dir around for cleanup
}

cleanup_registries_conf() {
  if [ -n "$PODMAN_REGISTRIES_CONF_DIR" ]; then
    rm -rf "$PODMAN_REGISTRIES_CONF_DIR"
    unset PODMAN_REGISTRIES_CONF_DIR
  fi
  unset CONTAINERS_REGISTRIES_CONF
}

### Tests

@test "image name not tagged: alpine" {
  setup_registries_conf_with_alpine_alias

  run pull_image "alpine"
  [ "$status" -eq 0 ]

  run migrate_image "alpine"
  [ "$status" -eq 0 ]
  assert_output --partial "Migration successfully completed"

  run run_image "alpine"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run rmi_image "alpine"
  [ "$status" -eq 0 ]

  run list_squash_files
  [ "$status" -ne 0 ]

  cleanup_registries_conf
}

@test "image name tagged latest: alpine:latest" {
  setup_registries_conf_with_alpine_alias

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

  cleanup_registries_conf
}

@test "image name tagged non latest: alpine:3.22.1" {
  setup_registries_conf_with_alpine_alias

  run pull_image "alpine:3.22.1"
  [ "$status" -eq 0 ]

  run migrate_image "alpine:3.22.1"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Migration successfully completed" || "$output" =~ "Nothing to do." ]]

  run run_image "alpine:3.22.1"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run rmi_image "alpine:3.22.1"
  [ "$status" -eq 0 ]

  run list_squash_files
  [ "$status" -ne 0 ]

  cleanup_registries_conf
}


@test "image name with registry: docker.io/library/alpine" {
  setup_registries_conf_with_alpine_alias

  run pull_image "docker.io/library/alpine"
  [ "$status" -eq 0 ]

  run migrate_image "docker.io/library/alpine"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Migration successfully completed" || "$output" =~ "Nothing to do." ]]

  run run_image "docker.io/library/alpine"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run rmi_image "docker.io/library/alpine"
  [ "$status" -eq 0 ]

  run list_squash_files
  [ "$status" -ne 0 ]

  cleanup_registries_conf
}

@test "image name with registry tagged: docker.io/library/alpine:3.22.1" {
  setup_registries_conf_with_alpine_alias

  run pull_image "docker.io/library/alpine:3.22.1"
  [ "$status" -eq 0 ]

  run migrate_image "docker.io/library/alpine:3.22.1"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Migration successfully completed" || "$output" =~ "Nothing to do." ]]

  run run_image "docker.io/library/alpine:3.22.1"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run rmi_image "docker.io/library/alpine:3.22.1"
  [ "$status" -eq 0 ]

  run list_squash_files
  [ "$status" -ne 0 ]

  cleanup_registries_conf
}

@test "podman build and migrate from implicit localhost/alpine" {
  setup_registries_conf_with_alpine_alias

  newref="new-alpine"

  run pull_image "alpine:latest"
  [ "$status" -eq 0 ]

  # simple containerfile
  buildctx="$(mktemp -d)"
  cat > "$buildctx/Containerfile" <<'EOF'
FROM alpine:latest
ENV FOO=bar
# tiny no-op layer to ensure a change
RUN echo "hello" > /hello.txt
EOF

  # build the new container image
  run "$PODMAN_BINARY" \
      --root "$PODMAN_ROOT" \
      --runroot "$PODMAN_RUNROOT" \
      build --pull=never -f "$buildctx/Containerfile" -t "$newref" "$buildctx"
  [ "$status" -eq 0 ]

  run migrate_image "$newref"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Migration successfully completed" || "$output" =~ "Nothing to do." ]]

  run run_image "$newref"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]

  run rmi_image "$newref"
  [ "$status" -eq 0 ]

  run list_squash_files
  [ "$status" -ne 0 ]

  rm -rf "$buildctx"

  cleanup_registries_conf
}
