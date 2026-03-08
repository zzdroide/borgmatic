#!/bin/bash
set -euo pipefail

print_part_files() {
  {
    for part_file in structure/part_*.txt; do
      # Example: part_HDD_NTFS.txt contains "/dev/sdc1".
      # This prints "/dev/sdc1 HDD_NTFS"
      <"$part_file" tr -d "\n"
      echo " $(basename "$part_file")" | sed 's/part_//; s/.txt//'
    done
  } | sort
  echo
  echo
}

part_path2disk_name() {
  # /dev/nvme0n1p1 -> nvme0n1
  # /dev/sda1 -> sda
  sed -E 's|/dev/(nvme[0-9]+n[0-9]+)p[0-9]+|\1|; s|/dev/([a-z]+)[0-9]+|\1|'
}

print_last_paragraph() {
  # https://unix.stackexchange.com/questions/315648/how-to-display-the-final-paragraph-of-a-text-document/315661#315661
  awk -v RS= 'END{if (NR) print}'
}

list_header_partitions() {
  local header=$1
  [[ -s "$header" ]]  # Assert exists

  local pttype; pttype=$(blkid --match-tag=PTTYPE --output=value "$header")
  case $pttype in
    dos)
      echo " MBR"
      sfdisk -l --quiet "$header"
      ;;
    PMBR)  # Detected as protective because the rest of the disk is missing
      echo " GPT  $header"
      gdisk -l "$header" 2>/dev/null | print_last_paragraph
      ;;
    *)
      echo "Error: unhandled PTTYPE=$pttype in $header"
      exit 1
      ;;
  esac
  echo
}

list_partitions() {
  local header_files; header_files=$(
    cat structure/part_*.txt |
      part_path2disk_name |
      sort -u |
      sed 's|^|structure/|; s|$|_header.bin|'
  )
  for header in $header_files; do
    list_header_partitions "$header"
  done
}


print_part_files
list_partitions
