load helpers.bash

export SKOPEO_BINARY="${SKOPEO_BINARY:-skopeo}"

# These tests are used to validate that different ways to reference images work
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

exist_image() {
  local ref="$1"
  "$PARALLAX_BINARY" \
    --roStoragePath "$RO_STORAGE" \
    --log-level info \
    --exists \
    --image "$ref"
}

list_squash_files() {
  ls "$RO_STORAGE"/overlay/**/*.squash
}

inspect_source_image() {
  "$PODMAN_BINARY" --root "$PODMAN_ROOT" --runroot "$PODMAN_RUNROOT" \
    image inspect --format "$2" "$1"
}

inspect_migrated_image() {
  "$PODMAN_BINARY" --root "$CLEAN_ROOT" --runroot "$PODMAN_RUNROOT" \
    --storage-opt additionalimagestore="$RO_STORAGE" \
    --storage-opt mount_program="$MOUNT_PROGRAM_PATH" \
    image inspect --format "$2" "$1"
}

import_source_image() {
  "$PODMAN_BINARY" --root "$PODMAN_ROOT" --runroot "$PODMAN_RUNROOT" \
    unshare "$SKOPEO_BINARY" --insecure-policy copy --format v2s2 "$1" \
    "containers-storage:[overlay@$PODMAN_ROOT+$PODMAN_RUNROOT]$2"
}

