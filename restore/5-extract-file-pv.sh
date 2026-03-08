#!/bin/bash
set -euo pipefail

ARC_NAME=$1
FILE=$2
SIZE=$3

borgmatic borg extract --stdout ::"$ARC_NAME" "$FILE" | pv -pterab --size="$SIZE"
