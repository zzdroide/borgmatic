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

unmount_boot() {
  if systemctl is-enabled boot.mount; then
    systemctl stop boot.mount
  fi
  if systemctl is-enabled boot-efi.mount; then
    systemctl stop boot-efi.mount
  fi
}

mount_boot() {
  if systemctl is-enabled boot.mount; then
    systemctl start boot.mount
  fi
  if systemctl is-enabled boot-efi.mount; then
    systemctl start boot-efi.mount
  fi
}

readonly PARTS_CONFIG="config/parts.cfg"
readonly BASE_DIR="/mnt/borg_parts"
readonly NTFS_EXCLUDES="$BASE_DIR/ntfs_excludes.txt"

if [[ "$HOOK_TYPE" == "$SETUP" ]]; then
  $0 $CLEANUP
  mkdir "$BASE_DIR"
  unmount_boot
fi


if [[ ! -f $PARTS_CONFIG ]]; then
  echo "$PARTS_CONFIG doesn't exist"
  exit 1
elif [[ ! -s $PARTS_CONFIG ]]; then
  echo "$PARTS_CONFIG is empty"
  exit 1
elif [[ ! -r $PARTS_CONFIG ]]; then
  echo "$PARTS_CONFIG is not readable"
  exit 1
fi
# Let's hope its format is correct

# shellcheck disable=SC2002
cat $PARTS_CONFIG | while read -r part dev ntfs; do

  mnt_path="$BASE_DIR/$part"
  pipe_path="$BASE_DIR/$part$( [[ $ntfs -eq 1 ]] && echo ".metadata.simg" || echo ".img")"
  realdev_path="$BASE_DIR/realdev_${part}.txt"

  if [[ "$HOOK_TYPE" == "$SETUP" ]]; then
    realdev=$(realpath "$dev")
    echo "$realdev" > "$realdev_path"
    # Prefer realdev over dev because it's more readable

    ensure_unmounted "$part" "$realdev"

    disk=$(lsblk -n -o pkname "$realdev")
    header_size=$(sfdisk -l --output Start --json "/dev/$disk" \
                  | jq '.partitiontable.partitions[0].start')
    # No "pipe file" here because files could repeat, and are small.
    dd if="/dev/$disk" of="$BASE_DIR/${disk}_header.bin" count="$header_size" status=none

    if [[ $ntfs -eq 1 ]]; then
      mkdir -p "$mnt_path"
      mount -o ro "$realdev" "$mnt_path"

      # Windows Vista and higher seem to create weird files that appear as a pipe
      find -L "$mnt_path" -type b -o -type c -o -type p >> "$NTFS_EXCLUDES" 2> /dev/null || true  # TODO: "pf:" ?

      mkfifo "$pipe_path"
      ntfsclone \
        --metadata --preserve-timestamps \
        --save-image \
        --output - \
        "$realdev" \
        > "$pipe_path" &
      # TODO: fail on ntfsclone error when ntfs is dirty

    else
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
  if grep -v /AppData/LocalLow/Microsoft/CryptnetUrlCache/Content/ "$NTFS_EXCLUDES"; then
    echo
    echo "Error: the above paths are pipe files not in whitelisted locations."
    exit 1
  fi

  # Include this in backup as a reference of the used "exclude_patterns":
  ln 02_parts.yaml "$BASE_DIR/"

elif [[ "$HOOK_TYPE" == "$CLEANUP" ]]; then
  rm -f $BASE_DIR/*_header.bin "$NTFS_EXCLUDES" "$BASE_DIR/02_parts.yaml"
  [[ ! -e "$BASE_DIR" ]] || rmdir "$BASE_DIR"   # Inverted logic because of "set -e"
  mount_boot

else
  echo "hook type assertion failed"
  exit 1
fi
