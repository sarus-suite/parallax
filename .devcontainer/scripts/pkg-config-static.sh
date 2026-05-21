#!/usr/bin/env sh
set -eu

exec pkg-config --static "$@"
