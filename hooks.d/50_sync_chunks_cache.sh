#!/bin/bash
set -euo pipefail
source helpers/common.py

# Synchronize chunks before taking snapshot, to prevent filling it.

case "$1" in
  "$hook_before")
    borgmatic repo-info >/dev/null
    ;;
esac
