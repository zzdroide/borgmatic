#!/bin/bash
set -euo pipefail

print_realdevs() {
  {
    for realdev in realdev_*.txt; do
      # Example: realdev_HDD_NTFS.txt contains "/dev/sdc1".
      # This prints "/dev/sdc1 HDD_NTFS"
      < "$realdev" tr -d "\n"
      echo " $realdev" | sed 's/realdev_//; s/.txt//'
    done
  } | sort
  echo
  echo
}

print_last_paragraph() {
  # https://unix.stackexchange.com/questions/315648/how-to-display-the-final-paragraph-of-a-text-document/315661#315661
  awk -v RS= 'END{if (NR) print}'
}

list_header_partitions() {
  local header=$1
  [[ -s "$header" ]]  # Assert exists

  local pttype; pttype=$(blkid --match-tag PTTYPE --output value "$header")
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
  local header_files; header_files=$(cat realdev_*.txt | cut -c 6-8 | sort -u | sed 's/$/_header.bin/')
  for header in $header_files; do
    list_header_partitions "$header"
  done
}


print_realdevs
list_partitions
