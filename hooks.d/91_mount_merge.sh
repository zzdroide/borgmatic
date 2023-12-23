#!/bin/bash
set -euo pipefail
source helpers/common.py

case "$1" in
  "$hook_before")
    # For correct mount nesting, the overlay has to be mounted first, and then its nested mounts.
    # But a nested mount requires an empty dir, which has to be created in a lowerdir,
    # but lowerdirs shouldn't be modified while the overlay is active
    # (https://www.kernel.org/doc/html/v6.4/filesystems/overlayfs.html#changes-to-underlying-filesystems).
    #
    # So:
    # - 90_*.sh: mkdir in lowerdir, accumulate mount commands in post_mounts.sh
    # - 91_mount_merge.sh: mount overlay, mount from post_mounts.sh
    # Having post_mounts.sh is better than repeating 90_*.sh logic in 91_*.sh.

    mkdir $merged_dir
    mount -t overlay overlay -o lowerdir=$src_dir:$specialfile_dir $merged_dir

    if [[ -s $post_mounts ]]; then
      # shellcheck source=/dev/null
      source $post_mounts
      rm $post_mounts
    fi
    ;;

  "$hook_after")
    # umount overlay and mounts from 90_*.sh:
    umount --recursive $merged_dir

    rmdir $merged_dir
    ;;
esac
