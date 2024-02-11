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
print_lv_serial() {
  blkid --match-tag=UUID --output=value "${bupsrc[devlv]}"
}

get_val() {
  sed -r 's/.+: +//'
}

generate_ext4_reserved_space() {
  local template_path="../restore/machine_specific/ext4_reserved_space.template.sh"
  local generated_path="../restore/machine_specific/ext4_reserved_space-${bupsrc[name]}.generated.sh"

  local e4_serial; e4_serial="$(print_lv_serial)"

  local tune_list; tune_list=$(tune2fs -l "${bupsrc[devlv]}")
  local reserved_blocks; reserved_blocks=$(echo "$tune_list" | grep "Reserved block count:" | get_val)

  sed "
    s/%e4_serial%/$e4_serial/
    s/%reserved_blocks%/$reserved_blocks/
  " \
    < $template_path \
    > "$generated_path"
  chmod 744 "$generated_path"
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

      case "${bupsrc[target]}" in
        "$target_part") true ;;  # Serial not required for part targets, it's embedded in the .img ;)
        "$target_data") print_part_serial >"$serial_file" ;;
        "$target_linux") print_lv_serial >"$serial_file" ;;
      esac

      is_bupsrc_target_linux && {
        echo "${bupsrc[devlv]}" >"$lvdev_file";
        generate_ext4_reserved_space;
      }

      stream_disk_header "$disk_name" >"$header_file"
      ;;

    "$hook_after")
      rm "$part_file"
      is_bupsrc_target_part || rm "$serial_file"
      is_bupsrc_target_linux && rm "$lvdev_file"

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
