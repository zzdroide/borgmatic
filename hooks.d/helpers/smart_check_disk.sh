#!/bin/bash
set -euo pipefail
(( EUID == 0 )) || { echo "Not root"; exit 2; }


[[ -b "$1" ]] ||
    { echo "Disk is not present"; exit 2; }


json=$(smartctl -HA --json=c "$1" || true)


echo "$json" | >/dev/null jq -e ".json_format_version == [1,0]" ||
    { echo "json_format_version doesn't match"; exit 2; }


echo "$json" | >/dev/null jq -e ".smart_status.passed" ||
    { echo "Drive self-assessment is bad"; exit 1; }


# smart attributes that when > 0, mean suspicious disk.
# https://www.backblaze.com/blog/what-smart-stats-indicate-hard-drive-failures/
backblaze_attrs=5,187,188,197,198

echo "$json" | >/dev/null jq -e "\
    [.ata_smart_attributes.table[] | select(.id == ($backblaze_attrs))] \
      | any(.raw.value != 0) \
  " &&
    { echo "A relevant attribute is greater than 0"; exit 1; }

exit 0
