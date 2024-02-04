#!/bin/bash
set -euo pipefail

server_ip=$1
server_mac=$2

wakeonlan "$server_mac" >/dev/null

# FIXME: check if server is awake with curl (install nginx on server)
#   hpnssh \
#     -oBatchMode=yes \
#     -oConnectTimeout=1 \
#     -oConnectionAttempts=20 \
#     "borg@$server_ip" \
#     "borg --version"
# Checking with ssh:
# - is too slow (command must be "borg" and 2 hooks have to be called)
# - [obsolete] The consecutive sshs (check awake, borg) fail because the second open_session
#   runs before the first close_session finishes
