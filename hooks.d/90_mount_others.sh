#!/bin/bash
set -euo pipefail
source helpers/common.py

readonly hook_type=$1

specialfile_srcs=()

# Shortcut functions for readable logic in this logic-verbose language
is_N0() { [[ "${bupsrc[ntfs]}" == 0 ]] && echo 1; }
is_N1() { [[ "${bupsrc[ntfs]}" == 1 ]] && echo 1; }
is_TP() { [[ "${bupsrc[target]}" == "$target_part" ]] && echo 1; }
is_TD() { [[ "${bupsrc[target]}" == "$target_data" ]] && echo 1; }
is_N0_TP() { [[ "${bupsrc[ntfs]}" == 0 && "${bupsrc[target]}" == "$target_part" ]] && echo 1; }
is_N0_TD() { [[ "${bupsrc[ntfs]}" == 0 && "${bupsrc[target]}" == "$target_data" ]] && echo 1; }
is_N1_TP() { [[ "${bupsrc[ntfs]}" == 1 && "${bupsrc[target]}" == "$target_part" ]] && echo 1; }
is_N1_TD() { [[ "${bupsrc[ntfs]}" == 1 && "${bupsrc[target]}" == "$target_data" ]] && echo 1; }

delete_windows_excluded_files() {
  # As this partition will be backed up by ntfsclone,
  # the ideal would be to have ntfsclone exclude the files so they don't end in the backup,
  # *and* keep them on disk. However this is not supported.
  #
  # So, this only excludes files which can be deleted without further consequences.
  #
  # Reference of typical Windows excludes: https://www.acronis.com/en-us/support/documentation/ATI2022/index.html#cshid=3488

  local mnt_tmp="$tmp_dir/_ntfs_del"

  mkdir "$mnt_tmp"
  mount -o rw "${bupsrc[devpart]}" "$mnt_tmp"
  # Alternative to mount: ntfstruncate.
  #   Disadvantage: its input is inode number, which would have to be parsed from ntfsinfo...
  #   Advantage: doesn't require mounting RW, which has the risk of data loss.
  # This should be quick, so no "trap ... EXIT"

  pushd "$mnt_tmp" >/dev/null
  local rm_rc=0
  rm -fv pagefile.sys hiberfil.sys swapfile.sys || rm_rc=$?

  popd >/dev/null
  umount "$mnt_tmp"
  rmdir "$mnt_tmp"

  if (( rm_rc > 0 )); then
    exit $rm_rc
  fi
}

filter_progress() {
  # shellcheck disable=SC2016
  tr '\r' '\n' | awk '
    /percent completed/ {  # Filter " percent completed"
      if (match($0, /([0-9]+(\.[0-9]+)?) percent completed/, m)) {
        pct = m[1] + 0
        # Print every 16.7% (6 times per 100%)
        if (pct < 100) {
          bucket = int(pct / 16.6667)
        } else {
          bucket = 6
        }
        if (bucket != last_bucket) {
          print
          last_bucket = bucket
        }
      }
      next
    }
    { print }  # Don"t filter others
  '
}

do_ntfsclone() {
  local img_path=$1 ntfsclone_rc_path=$2

  mkfifo "$img_path"

  # When target is data instead of part, some of the metadata still can be useful:
  # shellcheck disable=SC2015
  [[ $(is_TD) ]] && local extra_args="--metadata --save-image" || local extra_args=

  echo null >"$ntfsclone_rc_path"

  # Keep ntfsclone waiting in background:
  {
    local rc=0
    # shellcheck disable=SC2086
    ntfsclone $extra_args --output - "${bupsrc[devpart]}" >"$img_path" || rc=$?
    # Write to file only if it still exists: (we're not on cleanup)
    [[ -e "$ntfsclone_rc_path" ]] && echo $rc >"$ntfsclone_rc_path"
  } >&- 2> >(filter_progress >"$STDERR_ABOVE_BORGMATIC") &
  # Redirection so that output bypasses borgmatic and reaches the terminal.
}

break_pipe() {
  local img_path=$1

  # Break the pipe to close pending ntfsclone,
  # but without hanging ourselves if ntfsclone already exited: (https://unix.stackexchange.com/questions/164391/how-does-cat-file-work/164449#164449)
  read -r -t0 -N0 <>"$img_path" || true
}

