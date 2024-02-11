#!/bin/bash
set -euo pipefail

e4_serial=%e4_serial%
reserved_blocks=%reserved_blocks%

tune2fs -r $reserved_blocks /dev/disk/by-uuid/$e4_serial
