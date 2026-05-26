#!/usr/bin/env sh
set -eu

ROOT_DIR="${ROOT_DIR:-$(pwd)}"
SQUASHFUSE_LL_BIN="${SQUASHFUSE_LL_BIN:-${ROOT_DIR}/dist/squashfuse-static/squashfuse_ll}"
MKSQUASHFS_BIN="${MKSQUASHFS_BIN:-$(command -v mksquashfs)}"
FUSERMOUNT3_BIN="${FUSERMOUNT3_BIN:-$(command -v fusermount3)}"
TMP_DIR="$(mktemp -d)"
SRC_DIR="${TMP_DIR}/src"
IMAGE_PATH="${TMP_DIR}/sample.squashfs"
MOUNT_DIR="${TMP_DIR}/mnt"
EXPECTED_TEXT="hello from squashfuse_ll smoke test"

log() {
  printf '[smoke-test-squashfuse-ll] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

cleanup() {
  if mount | grep -F "on ${MOUNT_DIR} " >/dev/null 2>&1; then
    "${FUSERMOUNT3_BIN}" -u "${MOUNT_DIR}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TMP_DIR}"
}

main() {
  trap cleanup EXIT INT TERM

  require_cmd "${SQUASHFUSE_LL_BIN}"
  require_cmd "${MKSQUASHFS_BIN}"
  require_cmd "${FUSERMOUNT3_BIN}"

  mkdir -p "${SRC_DIR}" "${MOUNT_DIR}"
  printf '%s\n' "${EXPECTED_TEXT}" > "${SRC_DIR}/hello.txt"

  log "creating test squashfs image"
  "${MKSQUASHFS_BIN}" "${SRC_DIR}" "${IMAGE_PATH}" \
    -noappend \
    -comp zstd \
    -no-progress >/dev/null

  log "mounting image with ${SQUASHFUSE_LL_BIN}"
  "${SQUASHFUSE_LL_BIN}" "${IMAGE_PATH}" "${MOUNT_DIR}"

  if [ ! -f "${MOUNT_DIR}/hello.txt" ]; then
    printf 'expected mounted file missing: %s\n' "${MOUNT_DIR}/hello.txt" >&2
    exit 1
  fi

  actual_text="$(cat "${MOUNT_DIR}/hello.txt")"
  if [ "${actual_text}" != "${EXPECTED_TEXT}" ]; then
    printf 'mounted file contents mismatch\nexpected: %s\nactual: %s\n' "${EXPECTED_TEXT}" "${actual_text}" >&2
    exit 1
  fi

  log "unmounting image"
  "${FUSERMOUNT3_BIN}" -u "${MOUNT_DIR}"

  log "smoke test passed"
}

main "$@"
