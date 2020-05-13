import os
from threading import Thread, Event, Lock, RLock
from colorama import Fore, Back, Style, Cursor

INTERVAL = 1

(columns, _) = os.get_terminal_size()


class ProgressPrinter(Thread):
    data_lock = Lock()      # Used once for each file, performance critical
    print_lock = RLock()    # Used concurrently only on warnings, not critical
    finished = Event()

    member_name = ''
    file_count = 0
    readonly_count = 0

    prog_extra_lines = 0

    def __init__(self):
        super().__init__(daemon=True)
        self.start()

    def stop(self):
        self.finished.set()

    def is_stopped(self):
        return self.finished.is_set()

    def run(self):
        while not self.finished.wait(INTERVAL):
            self.print_prog()

    def get_prog_deleter(self):
        prog_deleter = '\r\033[K' + (Cursor.UP(1) + '\033[K') * self.prog_extra_lines
        self.prog_extra_lines = 0
        return prog_deleter

    def print_prog(self):
        with self.data_lock:
            fcount, self.file_count = self.file_count, 0
            rcount, self.readonly_count = self.readonly_count, 0
            mname = self.member_name

        with self.print_lock:
            prog_deleter = self.get_prog_deleter()

            texts = [
                format(fcount, '>5'),
                format(rcount, '>5'),
                '  ' + mname,
            ]
            self.prog_extra_lines = sum([len(t) for t in texts]) // columns

            print(
                (prog_deleter + Back.WHITE
                    + Fore.BLACK + texts[0]
                    + Fore.RED + texts[1]
                    + Fore.BLUE + texts[2]
                    + Style.RESET_ALL),
                end='', flush=True)

    def print_msg(self, msg):
        with self.print_lock:
            print(self.get_prog_deleter() + msg)
            if not self.is_stopped():
                self.print_prog()

    def print_warn(self, prefix, msg):
        self.print_msg(Fore.YELLOW + prefix + ' ' + Style.RESET_ALL + msg)

    def add_member(self, member):
        with self.data_lock:
            self.member_name = member.name
            self.file_count += 1

    def add_readonly(self):
        with self.data_lock:
            self.readonly_count += 1
