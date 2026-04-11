#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CACHE_DIR="${ROOT_DIR}/.ci-cache/host-tools"
OUT_DIR="${ROOT_DIR}/.ci-out/host-tools"
BIN_DIR="${OUT_DIR}/bin"
MANIFEST_DIR="${OUT_DIR}/share"

SQUASHFUSE_VERSION="${SQUASHFUSE_VERSION:-0.6.1}"
PODMAN_STATIC_VERSION="${PODMAN_STATIC_VERSION:-v5.8.1}"
BATS_REF="${BATS_REF:-v1.11.1}"

log() {
  printf '[host-tools] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

download_if_missing() {
  local url="$1"
  local dest="$2"

  if [ ! -f "$dest" ]; then
    log "downloading ${url}"
    curl -fsSL "$url" -o "$dest"
  fi
}

install_squashfuse() {
  local version="$1"
  local tarball="${CACHE_DIR}/downloads/squashfuse-${version}.tar.gz"
  local src_root="${CACHE_DIR}/src"
  local prefix="${CACHE_DIR}/prefix/squashfuse-${version}"
  local srcdir="${src_root}/squashfuse-${version}"

  if [ -x "${prefix}/bin/squashfuse" ] && [ -x "${prefix}/bin/squashfuse_ll" ]; then
    log "reusing cached squashfuse ${version}"
    return
  fi

  mkdir -p "${CACHE_DIR}/downloads" "${src_root}" "${CACHE_DIR}/build" "${CACHE_DIR}/prefix"
  download_if_missing \
    "https://github.com/vasi/squashfuse/releases/download/${version}/squashfuse-${version}.tar.gz" \
    "${tarball}"

  rm -rf "${srcdir}" "${prefix}"
  tar -xzf "${tarball}" -C "${src_root}"

  mkdir -p "${prefix}"
  pushd "${srcdir}" >/dev/null
  ./configure --prefix="${prefix}"
  make -j"$(nproc)"
  make install
  popd >/dev/null
}

install_podman_static() {
  local version="$1"
  local prefix="${CACHE_DIR}/prefix/podman-static-${version}"
  local tarball="${CACHE_DIR}/downloads/podman-static-${version}.tar.gz"
  local unpack_dir="${CACHE_DIR}/build/podman-static"
  local bundle_root="${unpack_dir}/podman-linux-amd64"
  local url="https://github.com/mgoltzsche/podman-static/releases/download/${version}/podman-linux-amd64.tar.gz"

  if [ -x "${prefix}/usr/local/bin/podman" ]; then
    log "reusing cached podman static bundle ${version}"
    return
  fi

  mkdir -p "${CACHE_DIR}/downloads" "${CACHE_DIR}/build" "${CACHE_DIR}/prefix"
  download_if_missing "${url}" "${tarball}"

  rm -rf "${unpack_dir}" "${prefix}"
  mkdir -p "${unpack_dir}" "${prefix}"
  tar -xzf "${tarball}" -C "${unpack_dir}"

  mkdir -p "${prefix}/usr" "${prefix}/etc"
  cp -R "${bundle_root}/usr/." "${prefix}/usr/"
  cp -R "${bundle_root}/etc/." "${prefix}/etc/"

  test -x "${prefix}/usr/local/bin/podman"
}

install_bats() {
  local ref="$1"
  local prefix="${CACHE_DIR}/prefix/bats-${ref}"
  local clone_dir="${CACHE_DIR}/src/bats-core-${ref}"

  if [ -x "${prefix}/bin/bats" ]; then
    log "reusing cached bats ${ref}"
    return
  fi

  rm -rf "${clone_dir}" "${prefix}"
  git clone --depth 1 --branch "${ref}" https://github.com/bats-core/bats-core.git "${clone_dir}"
  "${clone_dir}/install.sh" "${prefix}"
}

publish_bundle() {
  local podman_bin_dir="${OUT_DIR}/podman-static/usr/local/bin"

  rm -rf "${OUT_DIR}"
  mkdir -p "${BIN_DIR}" "${MANIFEST_DIR}" "${OUT_DIR}/podman-static" "${OUT_DIR}/bats"

  cp "${CACHE_DIR}/prefix/squashfuse-${SQUASHFUSE_VERSION}/bin/squashfuse" "${BIN_DIR}/"
  cp "${CACHE_DIR}/prefix/squashfuse-${SQUASHFUSE_VERSION}/bin/squashfuse_ll" "${BIN_DIR}/"

  cp -R "${CACHE_DIR}/prefix/podman-static-${PODMAN_STATIC_VERSION}/." "${OUT_DIR}/podman-static/"
  cp "${podman_bin_dir}/podman" "${BIN_DIR}/"
  cp "${podman_bin_dir}/crun" "${BIN_DIR}/" || true
  cp "${podman_bin_dir}/runc" "${BIN_DIR}/" || true
  cp "${podman_bin_dir}/fuse-overlayfs" "${BIN_DIR}/" || true
  cp "${podman_bin_dir}/fusermount3" "${BIN_DIR}/" || true
  cp "${podman_bin_dir}/pasta" "${BIN_DIR}/" || true
  cp "${podman_bin_dir}/pasta.avx2" "${BIN_DIR}/" || true

  cp -R "${CACHE_DIR}/prefix/bats-${BATS_REF}/." "${OUT_DIR}/bats/"
  cp "${CACHE_DIR}/prefix/bats-${BATS_REF}/bin/bats" "${BIN_DIR}/"

  cp "${ROOT_DIR}/scripts/parallax-mount-program.sh" "${BIN_DIR}/parallax-mount-program"
  chmod 0755 "${BIN_DIR}/parallax-mount-program"

  cat > "${MANIFEST_DIR}/manifest.txt" <<EOF
squashfuse_version=${SQUASHFUSE_VERSION}
podman_static_version=${PODMAN_STATIC_VERSION}
bats_ref=${BATS_REF}
EOF
}

main() {
  require_cmd curl
  require_cmd git
  require_cmd make
  require_cmd tar

  mkdir -p "${CACHE_DIR}"

  install_squashfuse "${SQUASHFUSE_VERSION}"
  install_podman_static "${PODMAN_STATIC_VERSION}"
  install_bats "${BATS_REF}"
  publish_bundle

  log "host tools bundle ready under ${OUT_DIR}"
  find "${OUT_DIR}" -maxdepth 2 -type f | sort
}

main "$@"
