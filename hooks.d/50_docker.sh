#!/bin/bash
set -euo pipefail
source helpers/common.py

if ! command -v docker &>/dev/null; then
  # Docker not installed
  exit 0
fi

case "$1" in
  "$hook_before")
    printf "docker image prune: "
    docker image prune --force
    ;;
esac
