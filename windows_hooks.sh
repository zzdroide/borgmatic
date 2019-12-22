#!/bin/bash
set -e
cd "$(dirname "$0")"
# This script expects a safe umask set

pre="pre"
post="post"
hook_type=$1
if [[ "$hook_type" != "$pre" ]] && [[ "$hook_type" != "$post" ]]; then
  echo "Bad hook type: [$hook_type]"
  exit 1
fi

ensure_unmounted() {
  part=$1
  dev_path=$2

  if findmnt "$dev_path" >/dev/null; then
    echo "Error: $part ($dev_path) is mounted"
    exit 1
  fi
}

windows_parts_file="config/windows_parts.cfg"
base_dir="/mnt/borg_windows"
excludes_file="$base_dir/excludes.txt"

if [[ "$hook_type" == "$pre" ]]; then
  if [[ -e "$base_dir" ]]; then
    echo "Error: base_dir ($base_dir) already exists"
    exit 1
  fi

  mkdir "$base_dir"
fi


if [[ ! -f $windows_parts_file ]]; then
  echo "$windows_parts_file doesn't exist"
  exit 1
elif [[ ! -s $windows_parts_file ]]; then
  echo "$windows_parts_file is empty"
  exit 1
elif [[ ! -r $windows_parts_file ]]; then
  echo "$windows_parts_file is not readable"
  exit 1
fi
# Let's hope its format is correct

while read -r part dev_path raw; do

  mnt_path="$base_dir/$part"
  pipe_path="$base_dir/$part$( [[ $raw -eq 1 ]] && echo ".img" || echo ".metadata.simg")"
  realdev_path="$base_dir/${part}_realdev_path.txt"

  if [[ "$hook_type" == "$pre" ]]; then
    ensure_unmounted "$part" "$dev_path"

    realdev=$(realpath "$dev_path")
    echo "$realdev" > "$realdev_path"
    disk_name=$(lsblk -n -o pkname "$realdev")
    # From https://borgbackup.readthedocs.io/en/stable/deployment/image-backup.html
    header_size=$(sfdisk -lo Start "/dev/$disk_name" | grep -A1 -P 'Start$' | tail -n1 | xargs echo)
    # No pipe here because files could repeat, and are small.
    dd if="/dev/$disk_name" of="$base_dir/${disk_name}_header.bin" count="$header_size" status=none

    mkfifo "$pipe_path"

    if [[ $raw -eq 1 ]]; then
      dd if="$dev_path" of="$pipe_path" bs=1M &   # TODO: test replacing with symlink

    else
      mkdir -p "$mnt_path"
      mount -o ro "$dev_path" "$mnt_path"

      # Windows Vista and higher seem to create weird files that appear as a pipe
      find -L "$mnt_path" -type b -o -type c -o -type p >> "$excludes_file" 2> /dev/null || true

      ntfsclone \
        --metadata --preserve-timestamps \
        --save-image \
        --output - \
        "$dev_path" \
        > "$pipe_path" &
    fi

  elif [[ "$hook_type" == "$post" ]]; then
    [[ $raw -ne 1 ]] && umount "$mnt_path" && rmdir "$mnt_path"

    rm "$pipe_path" "$realdev_path"

  else
    echo "hook type assertion failed"
    exit 1
  fi
done < $windows_parts_file


if [[ "$hook_type" == "$post" ]]; then
  rm $base_dir/*_header.bin "$excludes_file"
  rmdir "$base_dir"
fi
