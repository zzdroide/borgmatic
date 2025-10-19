#!/bin/bash
set -euo pipefail
source helpers/common.py

repo_id=$(yq .repo_id /etc/borgmatic/config/constants.yaml)

case "$1" in
  "$hook_cleanup")
    chown -Rf "$SUDO_USER:$SUDO_USER" \
      "/home/$SUDO_USER/.config/borg/security/$repo_id" \
      "/home/$SUDO_USER/.cache/borg/$repo_id" || true
    ;;
esac
