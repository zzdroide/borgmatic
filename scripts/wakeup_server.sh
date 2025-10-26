#!/bin/bash
set -euo pipefail

server_ip=$1
server_mac=${2:-}


if [[ -z "$server_mac" ]]; then
  # No WOL
  exit 0
fi


# Fixes WOL for a server infested with docker networks.
# Assumes a /24 netmask.
# Example: server_ip = 10.20.30.40 --> broadcast_ip = 10.20.30.255
broadcast_ip="${server_ip%.*}.255"

wakeonlan -i "$broadcast_ip" "$server_mac" >/dev/null

# Wait until awake
curl \
  -fsS \
  --max-time 1 \
  --retry 20 \
  --retry-delay 1 \
  --retry-connrefused \
  "$server_ip"
