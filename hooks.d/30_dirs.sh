#!/bin/bash
set -euo pipefail
source helpers/common.py

case "$1" in
  "$hook_cleanup")
    rm -rfv --one-file-system $base_dir
    # "-v": alert that something was not properly deleted by the "after" hook
    ;;

  "$hook_before")
    mkdir \
      $base_dir/ \
      $src_dir/ \
      $tmp_dir/
    ;;

  "$hook_after")
    rc=0
    if [[ -e $error_flag ]]; then
      rc=1
      rm $error_flag
      echo "Exiting with 1 because error_flag exists."
    fi

    rmdir \
      $src_dir/ \
      $tmp_dir/ \
      $base_dir/

    exit $rc
    ;;
esac
