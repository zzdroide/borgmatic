#!/bin/bash
set -euo pipefail
umask 077
(( EUID == 0 )) || (echo "Error: not root"; exit 1)
cd "$(dirname "$0")"

readonly HOOK_TYPE=$1
source shared/hooks.sh
global_exit=0

readonly PATA_CONFIG="config/pata.cfg"
readonly BASE_DIR="/mnt/borg_pata"
readonly NTFS_EXCLUDES="$BASE_DIR/ntfs_excludes.txt"
readonly NTFSCLONE_FAIL_FLAG="$BASE_DIR/ntfsclone_fail.flag"

readonly TARGET_PART=part
readonly TARGET_DATA=data


ensure_unmounted() {
  local name=$1 dev=$2

  if findmnt "$dev" >/dev/null; then
    echo "Error: $name ($dev) is mounted"
    exit 1
  fi
}

unmount_boot_parts() {
  if systemctl is-enabled boot.mount &>/dev/null; then  # also checks for existence
    systemctl stop boot.mount
  fi
  if systemctl is-enabled boot-efi.mount &>/dev/null; then
    systemctl stop boot-efi.mount
  fi
}

mount_boot_parts() {
  if systemctl is-enabled boot.mount &>/dev/null; then
    systemctl start boot.mount
  fi
  if systemctl is-enabled boot-efi.mount &>/dev/null; then
    systemctl start boot-efi.mount
  fi
}

fail_if_ntfs_dirty() {
  local ntfs=$1 dev=$2

  if [[ $ntfs ]]; then
    # This command prints a message on error, for example: "The disk contains an unclean file system (0, 0)."
    ntfs-3g.probe -w "$dev"
    # The script will exit here on error, because of "set -e".
  fi
}

write_disk_header() {
  local dev=$1
  local disk header_size

  disk=$(lsblk -n -o pkname "$dev")
  header_size=$(sfdisk -l --output Start --json "/dev/$disk" \
                | jq '.partitiontable.partitions[0].start')
  # No "pipe file" here because files could repeat, and are small.
  dd if="/dev/$disk" of="$BASE_DIR/${disk}_header.bin" count="$header_size" status=none
}

check_no_weird_ntfs3g_files() {
  local mnt_path=$1 name=$2

  # TODO: skip if using ntfs3

  # For some reason, ntfs-3g (but not ntfs3) shows some files as pipes.
  # Previously I saw it happen with some more files (can't remember details),
  # currently I can only reproduce it with this path on a Windows 7 installation:
  # C:/Windows/SysWOW64/config/systemprofile/AppData/LocalLow/Microsoft/CryptnetUrlCache/Content/94308059B57B3142E455B38A6EB92015
  # Anyway, exclude them because they hang borg with --read-special.

  [[ $mnt_path == $BASE_DIR/$name ]]  # Assert $mnt_path is this, as $name is used later:

  find -L "$mnt_path" \
      -type b -o -type c -o -type p \
      -printf "pf:$name/%P\n" \
    >> $NTFS_EXCLUDES 2>/dev/null \
    || true
}

make_ntfs_pipe_file() {
  local what=$1 realdev=$2 pipe_path=$3

  if [[ $what == data ]]; then
    local extra_args=
  elif [[ $what == metadata ]]; then
    local extra_args="--metadata --save-image"
  else
    echo "Error: unknown what [$what]"
    exit 1
  fi

  mkfifo "$pipe_path"

  {
    # shellcheck disable=SC2086
    ntfsclone \
          $extra_args \
          --output - \
          "$realdev" \
        > "$pipe_path" \
      || touch $NTFSCLONE_FAIL_FLAG
  } &
}

make_dev_pipe_file() {
  # This is not a pipe but anyway. It's like a hardlink to /dev/sdXY.

  local realdev=$1 pipe_path=$2
  local major_colon_minor major_space_minor

  #     major_space_minor=$(stat --format="%t %T" "$realdev")
  # Oh great. I have no idea why, but it's returning "8 11" when ll shows "8, 17"

  major_colon_minor=$(cat "/sys/$(udevadm info --query=path "$realdev")/dev")
  major_space_minor=$(echo "$major_colon_minor" | tr : " ")

  # shellcheck disable=SC2086
  mknod "$pipe_path" b $major_space_minor

  # Sanity check:
  if ! head -c 1 "$pipe_path" &>/dev/null; then
    echo "Error: created block device for $realdev doesn't work!"
    ls -l "$realdev" "$pipe_path"
    exit 1
  fi
}

