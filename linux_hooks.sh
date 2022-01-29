#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# This script expects a safe umask set

readonly SETUP="setup"
readonly CLEANUP="cleanup"
readonly HOOK_TYPE=$1
if [[ "$HOOK_TYPE" != "$SETUP" ]] && [[ "$HOOK_TYPE" != "$CLEANUP" ]]; then
  echo "Bad hook type: [$HOOK_TYPE]"
  exit 1
fi

readonly VG="myvg"
readonly LV="mylv"
readonly SNAP_SIZE="2G"

readonly MNT_DIR="/mnt/borg_lvm"
readonly SNAP_NAME="borg_${LV}_snapshot"
readonly SNAP_DEV="/dev/$VG/$SNAP_NAME"

if [[ "$HOOK_TYPE" == "$SETUP" ]]; then
  $0 $CLEANUP

  command -v docker &>/dev/null && docker image prune --force

  mkdir $MNT_DIR
  lvcreate --size=$SNAP_SIZE --snapshot --permission=r --name=$SNAP_NAME /dev/$VG/$LV
  mount -o ro $SNAP_DEV $MNT_DIR

elif [[ "$HOOK_TYPE" == "$CLEANUP" ]]; then
  findmnt $MNT_DIR >/dev/null && {
    umount $MNT_DIR
    sleep 2   # Otherwise "Logical volume xxxx contains a filesystem in use."
  }
  lvdisplay $SNAP_DEV &>/dev/null && lvremove --yes $SNAP_DEV
  [[ ! -e $MNT_DIR ]] || rmdir $MNT_DIR

else
  echo "hook type assertion failed"
  exit 1
fi
