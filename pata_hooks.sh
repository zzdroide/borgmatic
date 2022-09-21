#!/bin/bash
set -euo pipefail
umask 077
(( EUID == 0 )) || (echo "Run borgmatic with sudo"; exit 1)
cd "$(dirname "$0")"

readonly HOOK_TYPE=$1
source shared/hooks.sh

ensure_unmounted() {
  local name=$1
  local dev=$2

  if findmnt "$dev" >/dev/null; then
    echo "Error: $name ($dev) is mounted"
    exit 1
  fi
}

unmount_boot() {
  if systemctl is-enabled boot.mount &>/dev/null; then  # also checks for existence
    systemctl stop boot.mount
  fi
  if systemctl is-enabled boot-efi.mount &>/dev/null; then
    systemctl stop boot-efi.mount
  fi
}

mount_boot() {
  if systemctl is-enabled boot.mount &>/dev/null; then
    systemctl start boot.mount
  fi
  if systemctl is-enabled boot-efi.mount &>/dev/null; then
    systemctl start boot-efi.mount
  fi
}

readonly PATA_CONFIG="config/pata.cfg"
readonly BASE_DIR="/mnt/borg_pata"
readonly NTFS_EXCLUDES="$BASE_DIR/ntfs_excludes.txt"

readonly TARGET_PART=part
readonly TARGET_DATA=data

if [[ $HOOK_TYPE == "$BEFORE" ]]; then
  $0 $CLEANUP
  mkdir $BASE_DIR
  touch $NTFS_EXCLUDES
  unmount_boot

  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    echo "Backup will still run, but fail at after_backup hook."
  fi
fi

# shellcheck disable=SC2002   # More readable order
cat $PATA_CONFIG | while read -r name dev target; do
  if [[ ! $target ]]; then
    echo "Error: could't parse line in $PATA_CONFIG:"
    echo "  $name $dev $target"
    exit 1
  fi

  realdev=$(realpath "$dev")

  fstype=$(lsblk -n -o fstype "$realdev")
  [[ $fstype == ntfs ]] && ntfs=x || ntfs=

  mnt_path=$BASE_DIR/$name
  pipe_path=$BASE_DIR/$name$( [[ $target == "$TARGET_DATA" && $ntfs ]] && echo .metadata.simg || echo .img)
  realdev_path=$BASE_DIR/realdev_$name.txt

  if [[ $HOOK_TYPE == "$BEFORE" ]]; then
    echo "$realdev" > "$realdev_path"
    # Prefer realdev over dev because it's more readable

    ensure_unmounted "$name" "$realdev"

    # TODO: fail if ntfs and dirty

    disk=$(lsblk -n -o pkname "$realdev")
    header_size=$(sfdisk -l --output Start --json "/dev/$disk" \
                  | jq '.partitiontable.partitions[0].start')
    # No "pipe file" here because files could repeat, and are small.
    dd if="/dev/$disk" of="$BASE_DIR/${disk}_header.bin" count="$header_size" status=none

    if [[ $target == "$TARGET_DATA" ]]; then
      mkdir -p "$mnt_path"
      mount -o ro "$realdev" "$mnt_path"
      # TODO: use ntfs3 if available

      if [[ $ntfs ]]; then
        # For some reason, ntfs-3g (but not ntfs3) shows some files as pipes.
        # Previously I saw it happen with some more files (can't remember details),
        # currently I can only reproduce it with this path on a Windows 7 installation:
        # C:/Windows/SysWOW64/config/systemprofile/AppData/LocalLow/Microsoft/CryptnetUrlCache/Content/94308059B57B3142E455B38A6EB92015
        # Anyway, exclude them because they hang borg with --read-special.
        # TODO: skip if using ntfs3
        [[ $mnt_path == $BASE_DIR/$name ]]  # Assert $mnt_path is this, as $name is used later:
        find -L "$mnt_path" \
            -type b -o -type c -o -type p \
            -printf "pf:$name/%P\n" \
          >> $NTFS_EXCLUDES 2>/dev/null \
          || true

        # Although target is data instead of part, some of this metadata can be useful:
        mkfifo "$pipe_path"
        ntfsclone \
            --metadata \
            --save-image \
            --output - \
            "$realdev" \
          > "$pipe_path" &
        # TODO: fail if ntfsclone exits with error
      fi

    elif [[ $target == "$TARGET_PART" ]]; then
      if [[ $ntfs ]]; then
        # TODO: ntfstruncate /pagefile.sys, /hiberfil.sys and /swapfile.sys

        mkfifo "$pipe_path"
        ntfsclone \
            --output - \
            "$realdev" \
          > "$pipe_path" &
        # TODO: fail if ntfsclone exits with error

      else
        # This is not a pipe but anyway. "Hardlink" to /dev/sdXY:
        #     majmin=$(stat --format="%t %T" "$realdev")
        # Oh great. I have no idea why, but it's returning "8 11" when ll shows "8, 17"
        majmin=$(cat "/sys/$(udevadm info --query=path "$realdev")/dev" | tr : " ")
        # shellcheck disable=SC2086
        mknod "$pipe_path" b $majmin

        # Sanity check:
        if ! head -c 1 "$pipe_path" &>/dev/null; then
          echo "Error: created block device for $realdev doesn't work!"
          ls -lh --color=always "$realdev" "$pipe_path"
          exit 1
        fi
      fi

    else
      echo "Error: unknown target [$target]"
      exit 1
    fi

  elif [[ $HOOK_TYPE == "$CLEANUP" ]]; then
    findmnt "$mnt_path" >/dev/null && umount "$mnt_path"
    [[ -e "$mnt_path" ]] && rmdir "$mnt_path"   # check and rmdir to fail if not a dir
    rm -f "$pipe_path" "$realdev_path"

  fi
done


if [[ $HOOK_TYPE == "$CLEANUP" ]]; then
  rm -f $NTFS_EXCLUDES $BASE_DIR/*_header.bin
  [[ ! -e $BASE_DIR ]] || rmdir $BASE_DIR   # Inverted logic because of "set -e"
  mount_boot

elif [[ $HOOK_TYPE == "$AFTER" ]]; then
  $0 $CLEANUP

  # TODO: run once per repo instead of each borgmatic config:
  chown -R "$SUDO_USER:$SUDO_USER" /home/"$SUDO_USER"/{.config,.cache}/borg/
  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    exit 2
  fi
fi
