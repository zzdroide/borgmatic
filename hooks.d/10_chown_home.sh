#!/bin/bash
set -euo pipefail
source helpers/common.py

case "$1" in
  "$hook_cleanup")
    chown -Rf "$SUDO_USER:$SUDO_USER" \
      "/home/$SUDO_USER/.config/borg/security/$REPO_ID" \
      "/home/$SUDO_USER/.cache/borg/$REPO_ID" || true
    ;;
esac
