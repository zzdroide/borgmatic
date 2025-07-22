#!/usr/bin/env -S PYTHONPATH=. python3
import subprocess
import sys
from pathlib import Path

from helpers.common import base_dir, hook_cleanup

if sys.argv[1] != hook_cleanup:
    sys.exit(0)

with Path("/proc/mounts").open(encoding="utf-8") as f:
    procmounts = f.readlines()

# Second column of /proc/mounts:
fs_files = (row.split(" ")[1] for row in procmounts)
# Filter mounts only under base_dir:
mounts_here = (path for path in fs_files if path.startswith(f"{base_dir}/"))
# Sort by deepest first:
sorted_mounts = sorted(
    mounts_here,
    key=lambda path: path.count("/"),
    reverse=True,
)

if len(sorted_mounts) > 0:
    # umount with multiple arguments and nesting works fine,
    # but as long as arguments are in the correct order haha.
    #
    # Note: `umount --recursive ./mnt1` works for two mounts like `./mnt1` and `./mnt1/mnt2`,
    # but `umount --recursive ./foo` fails for `./foo/mnt1` and `./foo/mnt2`.
    subprocess.run(  # noqa: S603
        (
            "umount",
            "--force",
            "--verbose",    # Alert that something wasn't cleanly unmounted by the "after" hook
            *sorted_mounts,
        ),
        check=True,
    )
