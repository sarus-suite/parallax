#!/usr/bin/env sh
set -eu

OUT="${OUT:-dist/parallax-static}"
VERSION_LDFLAGS="${VERSION_LDFLAGS:-}"
EXTRA_LDFLAGS="${EXTRA_LDFLAGS:-}"

mkdir -p "$(dirname "${OUT}")"

export CGO_ENABLED="${CGO_ENABLED:-1}"
export GOOS="${GOOS:-linux}"
export GOFLAGS="${GOFLAGS:--buildvcs=false}"

if [ -z "${CC:-}" ]; then
  if command -v musl-gcc >/dev/null 2>&1; then
    export CC="musl-gcc"
  elif command -v gcc >/dev/null 2>&1; then
    gcc_machine="$(gcc -dumpmachine 2>/dev/null || true)"
    if printf '%s' "${gcc_machine}" | grep -q 'musl'; then
      export CC="gcc"
    else
      export CC="gcc"
      printf '%s\n' "warning: musl-targeted compiler not detected, falling back to ${CC}" >&2
    fi
  else
    export CC="cc"
    printf '%s\n' "warning: neither musl-gcc nor gcc found, falling back to ${CC}" >&2
  fi
fi

export PKG_CONFIG="${PKG_CONFIG:-$(pwd)/.devcontainer/scripts/pkg-config-static.sh}"
GO_LDFLAGS_DEFAULT="-linkmode external -extldflags '-static' -s -w"
export GO_LDFLAGS="${GO_LDFLAGS:-${GO_LDFLAGS_DEFAULT}}"

go build \
  -ldflags "${GO_LDFLAGS}${VERSION_LDFLAGS:+ ${VERSION_LDFLAGS}}${EXTRA_LDFLAGS:+ ${EXTRA_LDFLAGS}}" \
  -o "${OUT}" \
  .

if command -v file >/dev/null 2>&1; then
  file "${OUT}"
fi

if command -v readelf >/dev/null 2>&1; then
  readelf -l "${OUT}" | grep interpreter || true
fi

if command -v scanelf >/dev/null 2>&1; then
  scanelf -n "${OUT}" || true
fi
