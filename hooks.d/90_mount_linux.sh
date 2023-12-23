#!/bin/bash
set -euo pipefail
source helpers/common.py

readonly lv_snap_pre=tamborgmatic_snapshot

make_and_mount_snapshot() {
  local hook_type=$1 snap_name=$2 snap_dev=$3 mnt_dir_src=$4 mnt_dir_merged=$5

  mkdir "$mnt_dir_src"
  lvcreate -qq --snapshot --extents=100%FREE --permission=r --name="$snap_name" "${bupsrc[devlv]}"
  echo "mount -o ro \"$snap_dev\" \"$mnt_dir_merged\"" >>$post_mounts
}

umount_and_remove_snapshot() {
  local hook_type=$1 snap_name=$2 snap_dev=$3 mnt_dir_src=$4 mnt_dir_merged=$5

  # umount: performed in 91_mount_merge.sh.

  # Conditional because this is run for cleanup too.
  [[ -e "$mnt_dir_src" ]] && rmdir "$mnt_dir_src"

  if lvdisplay "$snap_dev" &>/dev/null; then
    if [[ "$hook_type" == "$hook_after" ]]; then
      local percent; percent=$(lvs --noheadings -o snap_percent "$snap_dev")
      local rounded; rounded=$(echo "$percent" | awk '{print int($1+0.5)}')
      echo "${bupsrc[name]} snapshot usage: $rounded%"
      # Note: could be unaccurate, as the percentage takes 30-60s to stop updating.
    else # == $hook_cleanup
      # Ensure unmounted so lvremove won't fail.
      umount "$mnt_dir_merged" || true
    fi
    lvremove -qq --yes "$snap_dev"
  fi
}

check_snapshot_overflow() {
  local hook_type=$1 snap_name=$2 snap_dev=$3 mnt_dir_src=$4 mnt_dir_merged=$5

  local status; status=$(dmsetup status "$snap_dev")
  if echo "$status" | grep -qi Invalid; then
    echo "Error: lvm snapshot is invalid"
    journalctl -b -u dm-event.service | grep "$snap_name"
    touch $error_flag
  fi
}

do_bupsrc() {
  local hook_type=$1

  local vg_name; vg_name=$(lvs --noheadings -o vg_name "${bupsrc[devlv]}"); vg_name=${vg_name:2}
  local snap_name="${lv_snap_pre}_${bupsrc[name]}"
  local snap_dev=/dev/$vg_name/$snap_name

  # When using overlayfs, mkdir must be in src/, and mount in merged/.
  # Because mounts don't propagate,
  # and so the files under merged/mnt/ change st_dev, and use native st_ino for borg's inode file cache.
  local mnt_dir_src="$src_dir/${bupsrc[name]}"
  local mnt_dir_merged="$merged_dir/${bupsrc[name]}"

  case "$hook_type" in
    "$hook_before")
      make_and_mount_snapshot    "$hook_type" "$snap_name" "$snap_dev" "$mnt_dir_src" "$mnt_dir_merged"
      ;;
    "$hook_after")
      check_snapshot_overflow    "$hook_type" "$snap_name" "$snap_dev" "$mnt_dir_src" "$mnt_dir_merged"
      umount_and_remove_snapshot "$hook_type" "$snap_name" "$snap_dev" "$mnt_dir_src" "$mnt_dir_merged"
      ;;
    "$hook_cleanup")
      umount_and_remove_snapshot "$hook_type" "$snap_name" "$snap_dev" "$mnt_dir_src" "$mnt_dir_merged"
      ;;
  esac
}

while next_bupsrc; do
  if ! is_bupsrc_target_linux; then
    continue
  fi

  do_bupsrc "$1"
done
