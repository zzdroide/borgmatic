#!/bin/bash
set -euo pipefail

server_ip=$1
server_mac=$2

wakeonlan "$server_mac" >/dev/null

hpnssh \
  -oBatchMode=yes \
  -oConnectTimeout=1 \
  -oConnectionAttempts=20 \
  "borg@$server_ip" \
  true
