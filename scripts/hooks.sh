#!/bin/bash
set -euo pipefail
(( EUID == 0 )) || { echo "Error: not root"; exit 1; }
umask 077
cd "$(dirname "$0")/../hooks.d"

# shellcheck source=../hooks.d/helpers/common.py
source helpers/common.py

# shellcheck source=../config_example/env
source ../config/env
# The reason for this messy config in multiple files is:
# - constants.yaml must be self-contained, so that "borgmatic" can be called as is without any wrapper or previous steps
# - Accessing constants.yaml from the hooks would require extracting them with yq (to be installed on every client), or pass them through args... Just duplicate what is required in config/env.
# - *.cfg are easy to loop in bash.

export LVM_SUPPRESS_FD_WARNINGS=x

case "$1" in
  "$hook_before") order_arg="" ;;
  "$hook_after"|"$hook_cleanup") order_arg="--reverse" ;;
  *) echo "Error: invalid hook type $1"; exit 1 ;;
esac

run-parts --regex="." --report $order_arg --exit-on-error --umask="$(umask)" --arg="$1" .
