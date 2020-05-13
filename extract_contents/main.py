import os
import stat
import sys
from itertools import filterfalse

assert sys.platform == 'win32', 'This script must be run under Windows'
assert sys.version_info >= (3, 4), 'Too old Python'

try:
    import pywintypes
    from winerror import ERROR_ACCESS_DENIED
except ImportError:
    print('Error: no pywin32 (https://github.com/mhammond/pywin32/releases)')
    sys.exit(1)

if sys.version_info < (3, 6):
    try:
        import win_unicode_console
    except ImportError:
        print('Error: old Python without win_unicode_console (pip install win_unicode_console)')
        sys.exit(1)

try:
    import colorama
    from colorama import Fore, Style
except ImportError:
    print('Error: no colorama (pip install colorama)')
    sys.exit(1)

from progress_printer import ProgressPrinter
from set_privileges import set_privileges
from sock import socket_listen_conn_generator
from updater_tarfile import UpdaterTarFile
from utils import get_args, extend_path


def main():
    if sys.version_info < (3, 6):
        win_unicode_console.enable()
    colorama.init()
    restore_path, port = get_args()
    set_privileges()

    print(Fore.GREEN + 'Listening...' + Style.RESET_ALL)
    generator = socket_listen_conn_generator(port)  # Store reference to avoid GC
    conn = next(generator)
    print(Fore.GREEN + 'Connected. Writing...' + Style.RESET_ALL)

    pp = ProgressPrinter()
    with UpdaterTarFile.open(fileobj=conn, mode='r|') as tar:
        for member in filterfalse(
            lambda m: (
                not m.isreg()       # Skip if not a regular file
                or m.size == 0      # or if it's empty.
            ),
            iter(tar.next, None)
        ):
            restore(member, tar, restore_path, pp)
            # Note: special hardlink handling is not necessary.
            # The first occurrence is stored as a regular file in the .tar (REGTYPE),
            # and additional links as LNKTYPE of 0 bytes, which this loop skips.

    pp.stop()
    pp.print_msg(Fore.GREEN + 'Success.' + Style.RESET_ALL)


def restore(member, tar, restore_path, pp):
    target = extend_path(restore_path + member.name)

    try:
        stat1 = os.stat(target)
    except FileNotFoundError:
        pp.print_warn('Warning: file not found:', member.name)
        return

    pp.add_member(member)

    try:
        tar.extract(member, path=restore_path, set_attrs=False)
    except pywintypes.error as e:
        if e.winerror != ERROR_ACCESS_DENIED:
            raise

        # Because of the super privileges, this should only happen
        # when the read-only attribute is set.
        pp.add_readonly()

        os.chmod(target, stat.S_IWRITE)
        stat2 = os.stat(target)
        if stat1.st_mode == stat2.st_mode:
            pp.print_warn("Warning: access denied but chmod S_IWRITE didn't change mode:",
                          member.name)

        try:
            tar.extract(member, path=restore_path, set_attrs=False)
        finally:
            if stat1.st_mode != stat2.st_mode:
                os.chmod(target, stat.S_IREAD)
                stat3 = os.stat(target)
                if stat1.st_mode != stat3.st_mode:
                    pp.print_warn(
                        "Warning: couldn't restore mode ({} --> {} --> {}):".format(
                            stat1.st_mode, stat2.st_mode, stat3.st_mode),
                        member.name)

    os.utime(target, ns=(stat1.st_atime_ns, stat1.st_mtime_ns))   # Restore changed mtime


if __name__ == '__main__':
    main()
