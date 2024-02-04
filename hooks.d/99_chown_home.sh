#!/bin/bash
set -euo pipefail
source helpers/common.py

case "$1" in
  "$hook_cleanup")
    chown -R "$SUDO_USER:$SUDO_USER" \
      "/home/$SUDO_USER/.local/share/borg/security/$REPO_ID" \
      "/home/$SUDO_USER/.cache/borg/$REPO_ID"
    ;;
esac
