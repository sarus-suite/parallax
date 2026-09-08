#!/usr/bin/env sh
set -eu

OUT="${OUT:-dist/fusermount3-static/fusermount3}"
LIBFUSE_VERSION="${LIBFUSE_VERSION:-3.18.2}"
LIBFUSE_REPO="${LIBFUSE_REPO:-https://github.com/libfuse/libfuse.git}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
root_dir="$(pwd -P)"

case "${OUT}" in
  /*) out_path="${OUT}" ;;
  *) out_path="${root_dir}/${OUT}" ;;
esac

workdir="$(mktemp -d)"
src_dir="${workdir}/libfuse"
build_dir="${workdir}/build"

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

  apk add --no-cache meson ninja pkgconf
}

mkdir -p "$(dirname "${out_path}")"

ensure_cmd git

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
ensure_cmd meson
ensure_cmd ninja

export CFLAGS="${CFLAGS:--O2 -pipe}"
export CPPFLAGS="${CPPFLAGS:-}"
export LDFLAGS="${LDFLAGS:--static}"
export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"

git init "${src_dir}" >/dev/null
git -C "${src_dir}" remote add origin "${LIBFUSE_REPO}"
git -C "${src_dir}" fetch --depth 1 origin "refs/tags/fuse-${LIBFUSE_VERSION}"
git -C "${src_dir}" checkout --detach FETCH_HEAD >/dev/null

meson setup "${build_dir}" "${src_dir}" \
  --buildtype=release \
  --default-library=static \
  -Dutils=true \
  -Dexamples=false \
  -Dtests=false \
  -Ddisable-mtab=true \
  -Duseroot=false \
  -Dc_args="${CFLAGS}${CPPFLAGS:+ ${CPPFLAGS}}" \
  -Dc_link_args="${LDFLAGS}"

ninja -C "${build_dir}" -j "${JOBS}"

cp "${build_dir}/util/fusermount3" "${out_path}"
chmod 0755 "${out_path}"

if command -v strip >/dev/null 2>&1; then
  strip "${out_path}" || true
fi

printf '%s\n' "Built static fusermount3 at ${out_path}"

if command -v file >/dev/null 2>&1; then
  file "${out_path}"
fi

if command -v readelf >/dev/null 2>&1; then
  readelf -l "${out_path}" | grep interpreter || true
fi

if command -v scanelf >/dev/null 2>&1; then
  scanelf -n "${out_path}" || true
fi