print_img_path_extension() {
  [[ $(is_N1_TD) ]] && echo metadata.nc.img
  [[ $(is_N0_TD) ]] && echo MISSINGNO
  [[ "${bupsrc[target]}" == "$target_part" ]] && echo raw.img
  true
}

do_bupsrc() {
  local mnt_dir_src="$src_dir/${bupsrc[name]}"
  local mnt_dir_merged="$merged_dir/${bupsrc[name]}"
  local img_path; img_path="$tmp_dir/${bupsrc[name]}.$(print_img_path_extension)"
  local ntfsclone_rc_path="$img_path.ncrc"

  case "$hook_type" in
    "$hook_before")

      [[ $(is_N1_TP) ]] && delete_windows_excluded_files

      ### ntfsclone
      if [[ $(is_N1) ]]; then
        do_ntfsclone "$img_path" "$ntfsclone_rc_path"
        specialfile_srcs+=("$img_path")
      fi

      ### mount
      if [[ $(is_TD) ]]; then
        mkdir "$mnt_dir_src"
        echo "mount -o ro \"${bupsrc[devpart]}\" \"$mnt_dir_merged\"" >>$post_mounts
      fi

      ### ln
      if [[ $(is_N0_TP) ]]; then
        ln -s "${bupsrc[devpart]}" "$img_path"
        specialfile_srcs+=("$img_path")
      fi
      ;;


    "$hook_after")

      ### ntfsclone
      if [[ $(is_N1) ]]; then
        local ntfsclone_rc; ntfsclone_rc=$(cat "$ntfsclone_rc_path")
        rm "$ntfsclone_rc_path"
        if [[ "$ntfsclone_rc" != "0" ]]; then
          echo "Error: ntfsclone for ${bupsrc[name]}: rc=$ntfsclone_rc"
          touch $error_flag
        fi

        break_pipe "$img_path"
        rm "$img_path"
      fi

      ### mount
      if [[ $(is_TD) ]]; then
        # umount: performed in 91_mount_merge.sh.

        rmdir "$mnt_dir_src"
      fi

      ### ln
      if [[ $(is_N0_TP) ]]; then
        rm "$img_path"
      fi
      ;;

    "$hook_cleanup")
      # There are catch-all hooks that umount and rm -rf,
      # but nothing to close the spawned ntfsclones.

      ### ntfsclone
      if [[ $(is_N1) ]]; then
        rm -f "$ntfsclone_rc_path"   # Prevents async respawn of this file
        [[ -p "$img_path" ]] && break_pipe "$img_path"
      fi
      ;;
  esac
  true
}



if [[ "$hook_type" == "$hook_after" ]]; then
  findmnt $specialfile_dir >/dev/null && umount $specialfile_dir
  rmdir $specialfile_dir
fi

while next_bupsrc; do
  if is_bupsrc_target_linux; then
    continue
  fi

  do_bupsrc
done

if [[ "$hook_type" == "$hook_before" ]]; then
  mkdir $specialfile_dir
  if (( ${#specialfile_srcs[@]} )); then  # if len(specialfile_srcs) != 0:
    specialfile "${specialfile_srcs[@]}" $specialfile_dir
  fi
fi


# Improvement: use partclone to backup only the used sectors (like ntfsclone)
# but for all supported filesystems.
#
# Don't use the partclone image format, because it deduplicates badly.
# (see https://github.com/borgbackup/borg/issues/1928 and https://github.com/borgbackup/borg/issues/1005#issuecomment-362531468)
#
# Use something like:
#     partclone.ext4 --clone --source /dev/sda2 |
#       partclone.ext4 --restore --restore_raw_file --source - >"$img_path"
# so that a full image is saved, but without reading unused areas.
#
# A named pipe can skip the "Partclone can't restore to stdout" error, but then fails with "Illegal seek".
# This feature can be implemented in partclone though:
# if the output is not seekable, replace the two calls to lseek with writes of zeros
# (just as borg does when extracting without "--sparse").
#
# However, using a modified partclone is risky for the integrity of the backups,
# and the non-NTFS "part"-target partitions that I'm backing up, are smaller than a GB (EFI, msftres, boot).
# So not worth it.
#
# Alternatively, partitions could be backed up with:
# - e2image for ext2/3/4
# - ntfsclone for ntfs (already implemented)
# - "data" instead of "part" target for FAT and exFAT
# - and don't care about the other filesystems.
