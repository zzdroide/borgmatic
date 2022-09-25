#!/bin/bash

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

# shellcheck disable=SC2046
sfdisk -l --quiet $(cat realdev_*.txt | cut -c 6-8 | sort -u | sed 's/$/_header.bin/')
