#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# This script expects a safe umask set

readonly HOOK_TYPE=$1
source shared/hooks.sh

# Improvement: autodiscover or make configurable
readonly VG="myvg"
readonly LV="mylv"
readonly SNAP_SIZE="2G"

readonly MNT_DIR="/mnt/borg_lvm"
readonly SNAP_NAME="borg_${LV}_snapshot"
readonly SNAP_DEV="/dev/$VG/$SNAP_NAME"

if [[ "$HOOK_TYPE" == "$BEFORE" ]]; then
  $0 $CLEANUP

  command -v docker &>/dev/null && docker image prune --force

  readonly VBOX_BEFORE="/home/$SUDO_USER/VirtualBox VMs/borg_before.sh"
  [ -x "$VBOX_BEFORE" ] && sudo -u "$SUDO_USER" "$VBOX_BEFORE"

  mkdir $MNT_DIR
  lvcreate --size=$SNAP_SIZE --snapshot --permission=r --name=$SNAP_NAME /dev/$VG/$LV
  mount -o ro $SNAP_DEV $MNT_DIR

  # Note: linux backup is not run first (so 02_linux.yaml) because on the first run,
  # chunks cache synchronization occurs, and would consume snapshot space.

  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    echo "Backup will still run, but fail at after_backup hook."
  fi

elif [[ "$HOOK_TYPE" == "$CLEANUP" ]]; then
  findmnt $MNT_DIR >/dev/null && {
    umount $MNT_DIR
    sleep 2   # Otherwise "Logical volume xxxx contains a filesystem in use."
  }
  lvdisplay $SNAP_DEV &>/dev/null && {
    percent=$(lvs --noheadings -o snap_percent $SNAP_DEV)
    rounded=$(echo "$percent" | awk '{print int($1+0.5)}')
    echo "Snapshot usage: $rounded%"
    lvremove --yes $SNAP_DEV
  }
  [[ ! -e $MNT_DIR ]] || rmdir $MNT_DIR

elif [[ "$HOOK_TYPE" == "$AFTER" ]]; then
  $0 $CLEANUP

  # TODO: run once per repo instead of each borgmatic config:
  chown -R "$SUDO_USER:$SUDO_USER" /home/"$SUDO_USER"/{.config,.cache}/borg/
  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    exit 2
  fi
fi
