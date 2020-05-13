import os
import sys
from colorama import Fore, Style


def get_args():
    try:
        restore_path = sys.argv[1]
    except IndexError:
        print(Fore.RED + 'Error: ' + Style.RESET_ALL + 'no restore path specified.')
        sys.exit(1)

    restore_path = os.path.join(restore_path, '/')
    # Now restore_path already contains trailing slash,
    # to concatenate strings instead of using path.join repeatedly.
    # Note: tar member names also have '/' instead of '\\'.

    try:
        port = int(sys.argv[2])
    except IndexError:
        print(Fore.RED + 'Error: ' + Style.RESET_ALL + 'no port specified.')
        sys.exit(1)

    return restore_path, port


def extend_path(path):
    # https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file#maximum-path-length-limitation
    if len(path) < 260:
        return path
    return '\\\\?\\' + os.path.abspath(path)
