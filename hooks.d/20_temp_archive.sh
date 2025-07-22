#!/bin/bash
set -euo pipefail
source helpers/common.py

case "$1" in
  "$hook_before")
    # For simplicity, have at most one temporary archive.
    borgmatic delete --archive="${SERVER_USER}[temp]"
    ;;
  "$hook_after")
    # Only after all other $hook_after hooks have succeeded, mark this archive as valid.
    borgmatic borg -- rename "${SERVER_USER}[temp]" "${SERVER_USER}-$(date +"%Y-%m-%d_%H:%M")"
    ;;
esac
