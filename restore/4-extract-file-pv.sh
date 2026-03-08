#!/bin/bash
set -euo pipefail

ARC_NAME=$1
FILE=$2
SIZE=$3

borgmatic --verbosity=-1 borg extract --stdout ::"$ARC_NAME" "$FILE" | pv -pterab --size="$SIZE"
# --verbosity=-1 to prevent borgmatic from polluting stdout.
# It's hardcoded to do so :(  https://projects.torsion.org/borgmatic-collective/borgmatic/src/tag/2.0.7/borgmatic/logger.py#L364
