#!/bin/bash
set -e
cd "$(dirname "$0")"
# This script expects a safe umask set

ensure_unmounted() {
  part=$1
  dev_path=$2

  if findmnt "$dev_path" >/dev/null; then
    echo "Error: $part ($dev_path) is mounted"
    exit 1
  fi
}

windows_parts_cfg="config/windows_parts.cfg"
base_dir="/mnt/borg_windows"

if [[ -e "$base_dir" ]]; then
  echo "Error: base_dir ($base_dir) already exists"
  exit 1
fi

mkdir "$base_dir"


if [[ ! -f $windows_parts_cfg ]]; then
  echo "$windows_parts_cfg doesn't exist"
  exit 1
elif [[ ! -s $windows_parts_cfg ]]; then
  echo "$windows_parts_cfg is empty"
  exit 1
elif [[ ! -r $windows_parts_cfg ]]; then
  echo "$windows_parts_cfg is not readable"
  exit 1
fi
# Let's hope its format is correct


while read -r part dev_path; do
  ensure_unmounted "$part" "$dev_path"

  realdev_txt_path="$base_dir/${part}_dev.txt"
  realdev=$(realpath "$dev_path")
  echo "$realdev" > "$realdev_txt_path"

  disk_name=$(lsblk -n -o PKNAME "$realdev")
  # From https://borgbackup.readthedocs.io/en/stable/deployment/image-backup.html
  header_size=$(sfdisk -lo Start "/dev/$disk_name" | grep -A1 -P 'Start$' | tail -n1 | xargs echo)
  # No pipe here because files could repeat, and are small.
  dd if="/dev/$disk_name" of="$base_dir/${disk_name}_header.bin" count="$header_size" status=none

  fstype=$(lsblk -n -o FSTYPE "$realdev")
  img_path="$base_dir/$part.img$( [[ $fstype == 'ntfs' ]] && echo .ntfs || echo .raw )"

  if [[ $fstype == 'ntfs' ]]; then
    mkfifo "$img_path"
    ntfsclone --output - "$dev_path" > "$img_path" &
  else
    ln -s "$dev_path" "$img_path"
  fi

done < $windows_parts_cfg
