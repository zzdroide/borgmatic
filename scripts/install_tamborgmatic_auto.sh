#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

sed -e "s/#user#/$USER/" -e "s/#group#/$(id -gn)/" tamborgmatic-auto.service |
  sudo tee /etc/systemd/system/tamborgmatic-auto.service >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable tamborgmatic-auto.service
