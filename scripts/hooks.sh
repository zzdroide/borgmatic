#!/bin/bash
set -euo pipefail
(( EUID == 0 )) || { echo "Error: not root"; exit 1; }
umask 077

cd "$(dirname "$0")/../hooks.d"
# shellcheck source=../config_example/env
source ../config/env
# shellcheck source-path=../hooks.d
source helpers/common.py

case "$1" in
  "$hook_before")
    order_arg=""
    ;;

  "$hook_after"|"$hook_cleanup")
    order_arg="--reverse"
    ;;

  *)
    echo "Error: invalid hook type $1"
    exit 1
    ;;
esac

run-parts --regex="." --report $order_arg --exit-on-error --umask="$(umask)" --arg="$1" .
