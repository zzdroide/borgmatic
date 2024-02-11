#!/bin/bash
set -euo pipefail
source helpers/common.py

# Delete all machine-specific restore scripts. They will be generated again after this hook.
# It will clean up in case a swapfile is changed, a disk is changed, a template file is renamed, etc.

case "$1" in
  "$hook_before")
    rm -f ../restore/machine_specific/*.generated.sh
    ;;
esac
