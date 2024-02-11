#!/bin/bash
set -euo pipefail

part_serial=%part_serial%
reserved_blocks=%reserved_blocks%

tune2fs -r $reserved_blocks /dev/disk/by-uuid/$part_serial
