import socket


def socket_listen_conn_generator(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('', port))
        s.listen(0)
        conn, addr = s.accept()

        #   with conn, conn.makefile(mode='rb') as f:
        #       yield f
        # "On Windows, the file-like object created by makefile() cannot be used
        #  where a file object with a file descriptor is expected,
        #  such as the stream arguments of subprocess.Popen()."

        # Alternative: use a small wrapper for the use case of this program:
        with conn, SockFileWrapper(conn) as f:
            yield f


class SockFileWrapper:
    def __init__(self, sock):
        self.sock = sock

    def __enter__(self):
        self.sock.__enter__()
        return self

    def __exit__(self, *excinfo):
        return self.sock.__exit__(*excinfo)

    def read(self, size):
        return self.sock.recv(size)
