FROM opensuse/leap:15.5

ARG GO_VERSION=1.24.0

RUN zypper --non-interactive refresh && \
    zypper --non-interactive update -y && \
    zypper --non-interactive install -y \
        bats \
        binutils \
        btrfsprogs \
        curl \
        device-mapper-devel \
        file \
        fuse-overlayfs \
        fuse3 \
        gcc \
        git \
        glibc-devel \
        gzip \
        inotify-tools \
        libbtrfs-devel \
        make \
        podman \
        rsync \
        shadow \
        slirp4netns \
        squashfs \
        squashfuse \
        tar \
        wget && \
    zypper clean --all

COPY scripts/install-go.sh /tmp/install-go.sh
RUN chmod 0755 /tmp/install-go.sh && /tmp/install-go.sh "${GO_VERSION}" && rm -f /tmp/install-go.sh

ENV PATH="/usr/local/go/bin:${PATH}"

CMD ["bash"]
