#!/usr/bin/env sh
set -eu

GO_VERSION="${1:?usage: install-go.sh <go-version>}"

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  *)
    echo "unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" -o /tmp/golang.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/golang.tar.gz
rm -f /tmp/golang.tar.gz
