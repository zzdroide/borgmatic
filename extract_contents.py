#!/usr/bin/env python3

import os
import sys
import tarfile
import subprocess
from itertools import filterfalse


assert (sys.platform == 'cygwin'), 'Error: no Cygwin?'
assert (sys.version_info >= (3, 6)), 'Error: too old Python.'

try:
    restore_path = sys.argv[1]
except IndexError:
    print('Error: no restore path specified', file=sys.stderr)
    sys.exit(1)

restore_path = os.path.join(restore_path, '')
# Now restore_path already contains trailing slash,
# to concatenate strings instead of using path.join repeatedly.

with tarfile.open(fileobj=sys.stdin.buffer, mode='r|') as tar:
    for member in filterfalse(
        lambda m: (
            not m.isreg()       # Skip if not a regular file
            or m.size == 0      # or if it's empty.
        ),
        iter(tar.next, None)
    ):
        target = restore_path + member.name

        try:
            stat = os.stat(target)
        except FileNotFoundError:
            print('Warning: file not found:', member.name, file=sys.stderr)
            continue

        try:
            tar.extract(member, path=restore_path, set_attrs=False)
        except PermissionError:
            # This happens (at least) when the read-only attribute is set.
            # It can be cleared with os.chmod, but not set (on Cygwin).
            # So manipulate it with chattr (ATTRIB is slightly faster but has problems with paths like /cygdrive/...)
            subprocess.run(['chattr', '-r', target], check=True)
            stat2 = os.stat(target)
            if stat.st_mode == stat2.st_mode:
                print("Warning: PermissionError but chattr -r didn't change mode:", member.name, file=sys.stderr)

            try:
                tar.extract(member, path=restore_path, set_attrs=False)
            finally:
                if stat.st_mode != stat2.st_mode:
                    subprocess.run(['chattr', '+r', target], check=True)
                    stat3 = os.stat(target)
                    if stat.st_mode != stat3.st_mode:
                        print(
                            "Warning: chattr -r/+r didn't restore mode "
                            f"({stat.st_mode} --> {stat2.st_mode} --> {stat3.st_mode}): "
                            f"{member.name}",
                            file=sys.stderr,
                        )

        os.utime(target, ns=(stat.st_atime_ns, stat.st_mtime_ns))   # Restore changed mtime


# Note: special hardlink handling is not necessary.
# The first occurrence is stored as a regular file in the .tar (REGTYPE),
# and additional links as LNKTYPE of 0 bytes, which this program skips.
