#!/usr/bin/env python3
"""
PTY helper: spawns claude-internal inside a real PTY,
relays I/O between stdin/stdout (pipes from Node) and the PTY master fd.

Supports resize via custom escape: \x1b]resize;ROWS;COLS\x07
"""

import os
import sys
import pty
import select
import signal
import struct
import fcntl
import termios
import errno

COMMAND = os.environ.get('BRIDGE_CLI', 'claude-internal')


def set_winsize(fd, rows, cols):
    winsize = struct.pack('HHHH', rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)


def main():
    cols = int(os.environ.get('COLUMNS', '80'))
    rows = int(os.environ.get('LINES', '24'))

    master_fd, slave_fd = pty.openpty()
    set_winsize(master_fd, rows, cols)

    pid = os.fork()
    if pid == 0:
        # Child: become session leader, set controlling terminal, exec CLI
        os.close(master_fd)
        os.setsid()
        fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
        os.dup2(slave_fd, 0)
        os.dup2(slave_fd, 1)
        os.dup2(slave_fd, 2)
        if slave_fd > 2:
            os.close(slave_fd)

        env = os.environ.copy()
        env['TERM'] = 'xterm-256color'
        env['COLORTERM'] = 'truecolor'

        # Try to find the command in PATH
        os.execvpe(COMMAND, [COMMAND], env)
    else:
        # Parent: relay I/O between stdin/stdout and PTY master
        os.close(slave_fd)

        flags = fcntl.fcntl(sys.stdin.fileno(), fcntl.F_GETFL)
        fcntl.fcntl(sys.stdin.fileno(), fcntl.F_SETFL, flags | os.O_NONBLOCK)

        # Buffer for detecting resize escape sequences
        input_buf = b''
        RESIZE_PREFIX = b'\x1b]resize;'
        RESIZE_END = b'\x07'

        def handle_sigchld(sig, frame):
            pass
        signal.signal(signal.SIGCHLD, handle_sigchld)

        try:
            while True:
                try:
                    rlist, _, _ = select.select(
                        [master_fd, sys.stdin.fileno()], [], [], 0.05
                    )
                except (select.error, OSError, ValueError):
                    break

                if master_fd in rlist:
                    try:
                        data = os.read(master_fd, 65536)
                        if not data:
                            break
                        sys.stdout.buffer.write(data)
                        sys.stdout.buffer.flush()
                    except OSError as e:
                        if e.errno == errno.EIO:
                            break
                        raise

                if sys.stdin.fileno() in rlist:
                    try:
                        data = os.read(sys.stdin.fileno(), 65536)
                        if not data:
                            break

                        input_buf += data

                        # Process resize commands mixed with regular input
                        while input_buf:
                            idx = input_buf.find(RESIZE_PREFIX)
                            if idx == -1:
                                # No resize command, write everything to PTY
                                os.write(master_fd, input_buf)
                                input_buf = b''
                            elif idx > 0:
                                # Write data before the resize command
                                os.write(master_fd, input_buf[:idx])
                                input_buf = input_buf[idx:]
                            else:
                                # Starts with resize command
                                end_idx = input_buf.find(RESIZE_END)
                                if end_idx == -1:
                                    # Incomplete, wait for more
                                    break
                                # Parse resize
                                payload = input_buf[len(RESIZE_PREFIX):end_idx]
                                input_buf = input_buf[end_idx + 1:]
                                try:
                                    parts = payload.split(b';')
                                    r, c = int(parts[0]), int(parts[1])
                                    set_winsize(master_fd, r, c)
                                    os.killpg(os.getpgid(pid), signal.SIGWINCH)
                                except (ValueError, IndexError, OSError):
                                    pass
                    except OSError as e:
                        if e.errno == errno.EAGAIN:
                            continue
                        break

                # Check child status
                try:
                    result = os.waitpid(pid, os.WNOHANG)
                    if result[0] != 0:
                        break
                except ChildProcessError:
                    break

        finally:
            os.close(master_fd)
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass


if __name__ == '__main__':
    main()
