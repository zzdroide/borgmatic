#!/bin/bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/hooks.d"
# shellcheck source-path=hooks.d
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
