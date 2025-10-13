#!/bin/bash
set -euo pipefail
source helpers/common.py

common_args="\
  --verbosity=-1 `# verbosity=0 prints a "Deleting archives" line` \
  --commands=[]"  # Don't run wakeup_server and others again

case "$1" in
  "$hook_before")
    # For simplicity, have at most one temporary archive.
    # shellcheck disable=SC2086
    borgmatic $common_args delete --archive="${SERVER_USER}(temp)"
    ;;

  "$hook_after")
    # Only after all other $hook_after hooks have succeeded, mark this archive as valid.
    # shellcheck disable=SC2086
    borgmatic $common_args borg -- rename "::${SERVER_USER}(temp)" "${SERVER_USER}-$(date +"%Y-%m-%d_%H:%M")"
    ;;
esac
