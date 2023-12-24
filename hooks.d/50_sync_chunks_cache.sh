#!/bin/bash
set -euo pipefail
source helpers/common.py

# Synchronize chunks before taking snapshot, to prevent filling it.

case "$1" in
  "$hook_before")
    # TODO: enable
    #   borgmatic2 rinfo >/dev/null
    ;;
esac
