#!/usr/bin/env sh
set -eu

VERSION="${RSYNC_VERSION:-3.4.1}"
ROOT_DIR="${ROOT_DIR:-$(pwd)}"
CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/.ci-cache/rsync}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist/rsync-static}"
DOWNLOAD_DIR="${CACHE_DIR}/downloads"
TARBALL="${DOWNLOAD_DIR}/rsync-${VERSION}.tar.gz"
OUTPUT_BIN="${OUT_DIR}/rsync"
SOURCE_URL="${RSYNC_URL:-https://download.samba.org/pub/rsync/src/rsync-${VERSION}.tar.gz}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
WORK_DIR="$(mktemp -d)"
PREFIX_DIR="${WORK_DIR}/prefix"
BUILD_DIR="${WORK_DIR}/build"
SRC_DIR="${BUILD_DIR}/rsync-${VERSION}"

cleanup() {
  if [ "${KEEP_WORKDIR}" = "1" ]; then
    log "keeping build workspace at ${WORK_DIR}"
    return
  fi

  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT HUP INT TERM

log() {
  printf '[build-rsync-static] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

require_file() {
  [ -f "$1" ] || {
    printf 'missing required static library: %s\n' "$1" >&2
    printf '%s\n' 'install the matching Alpine *-static package in the devcontainer and rebuild it' >&2
    exit 1
  }
}

download_if_missing() {
  if [ ! -f "$TARBALL" ]; then
    log "downloading ${SOURCE_URL}"
    curl -fsSL "$SOURCE_URL" -o "$TARBALL"
  fi
}

configure_build() {
  mkdir -p "$DOWNLOAD_DIR" "$BUILD_DIR" "$OUT_DIR"
  download_if_missing

  mkdir -p "$PREFIX_DIR"
  tar -xzf "$TARBALL" -C "$BUILD_DIR"

  cd "$SRC_DIR"

  : "${CC:=gcc}"
  : "${CFLAGS:=-O2}"
  : "${CPPFLAGS:=}"
  : "${LDFLAGS:=-static}"

  export CC CFLAGS CPPFLAGS LDFLAGS

  ./configure \
    --prefix="$PREFIX_DIR" \
    --enable-static \
    --disable-shared \
    --disable-md2man \
    --disable-xxhash \
    --disable-zstd \
    --disable-lz4 \
    --disable-openssl
  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  make install-strip
}

publish_output() {
  cp "${PREFIX_DIR}/bin/rsync" "$OUTPUT_BIN"
  chmod 0755 "$OUTPUT_BIN"

  log "static rsync available at ${OUTPUT_BIN}"

  if command -v file >/dev/null 2>&1; then
    file "$OUTPUT_BIN"
  fi

  if command -v scanelf >/dev/null 2>&1; then
    scanelf -n "$OUTPUT_BIN" || true
  fi

  if command -v readelf >/dev/null 2>&1; then
    readelf -l "$OUTPUT_BIN" | grep interpreter || true
  fi
}

main() {
  require_cmd curl
  require_cmd gcc
  require_cmd make
  require_cmd tar
  require_file /usr/lib/libz.a

  configure_build
  publish_output
}

main "$@"
