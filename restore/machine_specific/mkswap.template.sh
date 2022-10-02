#!/bin/bash
set -euo pipefail

relative_file=%relative_file%
megabytes=%megabytes%

dd if=/dev/zero of="$relative_file" bs=1M count="$megabytes" status=progress
chmod 600 "$relative_file"
mkswap "$relative_file"
