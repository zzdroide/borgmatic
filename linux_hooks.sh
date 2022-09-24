#!/bin/bash
set -euo pipefail
umask 077
(( EUID == 0 )) || (echo "Error: not root"; exit 1)
cd "$(dirname "$0")"

readonly HOOK_TYPE=$1
source shared/hooks.sh

# Improvement: autodiscover or make configurable
readonly VG="myvg"
readonly LV="mylv"
readonly SNAP_SIZE="2G"

readonly MNT_DIR="/mnt/borg_lvm"
readonly SNAP_NAME="borg_${LV}_snapshot"
readonly SNAP_DEV="/dev/$VG/$SNAP_NAME"


prune_docker_images() {
  if command -v docker &>/dev/null; then
    docker image prune --force
  fi
}

run_virtualbox_before_hook() {
  readonly VBOX_BEFORE="/home/$SUDO_USER/VirtualBox VMs/borg_before.sh"

  if [ -x "$VBOX_BEFORE" ]; then
    sudo -u "$SUDO_USER" "$VBOX_BEFORE"
  fi
}

make_and_mount_lvsnapshot() {
  mkdir $MNT_DIR
  lvcreate --size=$SNAP_SIZE --snapshot --permission=r --name=$SNAP_NAME /dev/$VG/$LV
  mount -o ro $SNAP_DEV $MNT_DIR

  # Note: linux backup is not run first (so 02_linux.yaml) because on the first run,
  # chunks cache synchronization occurs, and would consume snapshot space.
}

umount_and_remove_lvsnapshot() {
  if findmnt $MNT_DIR >/dev/null; then
    umount $MNT_DIR
    sleep 2   # Otherwise "Logical volume xxxx contains a filesystem in use."
  fi

  if lvdisplay $SNAP_DEV &>/dev/null; then
    local percent rounded
    percent=$(lvs --noheadings -o snap_percent $SNAP_DEV)
    rounded=$(echo "$percent" | awk '{print int($1+0.5)}')
    echo "Snapshot usage: $rounded%"
    lvremove --yes $SNAP_DEV
  fi

  [[ ! -e $MNT_DIR ]] || rmdir $MNT_DIR
}

run_hook_before() {
  $0 $CLEANUP
  prune_docker_images
  run_virtualbox_before_hook
  make_and_mount_lvsnapshot

  # TODO: run once per repo instead of each borgmatic config:
  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    echo "Backup will still run, but fail at after_backup hook."
  fi
}

run_hook_cleanup() {
  umount_and_remove_lvsnapshot
}

run_hook_after() {
  $0 $CLEANUP

  # TODO: run once per repo instead of each borgmatic config:
  chown -R "$SUDO_USER:$SUDO_USER" /home/"$SUDO_USER"/{.config,.cache}/borg/
  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    exit 2
  fi
}


if [[ "$HOOK_TYPE" == "$BEFORE" ]]; then
  run_hook_before
elif [[ "$HOOK_TYPE" == "$CLEANUP" ]]; then
  run_hook_cleanup
elif [[ "$HOOK_TYPE" == "$AFTER" ]]; then
  run_hook_after
fi
