#!/bin/bash
set -euo pipefail
source helpers/common.py

# Synchronize chunks before taking snapshot, to prevent filling it.

case "$1" in
  "$hook_before")
    # TODO: run "borg rinfo >/dev/null" with borgmatic
    ;;
esac
