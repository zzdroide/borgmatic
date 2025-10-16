#!/bin/bash
set -euo pipefail
source helpers/common.py

# Perform checks here to fail early, without wasting time in other expensive before hooks.

unmount_boot_parts() {
  local boot_dev; boot_dev=$(findmnt --noheadings --output=SOURCE /boot | sed 's|\[.*\]||' || true)

  if [[ -z "$boot_dev" ]]; then
    # /boot unmounted?
    return 0
  elif [[ "$boot_dev" == "$(findmnt --noheadings --output=SOURCE /)" ]]; then
    # No separate boot partition
    return 0
  fi

  # "is-enabled" also checks for existence
  if systemctl is-enabled boot.mount &>/dev/null; then
    systemctl stop boot.mount
  fi
  if systemctl is-enabled boot-efi.mount &>/dev/null; then
    systemctl stop boot-efi.mount
  fi

  if findmnt "$boot_dev" >/dev/null; then
    # Still mounted. This happens to me on Armbian, in which the partition is mounted at /media/mmcboot,
    # and then /boot is a bind mount to /media/mmcboot/boot.
    umount "$boot_dev"
    # Fortunately nothing has to be done on remount, as "sc-start boot.mount" automatically mounts the dependency.
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
