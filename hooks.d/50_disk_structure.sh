#!/bin/bash
set -euo pipefail
source helpers/common.py

readonly hook_type=$1
readonly struct_dir=$src_dir/structure

stream_disk_header() {
  local disk_name=$1

  local header_size; header_size=$(sfdisk -l --output Start --json "/dev/$disk_name" \
                | jq '.partitiontable.partitions[0].start')

  dd if="/dev/$disk_name" count="$header_size" status=none
}

print_part_serial() {
  blkid --match-tag=UUID --output=value "${bupsrc[devpart]}"
}

do_bupsrc() {
  # $disk_name will be "sda", "sdb", etc.
  local disk_name; disk_name=$(lsblk --noheadings --output pkname "${bupsrc[devpart]}" | head -n1)

  if [[ ! -b "/dev/$disk_name" ]]; then
    echo "Error: could not get disk_name for ${bupsrc[name]} (${bupsrc[devpart]})"
    exit 1
  fi

  local part_file="$struct_dir/part_${bupsrc[name]}.txt"
  is_bupsrc_target_linux && local lvdev_file="$struct_dir/lvdev_${bupsrc[name]}.txt"
  local serial_file="$struct_dir/serial_${bupsrc[name]}.txt"

  # These files could repeat and would be overwritten with the same data, it doesn't matter.
  local header_file="$struct_dir/${disk_name}_header.bin"


  case "$hook_type" in
    "$hook_before")
      echo "${bupsrc[devpart]}" >"$part_file"

      is_bupsrc_target_part \
        `# Serial not required for part targets, it's embedded in the .img ;)` \
        || print_part_serial >"$serial_file"

      [[ ${lvdev_file:-} ]] && echo "${bupsrc[devlv]}" >"$lvdev_file"
      # TODO: get_ext4_reserved_space.sh

      stream_disk_header "$disk_name" >"$header_file"
      ;;

    "$hook_after")
      rm "$part_file"
      is_bupsrc_target_part || rm "$serial_file"
      [[ ${lvdev_file:-} ]] && rm "$lvdev_file"

      rm -f "$header_file"
      ;;
  esac
}



[[ "$hook_type" == "$hook_before" ]] && mkdir $struct_dir/

while next_bupsrc; do
  do_bupsrc
done

[[ "$hook_type" == "$hook_after" ]] && rmdir $struct_dir/
true