prepare_alternate_digest_image() {
  local ref="$1"
  local source_dir="$BATS_TEST_TMPDIR/oci-source"
  local converted_dir="$BATS_TEST_TMPDIR/docker-converted"

  # Copy only the selected platform. Format conversion, rather than a
  # multiarchitecture index, provides the two different manifest digests.
  run "$SKOPEO_BINARY" --insecure-policy copy --format oci \
    "docker://$ref" "dir:$source_dir"
  assert_success
  run "$SKOPEO_BINARY" manifest-digest "$source_dir/manifest.json"
  assert_success
  original_digest="$output"

  run "$SKOPEO_BINARY" --insecure-policy copy --format v2s2 \
    "dir:$source_dir" "dir:$converted_dir"
  assert_success

  # Seed the primary digest with the converted manifest, then import the
  # original again with conversion so its digest is retained in RepoDigests.
  run import_source_image "dir:$converted_dir" "$ref"
  assert_success
  run import_source_image "dir:$source_dir" "$ref"
  assert_success
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

@test "migrate image by reference with digest" {
  local repo="docker.io/library/alpine"
  local ref="$repo:3.22.1"
  run pull_image "$ref"
  assert_success

  run inspect_source_image "$ref" '{{.Digest}}'
  assert_success
  [[ "$output" == sha256:* ]]
  local digest_ref="$repo@$output"

  run migrate_image "$digest_ref"
  assert_success
  assert_output --partial 'Migration successfully completed'

  run exist_image "$digest_ref"
  assert_success
  assert_output --partial 'exists in read-only storage'
}

@test "migrate image by alternate RepoDigests reference after import conversion" {
  local repo="docker.io/library/alpine"
  local ref="$repo:3.22.1"
  local original_digest
  prepare_alternate_digest_image "$ref"
  [[ "$original_digest" == sha256:* ]]
  local digest_ref="$repo@$original_digest"

  # Require the alternate-digest fixture; an ordinary digest must not pass.
  run inspect_source_image "$ref" '{{.Digest}}'
  assert_success
  [[ "$output" == sha256:* ]]
  [ "$output" != "$original_digest" ]
  run inspect_source_image "$ref" '{{range .RepoDigests}}{{println .}}{{end}}'
  assert_success
  assert_output --partial "$digest_ref"

  run inspect_source_image "$ref" '{{.Id}}'
  assert_success
  local image_id="$output"
  run inspect_source_image "$digest_ref" '{{.Id}}'
  assert_success
  assert_output "$image_id"

  run migrate_image "$digest_ref"
  assert_success
  assert_output --partial 'Migration successfully completed'
  run exist_image "$digest_ref"
  assert_success
  assert_output --partial 'exists in read-only storage'
}

@test "remove image by reference with digest" {
  local repo="docker.io/library/alpine"
  local ref="$repo:3.22.1"
  run pull_image "$ref"
  assert_success
  run migrate_image "$ref"
  assert_success
  assert_output --partial 'Migration successfully completed'

  # Flattening creates a new manifest, so removal must use its new digest.
  run inspect_migrated_image "$ref" '{{.Digest}}'
  assert_success
  [[ "$output" == sha256:* ]]
  local digest_ref="$repo@$output"
  run exist_image "$digest_ref"
  assert_success
  assert_output --partial 'exists in read-only storage'

  run rmi_image "$digest_ref"
  assert_success
  assert_output --partial 'Removal successfully completed'

  # Removal can return zero on failure; check the image and sidecars too.
  local lookup
  for lookup in "$ref" "$digest_ref"; do
    run exist_image "$lookup"
    assert_failure
    assert_output --partial 'does not exist in read-only storage'
  done
  run list_squash_files
  assert_failure
}

@test "remove image by image ID" {
  local ref="docker.io/library/alpine:3.22.1"
  run pull_image "$ref"
  assert_success
  run migrate_image "$ref"
  assert_success
  assert_output --partial 'Migration successfully completed'

  # Use the migrated image's short ID, as displayed by podman images.
  run inspect_migrated_image "$ref" '{{.Id}}'
  assert_success
  [[ "$output" =~ ^[0-9a-f]{64}$ ]]
  local image_id="$output"

  run rmi_image "${image_id:0:12}"
  assert_success
  assert_output --partial 'Removal successfully completed'

  run exist_image "$ref"
  assert_failure
  assert_output --partial 'does not exist in read-only storage'
  run list_squash_files
  assert_failure
}

@test "image name not tagged: alpine" {
  setup_registries_conf_with_alpine_alias

  run pull_image "alpine"
  assert_success

  run migrate_image "alpine"
  assert_success
  assert_output --regexp 'Migration successfully completed|Nothing to do\.'

  run exist_image "alpine"
  assert_success
  assert_output --regexp 'exists in read-only storage'

  run run_image "alpine"
  assert_success
  assert_output "ok"

  run rmi_image "alpine"
  assert_success

  run exist_image "alpine"
  assert_failure
  assert_output --regexp 'does not exist in read-only storage'

  run list_squash_files
  assert_failure

  cleanup_registries_conf
}

@test "image name tagged latest: alpine:latest" {
  setup_registries_conf_with_alpine_alias

  run pull_image "alpine:latest"
  assert_success

  run migrate_image "alpine:latest"
  assert_success
  assert_output --regexp 'Migration successfully completed|Nothing to do\.'

  run exist_image "alpine:latest"
  assert_success
  assert_output --regexp 'exists in read-only storage'

  run run_image "alpine:latest"
  assert_success
  assert_output "ok"

  run rmi_image "alpine:latest"
  assert_success

  run exist_image "alpine:latest"
  assert_failure
  assert_output --regexp 'does not exist in read-only storage'

  run list_squash_files
  assert_failure

  cleanup_registries_conf
}

@test "image name tagged non latest: alpine:3.22.1" {
  setup_registries_conf_with_alpine_alias

  run pull_image "alpine:3.22.1"
  assert_success

  run migrate_image "alpine:3.22.1"
  assert_success
  assert_output --regexp 'Migration successfully completed|Nothing to do\.'

  run exist_image "alpine:3.22.1"
  assert_success
  assert_output --regexp 'exists in read-only storage'

  run run_image "alpine:3.22.1"
  assert_success
  assert_output "ok"

  run rmi_image "alpine:3.22.1"
  assert_success

  run exist_image "alpine:3.22.1"
  assert_failure
  assert_output --regexp 'does not exist in read-only storage'

  run list_squash_files
  assert_failure

  cleanup_registries_conf
}


@test "image name with registry: docker.io/library/alpine" {
  setup_registries_conf_with_alpine_alias

  run pull_image "docker.io/library/alpine"
  assert_success

  run migrate_image "docker.io/library/alpine"
  assert_success
  assert_output --regexp 'Migration successfully completed|Nothing to do\.'

  run exist_image "docker.io/library/alpine"
  assert_success
  assert_output --regexp 'exists in read-only storage'

  run run_image "docker.io/library/alpine"
  assert_success
  assert_output "ok"

  run rmi_image "docker.io/library/alpine"
  assert_success

  run exist_image "docker.io/library/alpine"
  assert_failure
  assert_output --regexp 'does not exist in read-only storage'

  run list_squash_files
  assert_failure

  cleanup_registries_conf
}

@test "image name with registry tagged: docker.io/library/alpine:3.22.1" {
  setup_registries_conf_with_alpine_alias

  run pull_image "docker.io/library/alpine:3.22.1"
  assert_success

  run migrate_image "docker.io/library/alpine:3.22.1"
  assert_success
  assert_output --regexp 'Migration successfully completed|Nothing to do\.'

  run exist_image "docker.io/library/alpine:3.22.1"
  assert_success
  assert_output --regexp 'exists in read-only storage'

  run run_image "docker.io/library/alpine:3.22.1"
  assert_success
  assert_output "ok"

  run rmi_image "docker.io/library/alpine:3.22.1"
  assert_success

  run exist_image "docker.io/library/alpine:3.22.1"
  assert_failure
  assert_output --regexp 'does not exist in read-only storage'

  run list_squash_files
  assert_failure

  cleanup_registries_conf
}

@test "podman build and migrate from implicit localhost/alpine" {
  setup_registries_conf_with_alpine_alias

  newref="new-alpine"

  run pull_image "alpine:latest"
  assert_success

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
  assert_success

  run migrate_image "$newref"
  assert_success
  assert_output --regexp 'Migration successfully completed|Nothing to do\.'

  run exist_image "$newref"
  assert_success
  assert_output --regexp 'exists in read-only storage'

  run run_image "$newref"
  assert_success
  assert_output "ok"

  run rmi_image "$newref"
  assert_success

  run exist_image "$newref"
  assert_failure
  assert_output --regexp 'does not exist in read-only storage'

  run list_squash_files
  assert_failure

  rm -rf "$buildctx"

  cleanup_registries_conf
}
