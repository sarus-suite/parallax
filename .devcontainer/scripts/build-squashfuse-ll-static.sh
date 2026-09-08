#!/usr/bin/env sh
set -eu

OUT="${OUT:-dist/squashfuse-static/squashfuse_ll}"
SQUASHFUSE_VERSION="${SQUASHFUSE_VERSION:-0.6.1}"
SQUASHFUSE_REPO="${SQUASHFUSE_REPO:-https://github.com/vasi/squashfuse.git}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
root_dir="$(pwd -P)"

case "${OUT}" in
  /*) out_path="${OUT}" ;;
  *) out_path="${root_dir}/${OUT}" ;;
esac

workdir="$(mktemp -d)"
src_dir="${workdir}/squashfuse"
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

  apk add --no-cache autoconf automake fuse3-dev libtool pkgconf zlib-dev zstd-dev

  for pkg in fuse3-static zlib-static zstd-static; do
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
ensure_static_archive libfuse3.a "fuse3-dev and fuse3-static"
ensure_static_archive libz.a "zlib-dev and zlib-static"
ensure_static_archive libzstd.a "zstd-dev and zstd-static"

export CFLAGS="${CFLAGS:--O2 -pipe}"
export CPPFLAGS="${CPPFLAGS:-}"
export LDFLAGS="${LDFLAGS:--static}"

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
git -C "${src_dir}" remote add origin "${SQUASHFUSE_REPO}"
git -C "${src_dir}" fetch --depth 1 origin "refs/tags/${SQUASHFUSE_VERSION}"
git -C "${src_dir}" checkout --detach FETCH_HEAD >/dev/null

cd "${src_dir}"
if [ -x ./autogen.sh ]; then
  ./autogen.sh
else
  autoreconf -fi
fi

./configure \
  --disable-dependency-tracking \
  --disable-shared \
  --enable-static \
  --disable-high-level \
  --disable-demo \
  --prefix="${install_dir}"

make -j"${JOBS}" LDFLAGS="${LDFLAGS} -all-static" squashfuse_ll
make LDFLAGS="${LDFLAGS} -all-static" install

cp "${install_dir}/bin/squashfuse_ll" "${out_path}"
chmod 0755 "${out_path}"

if command -v strip >/dev/null 2>&1; then
  strip "${out_path}" || true
fi

printf '%s\n' "Built static squashfuse_ll at ${out_path}"

if command -v file >/dev/null 2>&1; then
  file "${out_path}"
fi

if command -v readelf >/dev/null 2>&1; then
  readelf -l "${out_path}" | grep interpreter || true
fi

if command -v scanelf >/dev/null 2>&1; then
  scanelf -n "${out_path}" || true
fi
