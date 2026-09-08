#!/usr/bin/env sh
set -eu

OUT="${OUT:-dist/inotifywait-static}"
INOTIFY_TOOLS_VERSION="${INOTIFY_TOOLS_VERSION:-4.23.9.0}"
INOTIFY_TOOLS_REPO="${INOTIFY_TOOLS_REPO:-https://github.com/inotify-tools/inotify-tools.git}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
root_dir="$(pwd -P)"

case "${OUT}" in
  /*) out_path="${OUT}" ;;
  *) out_path="${root_dir}/${OUT}" ;;
esac

workdir="$(mktemp -d)"
src_dir="${workdir}/inotify-tools"
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

ensure_autotools() {
  if command -v autoreconf >/dev/null 2>&1 &&
     command -v aclocal >/dev/null 2>&1 &&
     command -v automake >/dev/null 2>&1 &&
     command -v libtoolize >/dev/null 2>&1; then
    return
  fi

  if command -v apk >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    apk add --no-cache autoconf automake libtool
    return
  fi

  printf '%s\n' "error: autotools missing; install autoconf automake and libtool first" >&2
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
ensure_autotools

export CFLAGS="${CFLAGS:--O2 -pipe}"
export CPPFLAGS="${CPPFLAGS:-}"
export LDFLAGS="${LDFLAGS:--static}"
# Libtool drops plain -static during the final program link for inotify-tools,
# so force an all-static link at make/install time while leaving configure sane.
make_ldflags="${MAKE_LDFLAGS:-${LDFLAGS} -all-static}"

git init "${src_dir}" >/dev/null
git -C "${src_dir}" remote add origin "${INOTIFY_TOOLS_REPO}"
git -C "${src_dir}" fetch --depth 1 origin "refs/tags/${INOTIFY_TOOLS_VERSION}"
git -C "${src_dir}" checkout --detach FETCH_HEAD >/dev/null

cd "${src_dir}"
autoreconf -fi

./configure \
  --disable-dependency-tracking \
  --disable-shared \
  --enable-static \
  --prefix="${install_dir}"

make -j"${JOBS}" LDFLAGS="${make_ldflags}"
make LDFLAGS="${make_ldflags}" install

cp "${install_dir}/bin/inotifywait" "${out_path}"
chmod 0755 "${out_path}"

if command -v strip >/dev/null 2>&1; then
  strip "${out_path}" || true
fi

printf '%s\n' "Built static inotifywait at ${out_path}"

if command -v file >/dev/null 2>&1; then
  file "${out_path}"
fi

if command -v readelf >/dev/null 2>&1; then
  readelf -l "${out_path}" | grep interpreter || true
fi

if command -v scanelf >/dev/null 2>&1; then
  scanelf -n "${out_path}" || true
fi
