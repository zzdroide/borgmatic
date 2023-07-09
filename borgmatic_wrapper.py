#!/usr/bin/env python3

import dbus
import subprocess


def inhibit_suspend():
    """
    A long backup (no files cache) failed when the computer went to sleep.

    Maybe it shouldn't have slept while disk was active, maybe it slept anyway
    because disk was inactive while "Remote: Compacting segments".

    Anyway, disable suspend while borgmatic is running.

    One option is to use systemd-inhibit but it doesn't play well with Desktop Environments.
    In Cinnamon, it had to be run with sudo for it to work, and then when the inhibit was released,
    Cinnamon stayed stuck in an "Authentication is required" prompt (required to suspend),
    so it didn't automatically suspend afterwards.

    This systemd-inhibit approach was suggested and tested according to
    https://askubuntu.com/questions/805243/prevent-suspend-before-completion-of-command-run-from-terminal
    (using `org>cinnamon>settings` instead of `org>gnome>settings`)

    Note that inhibitors are automatically released when the process exits
    (https://stackoverflow.com/questions/17478532/powermanagement-inhibit-works-with-dbus-python-but-not-dbus-send),
    so that's why this script is Python instead of Bash.

    So according to https://arnaudr.io/2020/09/25/inhibit-suspending-the-computer-with-gtkapplication/,
    the best and most compatible would be to use
    http://lazka.github.io/pgi-docs/#Gtk-3.0/classes/Application.html#Gtk.Application.inhibit,
    but while searching for an existing app, I got to
    https://codeberg.org/WhyNotHugo/caffeine-ng/src/tag/v4.0.2/caffeine/inhibitors.py#L66
    which works in Cinnamon so let's copy that.
    """

    bus = dbus.SessionBus()
    applicable = "org.gnome.SessionManager" in bus.list_names()

    if applicable:
        proxy1 = bus.get_object("org.gnome.SessionManager", "/org/gnome/SessionManager")
        proxy = dbus.Interface(proxy1, dbus_interface="org.gnome.SessionManager")

        # https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/blob/master/gnome-settings-daemon/org.gnome.SessionManager.xml#L102
        APP_ID = 'Borgmatic'
        REASON = 'Running backup'
        INHIBIT_SUSPEND_FLAG = 4
        TOPLEVEL_XID = 0
        proxy.Inhibit(APP_ID, dbus.UInt32(TOPLEVEL_XID), REASON, dbus.UInt32(INHIBIT_SUSPEND_FLAG))
        # No need to store cookie or call Uninhibit, just exit script.

    else:
        print('Note: not preventing suspension')

inhibit_suspend()

# TODO(upg): run 01_pata.yaml before_backup hooks here, so 02_linux.yaml won't run on failure,
# possibly creating an LVM snapshot and filling it with chunks cache synchronization.

subprocess.run(
    'sudo SSH_AUTH_SOCK="$SSH_AUTH_SOCK" borgmatic -v1 create --progress --stats',
    shell=True,
    check=True,
)
