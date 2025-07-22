#!/bin/bash
set -euo pipefail
source helpers/common.py

# Perform checks here to fail early, without wasting time in other expensive before hooks.

unmount_boot_parts() {
  # "is-enabled" also checks for existence
  if systemctl is-enabled boot.mount &>/dev/null; then
    systemctl stop boot.mount
  fi
  if systemctl is-enabled boot-efi.mount &>/dev/null; then
    systemctl stop boot-efi.mount
  fi
}

mount_boot_parts() {
  if systemctl is-enabled boot.mount &>/dev/null; then
    systemctl start boot.mount
  fi
  if systemctl is-enabled boot-efi.mount &>/dev/null; then
    systemctl start boot-efi.mount
  fi
}

ensure_parts_unmounted() {
  reset_bupsrc
  while next_bupsrc; do
    if ! is_bupsrc_target_linux && findmnt "${bupsrc[devpart]}" >/dev/null; then
      echo "Error: ${bupsrc[name]} (${bupsrc[devpart]}) is mounted"
      exit 1
    fi
  done
}

check_ntfs_clean() {
  reset_bupsrc
  while next_bupsrc; do
    if [[ "${bupsrc[ntfs]}" == 1 ]]; then
      # This command prints a message on error, for example:
      # "The disk contains an unclean file system (0, 0)."
      ntfs-3g.probe --readwrite "${bupsrc[devpart]}" || exit $?
    fi
  done
}


case "$1" in
  "$hook_before")
    unmount_boot_parts
    ensure_parts_unmounted
    check_ntfs_clean
    ;;

  "$hook_after" | "$hook_cleanup")
    # Assume they normally should be mounted
    mount_boot_parts
    ;;
esac