run_hook_before_global() {
  $0 $CLEANUP
  mkdir $BASE_DIR
  touch $NTFS_EXCLUDES
  unmount_boot_parts

  # TODO: run once per repo instead of each borgmatic config:
  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    echo "Backup will still run, but fail at after_backup hook."
  fi
}

run_hook_before_each() {
  local name=$1 dev=$2 target=$3 realdev=$4 ntfs=$5 mnt_path=$6 pipe_path=$7 realdev_path=$8

  echo "$realdev" > "$realdev_path"
  # Prefer realdev over dev because it's more readable

  ensure_unmounted "$name" "$realdev"
  fail_if_ntfs_dirty "$ntfs" "$realdev"
  write_disk_header "$realdev"

  if [[ $target == "$TARGET_DATA" ]]; then
    mkdir -p "$mnt_path"
    mount -o ro "$realdev" "$mnt_path"
    # TODO: use ntfs3 if available

    if [[ $ntfs ]]; then
      check_no_weird_ntfs3g_files "$mnt_path" "$name"
      # Although target is data instead of part, some of the metadata can be useful:
      make_ntfs_pipe_file "metadata" "$realdev" "$pipe_path"
    fi

  elif [[ $target == "$TARGET_PART" ]]; then

    if [[ $ntfs ]]; then
      # TODO: ntfstruncate /pagefile.sys, /hiberfil.sys and /swapfile.sys
      make_ntfs_pipe_file "data" "$realdev" "$pipe_path"
    else
      make_dev_pipe_file "$realdev" "$pipe_path"
    fi

  else
    echo "Error: unknown target [$target]"
    exit 1
  fi
}

run_hook_cleanup_each() {
  local name=$1 dev=$2 target=$3 realdev=$4 ntfs=$5 mnt_path=$6 pipe_path=$7 realdev_path=$8

  findmnt "$mnt_path" >/dev/null && umount "$mnt_path"
  [[ -e "$mnt_path" ]] && rmdir "$mnt_path"   # check and rmdir to fail if not a dir
  rm -f "$pipe_path" "$realdev_path"
}

run_hook_cleanup_global() {
  rm -f \
    $NTFS_EXCLUDES \
    $NTFSCLONE_FAIL_FLAG \
    $BASE_DIR/*_header.bin

  [[ ! -e $BASE_DIR ]] || rmdir $BASE_DIR   # Inverted logic because of "set -e"
  mount_boot_parts
}

run_hook_after_global() {
  [ -e $NTFSCLONE_FAIL_FLAG ] && global_exit=1

  $0 $CLEANUP

  # TODO: run once per repo instead of each borgmatic config:
  chown -R "$SUDO_USER:$SUDO_USER" /home/"$SUDO_USER"/{.config,.cache}/borg/
  if root_borg_dirs_exist; then
    echo "$ROOT_BORG_DIRS_EXIST_MSG"
    exit 2
  fi
}

main() {
  local name dev target realdev ntfs mnt_path pipe_path realdev_path

  if [[ $HOOK_TYPE == "$BEFORE" ]]; then
    run_hook_before_global
  fi

  # shellcheck disable=SC2002   # More readable order
  cat $PATA_CONFIG | while read -r name dev target; do
    if [[ ! $target ]]; then
      echo "Error: could't parse line in $PATA_CONFIG:"
      echo "  $name $dev $target"
      exit 1
    fi

    realdev=$(realpath "$dev")

    local fstype
    fstype=$(lsblk -n -o fstype "$realdev")
    [[ $fstype == ntfs ]] && ntfs=x || ntfs=

    mnt_path=$BASE_DIR/$name
    pipe_path=$BASE_DIR/$name$( [[ $target == "$TARGET_DATA" && $ntfs ]] && echo .metadata.simg || echo .img)
    realdev_path=$BASE_DIR/realdev_$name.txt

    if [[ $HOOK_TYPE == "$BEFORE" ]]; then
      run_hook_before_each "$name" "$dev" "$target" "$realdev" "$ntfs" "$mnt_path" "$pipe_path" "$realdev_path"
    elif [[ $HOOK_TYPE == "$CLEANUP" ]]; then
      run_hook_cleanup_each "$name" "$dev" "$target" "$realdev" "$ntfs" "$mnt_path" "$pipe_path" "$realdev_path"
    fi
  done


  if [[ $HOOK_TYPE == "$CLEANUP" ]]; then
    run_hook_cleanup_global
  elif [[ $HOOK_TYPE == "$AFTER" ]]; then
    run_hook_after_global
  fi
}

main
exit $global_exit
