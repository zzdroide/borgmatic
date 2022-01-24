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

ensure_unmounted() {
  part=$1
  dev=$2

  if findmnt "$dev" >/dev/null; then
    echo "Error: $part ($dev) is mounted"
    exit 1
  fi
}

readonly WINDOWS_PARTS_FILE="config/windows_parts.cfg"
readonly BASE_DIR="/mnt/borg_windows"
readonly EXCLUDES_FILE="$BASE_DIR/excludes.txt"

if [[ "$HOOK_TYPE" == "$SETUP" ]]; then
  $0 $CLEANUP
  mkdir "$BASE_DIR"
fi


if [[ ! -f $WINDOWS_PARTS_FILE ]]; then
  echo "$WINDOWS_PARTS_FILE doesn't exist"
  exit 1
elif [[ ! -s $WINDOWS_PARTS_FILE ]]; then
  echo "$WINDOWS_PARTS_FILE is empty"
  exit 1
elif [[ ! -r $WINDOWS_PARTS_FILE ]]; then
  echo "$WINDOWS_PARTS_FILE is not readable"
  exit 1
fi
# Let's hope its format is correct

# TODO: unmount/remount EFI partition

# shellcheck disable=SC2002
cat $WINDOWS_PARTS_FILE | while read -r part dev raw; do

  mnt_path="$BASE_DIR/$part"
  pipe_path="$BASE_DIR/$part$( [[ $raw -eq 1 ]] && echo ".img" || echo ".metadata.simg")"
  realdev_path="$BASE_DIR/realdev_${part}.txt"

  if [[ "$HOOK_TYPE" == "$SETUP" ]]; then
    realdev=$(realpath "$dev")
    echo "$realdev" > "$realdev_path"
    # Prefer realdev over dev because it's more readable

    ensure_unmounted "$part" "$realdev"

    disk=$(lsblk -n -o pkname "$realdev")
    # From https://borgbackup.readthedocs.io/en/stable/deployment/image-backup.html
    header_size=$(sfdisk -lo Start "/dev/$disk" | grep -A1 -P 'Start$' | tail -n1 | xargs echo)
    # No "pipe file" here because files could repeat, and are small.
    dd if="/dev/$disk" of="$BASE_DIR/${disk}_header.bin" count="$header_size" status=none

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
      find -L "$mnt_path" -type b -o -type c -o -type p >> "$EXCLUDES_FILE" 2> /dev/null || true  # TODO: "pf:" ?

      mkfifo "$pipe_path"
      ntfsclone \
        --metadata --preserve-timestamps \
        --save-image \
        --output - \
        "$realdev" \
        > "$pipe_path" &
      # TODO: fail on ntfsclone error when fs dirty
    fi

  elif [[ "$HOOK_TYPE" == "$CLEANUP" ]]; then
    findmnt "$mnt_path" >/dev/null && umount "$mnt_path"
    [[ -e "$mnt_path" ]] && rmdir "$mnt_path"   # check and rmdir to fail if not a dir

    rm -f "$pipe_path" "$realdev_path"

  else
    echo "hook type assertion failed"
    exit 1
  fi
done


if [[ "$HOOK_TYPE" == "$SETUP" ]]; then
  if grep -v /AppData/LocalLow/Microsoft/CryptnetUrlCache/Content/ "$EXCLUDES_FILE"; then
    echo
    echo "Error: the above paths are pipe files not in whitelisted locations."
    exit 1
  fi

  # Include this in backup as a reference of the used "exclude_patterns":
  ln windows.yaml "$BASE_DIR/"

elif [[ "$HOOK_TYPE" == "$CLEANUP" ]]; then
  rm -f $BASE_DIR/*_header.bin "$EXCLUDES_FILE" "$BASE_DIR/windows.yaml"
  [[ ! -e "$BASE_DIR" ]] || rmdir "$BASE_DIR"   # Inverted logic because of "set -e"

else
  echo "hook type assertion failed"
  exit 1
fi
