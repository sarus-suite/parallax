#!/usr/bin/env sh
set -eu

OUT="${OUT:-dist/squashfs-tools-static/mksquashfs}"
SQUASHFS_TOOLS_VERSION="${SQUASHFS_TOOLS_VERSION:-4.7.5}"
SQUASHFS_TOOLS_REPO="${SQUASHFS_TOOLS_REPO:-https://github.com/plougher/squashfs-tools.git}"
COMP_DEFAULT="${COMP_DEFAULT:-zstd}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
root_dir="$(pwd -P)"

case "${OUT}" in
  /*) out_path="${OUT}" ;;
  *) out_path="${root_dir}/${OUT}" ;;
esac

workdir="$(mktemp -d)"
src_dir="${workdir}/squashfs-tools"
build_dir="${src_dir}/squashfs-tools"

cleanup() {
  if [ "${KEEP_WORKDIR}" = "1" ]; then
    printf '%s\n' "Keeping build workspace at ${workdir}"
    return
  fi

  rm -rf "${workdir}"
}

trap cleanup EXIT HUP INT TERM

ensure_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    return
  fi

  printf '%s\n' "error: required command not found: $1" >&2
  exit 1
}

apk_install_if_root() {
  if ! command -v apk >/dev/null 2>&1; then
    return
  fi

  if [ "$(id -u)" -ne 0 ]; then
    return
  fi

  apk add --no-cache zlib-dev zstd-dev

  for pkg in zlib-static zstd-static; do
    apk add --no-cache "${pkg}" >/dev/null 2>&1 || true
  done
}

cc_find_file() {
  file_name="$1"
  found_path="$("${CC}" -print-file-name="${file_name}" 2>/dev/null || true)"

  if [ -n "${found_path}" ] && [ "${found_path}" != "${file_name}" ] && [ -f "${found_path}" ]; then
    printf '%s\n' "${found_path}"
    return 0
  fi

  return 1
}

ensure_static_archive() {
  archive_name="$1"
  package_hint="$2"

  if cc_find_file "${archive_name}" >/dev/null 2>&1; then
    return
  fi

  printf '%s\n' "error: static archive ${archive_name} not found for ${CC}; install ${package_hint}" >&2
  exit 1
}

mkdir -p "$(dirname "${out_path}")"

ensure_cmd git
ensure_cmd make

if [ -z "${CC:-}" ]; then
  if command -v musl-gcc >/dev/null 2>&1; then
    export CC="musl-gcc"
  elif command -v gcc >/dev/null 2>&1; then
    export CC="gcc"
  else
    export CC="cc"
  fi
fi

ensure_cmd "${CC}"
apk_install_if_root
ensure_static_archive libz.a "zlib-dev and zlib-static"
ensure_static_archive libzstd.a "zstd-dev and zstd-static"

extra_cflags="${EXTRA_CFLAGS:-${CFLAGS:--O2 -pipe}}"
cppflags="${CPPFLAGS:-}"
extra_ldflags="${EXTRA_LDFLAGS:-${LDFLAGS:--static}}"

git init "${src_dir}" >/dev/null
git -C "${src_dir}" remote add origin "${SQUASHFS_TOOLS_REPO}"
git -C "${src_dir}" fetch --depth 1 origin "refs/tags/${SQUASHFS_TOOLS_VERSION}"
git -C "${src_dir}" checkout --detach FETCH_HEAD >/dev/null

cd "${build_dir}"
make -j"${JOBS}" \
  CONFIG=1 \
  GZIP_SUPPORT=1 \
  XZ_SUPPORT=0 \
  LZO_SUPPORT=0 \
  LZ4_SUPPORT=0 \
  ZSTD_SUPPORT=1 \
  LZMA_XZ_SUPPORT=0 \
  LZMA_SUPPORT=0 \
  COMP_DEFAULT="${COMP_DEFAULT}" \
  XATTR_SUPPORT=1 \
  XATTR_OS_SUPPORT=1 \
  XATTR_DEFAULT=1 \
  USE_PREBUILT_MANPAGES=y \
  EXTRA_CFLAGS="${extra_cflags}" \
  CPPFLAGS="${cppflags}" \
  EXTRA_LDFLAGS="${extra_ldflags}" \
  mksquashfs

cp "${build_dir}/mksquashfs" "${out_path}"
chmod 0755 "${out_path}"

if command -v strip >/dev/null 2>&1; then
  strip "${out_path}" || true
fi

printf '%s\n' "Built static mksquashfs at ${out_path}"

if command -v file >/dev/null 2>&1; then
  file "${out_path}"
fi

if command -v readelf >/dev/null 2>&1; then
  readelf -l "${out_path}" | grep interpreter || true
fi

if command -v scanelf >/dev/null 2>&1; then
  scanelf -n "${out_path}" || true
fi
