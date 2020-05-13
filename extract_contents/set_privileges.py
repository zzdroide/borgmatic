# https://github.com/mhammond/pywin32/blob/master/win32/Demos/RegRestoreKey.py

import ntsecuritycon
import win32api
import win32con
import win32security


def set_privileges():
    privs = (
        (win32security.LookupPrivilegeValue('', ntsecuritycon.SE_BACKUP_NAME),
            win32con.SE_PRIVILEGE_ENABLED),
        (win32security.LookupPrivilegeValue('', ntsecuritycon.SE_RESTORE_NAME),
            win32con.SE_PRIVILEGE_ENABLED))
    ph = win32api.GetCurrentProcess()
    th = win32security.OpenProcessToken(
        ph,
        win32con.TOKEN_READ | win32con.TOKEN_ADJUST_PRIVILEGES
    )
    win32security.AdjustTokenPrivileges(th, 0, privs)
    sa = win32security.SECURITY_ATTRIBUTES()
    my_sid = win32security.GetTokenInformation(th, ntsecuritycon.TokenUser)[0]
    sa.SECURITY_DESCRIPTOR.SetSecurityDescriptorOwner(my_sid, 0)
