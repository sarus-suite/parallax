#!/usr/bin/env sh
set -eu

sh ./.devcontainer/scripts/post-create.sh

mkdir -p dist

printf '%s\n' "Static build entrypoint ready: sh ./.devcontainer/scripts/build-static.sh"
