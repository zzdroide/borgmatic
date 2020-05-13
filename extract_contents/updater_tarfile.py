import frozen_tarfile as tarfile
# Because _Stream modification relies on internal implementation.

import win32file

from utils import extend_path

BUFSIZE = 16 * 1024


class UpdaterTarFile(tarfile.TarFile):
    def __init__(self, name, mode, stream):
        super().__init__(name, mode, MyStream(stream))

    def makefile(self, tarinfo, targetpath):
        assert tarinfo.sparse is None
        source = self.fileobj
        source.seek(tarinfo.offset_data)

        target_handle = win32file.CreateFileW(
            FileName=extend_path(targetpath),
            DesiredAccess=win32file.GENERIC_WRITE,
            ShareMode=0,    # bonus: block others from opening the file
            SecurityAttributes=None,
            CreationDisposition=win32file.OPEN_EXISTING,
            FlagsAndAttributes=win32file.FILE_FLAG_BACKUP_SEMANTICS
        )
        try:
            copyfileobj(source, target_handle, tarinfo.size)
        finally:
            target_handle.Close()


class MyStream(tarfile._Stream):
    def __init__(self, existing_stream):
        super().__init__(
            existing_stream.name,
            existing_stream.mode,
            existing_stream.comptype,
            existing_stream.fileobj,
            BUFSIZE
        )

    def read(self, size):
        """
        Optimization: skip _read and __read calls. They are called MANY times.
        Although it only reduced run time in 1.8% when WriteFile CPU is the bottleneck.
        """
        c = len(self.buf)
        t = [self.buf]
        while c < size:
            buf = self.fileobj.read(self.bufsize)
            if not buf:
                break
            t.append(buf)
            c += len(buf)
        t = b"".join(t)
        self.buf = t[size:]
        buf = t[:size]

        self.pos += len(buf)
        return buf


def copyfileobj(src, dst, length):
    """Copy length bytes from fileobj src to handle dst."""

    blocks, remainder = divmod(length, src.bufsize)
    for b in range(blocks):
        buf = src.read(src.bufsize)
        if len(buf) < src.bufsize:
            raise tarfile.ReadError("unexpected end of data")
        win32file.WriteFile(dst, buf)

    if remainder != 0:
        buf = src.read(remainder)
        if len(buf) < remainder:
            raise tarfile.ReadError("unexpected end of data")
        win32file.WriteFile(dst, buf)
