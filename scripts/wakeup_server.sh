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
for attempt in {1..20}; do
  if ssh-keyscan -T 1 -t ed25519 -p1701 "$server_ip" >/dev/null 2>&1; then
    exit 0
  fi
  # Output is line-buffered:
  printf '%.0s.' $(seq 1 "$attempt")
  echo ""
done

echo "Error: failed to wakeup/reach server."
exit 1
