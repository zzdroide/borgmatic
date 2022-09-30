#!/bin/bash
set -euo pipefail
umask 077
(( EUID == 0 )) || (echo "Error: not root"; exit 1)
cd "$(dirname "$0")"

readonly HOOK_TYPE=$1
source shared/hooks.sh

readonly MNT_DIR="/mnt/borg_root_snapshot"
readonly SNAP_NAME="borg_snapshot"


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

make_and_mount_snapshot() {
  local root_dev=$1 snap_dev=$2

  mkdir $MNT_DIR
  lvcreate -qq --snapshot --extents=100%FREE --permission=r --name=$SNAP_NAME "$root_dev"
  mount -o ro "$snap_dev" $MNT_DIR

  # Note: linux backup is not run first (so 02_linux.yaml) because on the first run,
  # chunks cache synchronization occurs, and would consume snapshot space.
}

umount_and_remove_snapshot() {
  local root_dev=$1 snap_dev=$2

  if findmnt $MNT_DIR >/dev/null; then
    umount $MNT_DIR
    sleep 2   # Otherwise "Logical volume xxxx contains a filesystem in use."
  fi

  if lvdisplay "$snap_dev" &>/dev/null; then
    local percent rounded
    percent=$(lvs --noheadings -o snap_percent "$snap_dev")
    rounded=$(echo "$percent" | awk '{print int($1+0.5)}')
    echo "Snapshot usage: $rounded%"
    lvremove -qq --yes "$snap_dev"
  fi

  [[ ! -e $MNT_DIR ]] || rmdir $MNT_DIR
}

run_hook_before() {
  local root_dev=$1 snap_dev=$2

  $0 $CLEANUP
  prune_docker_images
  run_virtualbox_before_hook
  make_and_mount_snapshot "$root_dev" "$snap_dev"

  # TODO: run once per repo instead of each borgmatic config:
  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    echo "Backup will still run, but fail at after_backup hook."
  fi
}

run_hook_cleanup() {
  local root_dev=$1 snap_dev=$2

  umount_and_remove_snapshot "$root_dev" "$snap_dev"
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

main() {
  local root_dev vg_name snap_dev
  root_dev=$(findmnt --noheadings --output source /)
  vg_name=$(lvs --noheadings -o vg_name "$root_dev" | xargs echo)
  snap_dev="/dev/$vg_name/$SNAP_NAME"

  if [[ "$HOOK_TYPE" == "$BEFORE" ]]; then
    run_hook_before "$root_dev" "$snap_dev"
  elif [[ "$HOOK_TYPE" == "$CLEANUP" ]]; then
    run_hook_cleanup "$root_dev" "$snap_dev"
  elif [[ "$HOOK_TYPE" == "$AFTER" ]]; then
    run_hook_after
  fi
}

main
