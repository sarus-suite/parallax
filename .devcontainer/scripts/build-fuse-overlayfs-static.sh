#!/usr/bin/env sh
set -eu

OUT="${OUT:-dist/fuse-overlayfs-static/fuse-overlayfs}"
FUSE_OVERLAYFS_VERSION="${FUSE_OVERLAYFS_VERSION:-v1.17}"
FUSE_OVERLAYFS_REPO="${FUSE_OVERLAYFS_REPO:-https://github.com/containers/fuse-overlayfs.git}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
root_dir="$(pwd -P)"

case "${OUT}" in
  /*) out_path="${OUT}" ;;
  *) out_path="${root_dir}/${OUT}" ;;
esac

workdir="$(mktemp -d)"
src_dir="${workdir}/fuse-overlayfs"
install_dir="${workdir}/install"

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

  apk add --no-cache autoconf automake fuse3-dev libtool make pkgconf
  apk add --no-cache fuse3-static >/dev/null 2>&1 || true
}

ensure_autotools() {
  if command -v autoreconf >/dev/null 2>&1 &&
     command -v aclocal >/dev/null 2>&1 &&
     command -v automake >/dev/null 2>&1 &&
     command -v libtoolize >/dev/null 2>&1; then
    return
  fi

  printf '%s\n' "error: autotools missing; install autoconf automake and libtool first" >&2
  exit 1
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
ensure_autotools
ensure_static_archive libfuse3.a "fuse3-dev and fuse3-static"

export CFLAGS="${CFLAGS:--O2 -pipe}"
export CPPFLAGS="${CPPFLAGS:-}"
export LDFLAGS="${LDFLAGS:--static}"
export PKG_CONFIG_ALL_STATIC="${PKG_CONFIG_ALL_STATIC:-1}"

if [ -z "${PKG_CONFIG:-}" ]; then
  pkg_config_wrapper="${workdir}/pkg-config-static"
  cat > "${pkg_config_wrapper}" <<'EOF'
#!/usr/bin/env sh
set -eu

exec pkg-config --static "$@"
EOF
  chmod 0755 "${pkg_config_wrapper}"
  export PKG_CONFIG="${pkg_config_wrapper}"
fi

git init "${src_dir}" >/dev/null
git -C "${src_dir}" remote add origin "${FUSE_OVERLAYFS_REPO}"
git -C "${src_dir}" fetch --depth 1 origin "refs/tags/${FUSE_OVERLAYFS_VERSION}"
git -C "${src_dir}" checkout --detach FETCH_HEAD >/dev/null

cd "${src_dir}"
if [ -x ./autogen.sh ]; then
  ./autogen.sh
else
  autoreconf -fi
fi

LIBS="-ldl ${LIBS:-}" ./configure \
  --disable-dependency-tracking \
  --prefix="${install_dir}"

make -j"${JOBS}"
make install

cp "${install_dir}/bin/fuse-overlayfs" "${out_path}"
chmod 0755 "${out_path}"

if command -v strip >/dev/null 2>&1; then
  strip "${out_path}" || true
fi

printf '%s\n' "Built static fuse-overlayfs at ${out_path}"

if command -v file >/dev/null 2>&1; then
  file "${out_path}"
fi

if command -v readelf >/dev/null 2>&1; then
  readelf -l "${out_path}" | grep interpreter || true
fi

if command -v scanelf >/dev/null 2>&1; then
  scanelf -n "${out_path}" || true
fi
