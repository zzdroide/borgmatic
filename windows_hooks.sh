#!/bin/bash

set -e
# This script expects a safe umask set

content_pre="content_pre"
content_post="content_post"
metadata_pre="metadata_pre"
metadata_post="metadata_post"

hook_type=$1

if [[ "$hook_type" != "$content_pre" ]] \
  && [[ "$hook_type" != "$content_post" ]] \
  && [[ "$hook_type" != "$metadata_pre" ]] \
  && [[ "$hook_type" != "$metadata_post" ]]
then
  echo "Bad hook type: [$hook_type]"
  exit 1
fi


ensure_unmounted() {
  disk=$1
  dev_path=$2

  if findmnt "$dev_path" >/dev/null; then
    echo "Error: $disk ($dev_path) is mounted"
    exit 1
  fi
}


windows_disks_file="windows_disks.cfg"
base_content_mnt="/mnt/borg_windows_content"
base_metadata_dir="/tmp/borg_windows_metadata"

if [[ "$hook_type" == "$metadata_pre" ]]; then
  if [[ -e "$base_metadata_dir" ]]; then
    echo "Error: base_metadata_dir ($base_metadata_dir) already exists"
    exit 1
  fi

  mkdir -p "$base_metadata_dir"
fi


if [[ ! -f $windows_disks_file ]]; then
  echo $windows_disks_file doesnt exist
  exit 1
elif [[ ! -s $windows_disks_file ]]; then
  echo $windows_disks_file is empty
  exit 1
elif [[ ! -r $windows_disks_file ]]; then
  echo $windows_disks_file is not readable
  exit 1
fi
# Let's hope its format is correct

while read -r disk dev_path; do

  if [[ "$hook_type" == "$content_pre" ]]; then
    ensure_unmounted "$disk" "$dev_path"
    mkdir -p "$base_content_mnt/$disk"
    mount -o ro "$dev_path" "$base_content_mnt/$disk"

  elif [[ "$hook_type" == "$content_post" ]]; then
    umount "$base_content_mnt/$disk"
    rmdir "$base_content_mnt/$disk"

  elif [[ "$hook_type" == "$metadata_pre" ]]; then
    ensure_unmounted "$disk" "$dev_path"
    mkfifo "$base_metadata_dir/$disk"

    ntfsclone \
      --metadata --preserve-timestamps \
      --save-image \
      --output - \
      "$dev_path" \
      > "$base_metadata_dir/$disk" &

  elif [[ "$hook_type" == "$metadata_post" ]]; then
    rm "$base_metadata_dir/$disk"

  else
    echo "hook type assertion failed"
    exit 1
  fi
done < windows_disks_file.cfg


if [[ "$hook_type" == "$content_post" ]]; then
  rmdir "$base_content_mnt"
elif [[ "$hook_type" == "$metadata_post" ]]; then
  rmdir "$base_metadata_dir"
fi
