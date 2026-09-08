#!/usr/bin/env sh
set -eu

ROOT_DIR="${ROOT_DIR:-$(pwd)}"
FUSERMOUNT3_BIN="${FUSERMOUNT3_BIN:-${ROOT_DIR}/dist/fuse3-static/fusermount3}"

log() {
  printf '[smoke-test-fusermount3] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

assert_contains() {
  needle="$1"
  haystack="$2"
  if ! printf '%s' "$haystack" | grep -F "$needle" >/dev/null 2>&1; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf 'actual output was:\n%s\n' "$haystack" >&2
    exit 1
  fi
}

main() {
  require_cmd "${FUSERMOUNT3_BIN}"

  log "checking --help output"
  help_output="$("${FUSERMOUNT3_BIN}" --help 2>&1)"
  assert_contains "fusermount3" "${help_output}"
  assert_contains "options:" "${help_output}"

  log "checking --version output"
  version_output="$("${FUSERMOUNT3_BIN}" --version 2>&1)"
  assert_contains "fusermount3 version:" "${version_output}"

  log "smoke test passed"
}

main "$@"
