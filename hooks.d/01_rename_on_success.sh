#!/bin/bash
set -euo pipefail
source helpers/common.py

case "$1" in
  "$hook_after")
    # TODO: https://borgbackup.readthedocs.io/en/stable/usage/rename.html
    ;;
esac
