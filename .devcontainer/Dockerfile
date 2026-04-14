FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG GO_VERSION=1.24.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bats \
        btrfs-progs \
        build-essential \
        ca-certificates \
        curl \
        fuse-overlayfs \
        git \
        libbtrfs-dev \
        libdevmapper-dev \
        lvm2 \
        podman \
        slirp4netns \
        squashfs-tools \
        squashfuse \
        uidmap && \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) goarch='amd64' ;; \
      arm64) goarch='arm64' ;; \
      *) echo "Unsupported architecture: ${arch}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${goarch}.tar.gz" -o /tmp/golang.tar.gz; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf /tmp/golang.tar.gz; \
    rm /tmp/golang.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"
