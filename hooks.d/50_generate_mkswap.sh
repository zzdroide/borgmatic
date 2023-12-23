#!/bin/bash
set -euo pipefail
source helpers/common.py

filter_comments() {
  grep -v '^\s*#'
}

filter_swap_print_col1() {
  awk '{if ($3 == "swap") print $1;}'
}

generate_mkswap() {
  local swapfile_path; swapfile_path=$(</etc/fstab filter_comments | filter_swap_print_col1)

  if [[ ! $swapfile_path ]]; then
    # No swapfile
    return 0
  fi

  if (( $(echo "$swapfile_path" | wc -l ) > 1 )); then
    echo -e "Error: only 1 swapfile is supported. Found:\n$swapfile_path"
    return 1
  fi

  if [[ $(findmnt --noheadings --output=target --target="$swapfile_path") != / ]]; then
    # Swapfile not in root filesystem?
    return 0
  fi

  local megabytes; megabytes=$(du --block-size=1M --apparent-size "$swapfile_path" | cut -f1)
  local relative_file; relative_file=$(realpath --relative-to=/ "$swapfile_path")

  sed "
    s|%relative_file%|$relative_file|
    s|%megabytes%|$megabytes|
  " \
    < ../restore/machine_specific/mkswap.template.sh \
    > ../restore/machine_specific/mkswap.generated.sh
  chmod 744 ../restore/machine_specific/mkswap.generated.sh
}

case "$1" in
  "$hook_before") generate_mkswap ;;
esac
