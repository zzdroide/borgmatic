#!/bin/bash
set -euo pipefail

server_ip=$1
server_mac=$2

wakeonlan "$server_mac" >/dev/null

# Wait until awake
curl \
  -fsS \
  --max-time 1 \
  --retry 20 \
  --retry-delay 1 \
  --retry-connrefused \
  "$server_ip"
