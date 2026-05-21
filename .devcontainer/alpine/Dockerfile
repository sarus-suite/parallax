FROM alpine:3.22

ARG GO_VERSION=1.24.0

RUN apk add --no-cache \
        bash \
        bats \
        binutils \
        btrfs-progs \
        btrfs-progs-dev \
        build-base \
        ca-certificates \
        curl \
        file \
        fuse-overlayfs \
        git \
        inotify-tools \
        libassuan-dev \
        libseccomp-dev \
        libselinux-dev \
        linux-headers \
        lvm2-dev \
        musl-dev \
        pax-utils \
        podman \
        protobuf-c-dev \
        protobuf-dev \
        pkgconf \
        rsync \
        shadow-uidmap \
        slirp4netns \
        squashfs-tools \
        squashfuse \
        tar \
        gpgme-dev

COPY scripts/install-go.sh /tmp/install-go.sh
RUN chmod 0755 /tmp/install-go.sh && /tmp/install-go.sh "${GO_VERSION}" && rm -f /tmp/install-go.sh

ENV PATH="/usr/local/go/bin:${PATH}"

CMD ["bash"]
