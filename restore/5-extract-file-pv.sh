#!/bin/bash
set -euo pipefail

ARC_NAME=$1
FILE=$2

echo "Sorry, not implemented yet. See script's code and run manually."
exit 1
# FIXME(extract): implement with borgmatic set up so that tamborg alias is not required

# size=$(du --bytes "$FILE" | cut -f1)

# exec \
tamborg extract --stdout ::"$ARC_NAME" "$FILE" |
  pv -pterab --size="$(du --bytes "$FILE" | cut -f1)"
