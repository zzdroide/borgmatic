#!/bin/bash
set -euo pipefail
source helpers/common.py

readonly vbox_before="/home/$SUDO_USER/VirtualBox VMs/scripts/borg_before.sh"

case "$1" in
  "$hook_before")
    if [[ -x "$vbox_before" ]]; then
      sudo -u "$SUDO_USER" "$vbox_before"
    fi
    ;;
esac
