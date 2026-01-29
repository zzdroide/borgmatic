#!/bin/bash
set -euo pipefail

export server_ip=$1  # `export` for bash -c below
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
# shellcheck disable=SC2016
if ! timeout 20s bash -c '
  attempt=1
  while ! ssh-keyscan -T 1 -t ed25519 -p1701 "$server_ip" >/dev/null 2>&1; do
    # Output is line-buffered, so print dots in different lines instead of single line:
    printf "%.0s." $(seq 1 "$attempt")
    echo ""
    attempt=$((attempt + 1))
  done
'; then
  echo "Error: failed to wakeup/reach server."
  exit 1
fi
