#!/bin/bash
set -euo pipefail
source helpers/common.py

# Synchronize chunks before taking snapshot, to prevent filling it.

case "$1" in
  "$hook_before")
    borgmatic rinfo >/dev/null
    ;;
esac
