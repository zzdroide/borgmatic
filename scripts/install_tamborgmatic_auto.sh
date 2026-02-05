#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if (( $# == 0 )); then
  echo "Error: missing source"
  exit 1
fi

source_file="automation/tamborgmatic-auto_$1.service"
readonly dest_file="/etc/systemd/system/tamborgmatic-auto.service"

sed -e "s/#user#/$USER/" -e "s/#group#/$(id -gn)/" "$source_file" |
  sudo tee "$dest_file" >/dev/null

sudo systemctl daemon-reload
if grep -q '^\[Install]$' "$dest_file"; then
  sudo systemctl enable tamborgmatic-auto.service
fi
