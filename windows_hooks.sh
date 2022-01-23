#!/bin/bash
set -e
cd "$(dirname "$0")"
# This script expects a safe umask set

setup="setup"
cleanup="cleanup"
hook_type=$1
if [[ "$hook_type" != "$setup" ]] && [[ "$hook_type" != "$cleanup" ]]; then
  echo "Bad hook type: [$hook_type]"
  exit 1
fi

ensure_unmounted() {
  part=$1
  dev=$2

  if findmnt "$dev" >/dev/null; then
    echo "Error: $part ($dev) is mounted"
    exit 1
  fi
}

windows_parts_file="config/windows_parts.cfg"
base_dir="/mnt/borg_windows"
excludes_file="$base_dir/excludes.txt"

if [[ "$hook_type" == "$setup" ]]; then
  $0 $cleanup
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

# shellcheck disable=SC2002
cat $windows_parts_file | while read -r part dev raw; do

  mnt_path="$base_dir/$part"
  pipe_path="$base_dir/$part$( [[ $raw -eq 1 ]] && echo ".img" || echo ".metadata.simg")"
  realdev_path="$base_dir/realdev_${part}.txt"

  if [[ "$hook_type" == "$setup" ]]; then
    realdev=$(realpath "$dev")
    echo "$realdev" > "$realdev_path"
    # Prefer realdev over dev because it's more readable

    ensure_unmounted "$part" "$realdev"

    disk=$(lsblk -n -o pkname "$realdev")
    # From https://borgbackup.readthedocs.io/en/stable/deployment/image-backup.html
    header_size=$(sfdisk -lo Start "/dev/$disk" | grep -A1 -P 'Start$' | tail -n1 | xargs echo)
    # No "pipe file" here because files could repeat, and are small.
    dd if="/dev/$disk" of="$base_dir/${disk}_header.bin" count="$header_size" status=none

    if [[ $raw -eq 1 ]]; then
      # Previously this was dd to $pipe_path. Now it's not exactly a pipe...
      # "Hardlink" to /dev/sdXY:
      #     majmin=$(stat --format="%t %T" "$realdev")
      # Oh great. I have no idea why, but it's returning "8 11" when ll shows "8, 17"
      majmin=$(cat "/sys/$(udevadm info --query=path "$realdev")/dev" | tr : " ")
      # shellcheck disable=SC2086
      mknod "$pipe_path" b $majmin

      # Sanity check:
      if ! head -c 0 "$pipe_path" 2>/dev/null; then
        echo "Error: created block device for $realdev doesn't work!"
        ls -lh --color=always "$realdev" "$pipe_path"
        exit 1
      fi

    else
      mkdir -p "$mnt_path"
      mount -o ro "$realdev" "$mnt_path"

      # Windows Vista and higher seem to create weird files that appear as a pipe
      find -L "$mnt_path" -type b -o -type c -o -type p >> "$excludes_file" 2> /dev/null || true  # TODO: "pf:" ?

      mkfifo "$pipe_path"
      ntfsclone \
        --metadata --preserve-timestamps \
        --save-image \
        --output - \
        "$realdev" \
        > "$pipe_path" &
      # TODO: fail on ntfsclone error when fs dirty
    fi

  elif [[ "$hook_type" == "$cleanup" ]]; then
    findmnt "$mnt_path" >/dev/null && umount "$mnt_path"
    [[ -e "$mnt_path" ]] && rmdir "$mnt_path"   # check and rmdir to fail if not a dir

    rm -f "$pipe_path" "$realdev_path"

  else
    echo "hook type assertion failed"
    exit 1
  fi
done


if [[ "$hook_type" == "$setup" ]]; then
  if grep -v /AppData/LocalLow/Microsoft/CryptnetUrlCache/Content/ "$excludes_file"; then
    echo
    echo "Error: the above paths are pipe files not in whitelisted locations."
    exit 1
  fi

  # Include this in backup as a reference of the used "exclude_patterns":
  ln windows.yaml "$base_dir/"

elif [[ "$hook_type" == "$cleanup" ]]; then
  rm -f $base_dir/*_header.bin "$excludes_file" "$base_dir/windows.yaml"
  [[ ! -e "$base_dir" ]] || rmdir "$base_dir"   # Inverted logic because of "set -e"

else
  echo "hook type assertion failed"
  exit 1
fi
