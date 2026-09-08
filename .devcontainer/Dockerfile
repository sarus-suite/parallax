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

COPY scripts/install-go.sh /tmp/install-go.sh
RUN chmod 0755 /tmp/install-go.sh && /tmp/install-go.sh "${GO_VERSION}" && rm -f /tmp/install-go.sh

ENV PATH="/usr/local/go/bin:${PATH}"

CMD ["bash"]
