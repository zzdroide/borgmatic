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
  disk=$1
  dev_path=$2

  if findmnt "$dev_path" >/dev/null; then
    echo "Error: $disk ($dev_path) is mounted"
    exit 1
  fi
}

windows_disks_file="config/windows_disks.cfg"
base_dir="/mnt/borg_windows"

if [[ "$hook_type" == "$pre" ]]; then
  if [[ -e "$base_dir" ]]; then
    echo "Error: base_dir ($base_dir) already exists"
    exit 1
  fi

  mkdir "$base_dir"
fi


if [[ ! -f $windows_disks_file ]]; then
  echo "$windows_disks_file doesn't exist"
  exit 1
elif [[ ! -s $windows_disks_file ]]; then
  echo "$windows_disks_file is empty"
  exit 1
elif [[ ! -r $windows_disks_file ]]; then
  echo "$windows_disks_file is not readable"
  exit 1
fi
# Let's hope its format is correct

while read -r disk dev_path; do

  mnt_path="$base_dir/$disk"
  pipe_path="$base_dir/$disk.metadata.simg"

  if [[ "$hook_type" == "$pre" ]]; then
    ensure_unmounted "$disk" "$dev_path"
    
    mkdir -p "$mnt_path"
    mount -o ro "$dev_path" "$mnt_path"
    # Optional:
    problematic_files=$(find -L "$mnt_path" -type b -o -type c -o -type p -exec ls -lh {} + || true)
    if [[ "$problematic_files" ]]; then
      echo -e "\nFound the following files that can cause problems with --read-special:"
      echo "$problematic_files"
      exit 1
    fi
    
    mkfifo "$pipe_path"
    ntfsclone \
      --metadata --preserve-timestamps \
      --save-image \
      --output - \
      "$dev_path" \
      > "$pipe_path" &

  elif [[ "$hook_type" == "$post" ]]; then
    umount "$mnt_path"
    rmdir "$mnt_path"

    rm "$pipe_path"

  else
    echo "hook type assertion failed"
    exit 1
  fi
done < $windows_disks_file


if [[ "$hook_type" == "$post" ]]; then
  rmdir "$base_dir"
fi
