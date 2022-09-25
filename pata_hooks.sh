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


validate_disk_and_uuid() {
  local name=$1 dev=$2 realdev=$3 disk=$4

  if [[ ! $disk ]]; then
    echo "Error: could not get disk for $name ($realdev)"
    exit 1
  fi

  if ! echo "$dev" | grep -Eq "^/dev/disk/by-uuid/"; then
    echo "Error: $name's dev is not specified with /dev/disk/by-uuid/: $dev"
    exit 1
  fi

  local uuid instances disks
  # shellcheck disable=SC2001   # would result in horrible escapes
  uuid=$(echo "$dev" | sed 's|/dev/disk/by-uuid/||')
  instances=$(lsblk --raw -o uuid,pkname | grep "$uuid")

  if [[ $(echo "$instances" | wc -l) != 1 ]]; then
    disks=$(echo "$instances" | cut -d" " -f2 | sed 's|^|/dev/|')

    echo "Error: multiple UUIDs for $name." \
      "Refusing to continue as the backup could be made from the wrong one."
    echo
    # shellcheck disable=SC2086
    lsblk --tree -o name,uuid,model,serial $disks

    exit 1
  fi
}

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
  local dev=$1 disk=$2
  local header_size

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

delete_windows_excluded_files() {
  local realdev=$1 mnt_path=$2
  # As this partition will be backed up by ntfsclone,
  # the ideal would be to have ntfsclone exclude the files so they don't end in the backup,
  # *and* they are kept on disk. However this is not supported.
  #
  # So, this only excludes files which can be deleted without further consequences.
  #
  # Reference of typical Windows excludes: https://www.acronis.com/en-us/support/documentation/ATI2022/index.html#cshid=3488

  mkdir -p "$mnt_path"
  mount "$realdev" "$mnt_path"
  # Alternative to mount: ntfstruncate.
  #   Disadvantage: its input is inode number, which would have to be parsed from ntfsinfo...
  #   Advantage: doesn't require mounting RW, which has the risk of data loss
  #              if I blindly run "rm -rf $BASE_DIR" after failure, while mounted.
  #              And without --one-file-system of course.
  # This should be quick, so no "trap ... EXIT"

  pushd "$mnt_path" >/dev/null   # Paranoid protection for "rm -rf $var/sth" --> "rm -rf /sth"
  local rm_rc=0
  rm -fv pagefile.sys hiberfil.sys swapfile.sys || rm_rc=$?

  popd >/dev/null
  umount "$mnt_path"
  rmdir "$mnt_path"

  if (( rm_rc > 0 )); then
    exit $rm_rc
  fi
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
  local realdev=$1 pipe_path=$2
  # This is not a pipe but anyway. It's like a hardlink to /dev/sdXY.

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
  local name=$1 dev=$2 target=$3 realdev=$4 disk=$5 ntfs=$6 mnt_path=$7 pipe_path=$8 realdev_path=$9

  echo "$realdev" > "$realdev_path"
  # Prefer realdev over dev because it's more readable

  validate_disk_and_uuid "$name" "$dev" "$realdev" "$disk"
  ensure_unmounted "$name" "$realdev"
  fail_if_ntfs_dirty "$ntfs" "$realdev"
  write_disk_header "$realdev" "$disk"

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
      delete_windows_excluded_files "$realdev" "$mnt_path"
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
  local name=$1 dev=$2 target=$3 realdev=$4 disk=$5 ntfs=$6 mnt_path=$7 pipe_path=$8 realdev_path=$9

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
  local name dev target realdev disk ntfs mnt_path pipe_path realdev_path

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
    disk=$(lsblk -n -o pkname "$realdev")

    local fstype
    fstype=$(lsblk -n -o fstype "$realdev")
    [[ $fstype == ntfs ]] && ntfs=x || ntfs=

    mnt_path=$BASE_DIR/$name
    pipe_path=$BASE_DIR/$name$( [[ $target == "$TARGET_DATA" && $ntfs ]] && echo .metadata.simg || echo .img)
    realdev_path=$BASE_DIR/realdev_$name.txt

    if [[ $HOOK_TYPE == "$BEFORE" ]]; then
      run_hook_before_each "$name" "$dev" "$target" "$realdev" "$disk" "$ntfs" "$mnt_path" "$pipe_path" "$realdev_path"
    elif [[ $HOOK_TYPE == "$CLEANUP" ]]; then
      run_hook_cleanup_each "$name" "$dev" "$target" "$realdev" "$disk" "$ntfs" "$mnt_path" "$pipe_path" "$realdev_path"
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
