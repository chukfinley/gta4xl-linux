#!/usr/bin/env python3
"""Run a shell command on the tablet's USB serial console and print its output."""
import os
import sys
import termios
import time
import uuid

DEV = os.environ.get("GTA4XL_TTY", "/dev/ttyACM0")
TIMEOUT = float(os.environ.get("GTA4XL_TIMEOUT", "30"))


def main() -> int:
    cmd = " ".join(sys.argv[1:])
    fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[3] = 0
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 1
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)

    marker = uuid.uuid4().hex[:12]
    os.write(fd, f"stty -echo 2>/dev/null\n{cmd}\necho __END_{marker}_$?__\n".encode())

    buf = b""
    end = f"__END_{marker}_".encode()
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        chunk = os.read(fd, 65536)
        if chunk:
            buf += chunk
            if end in buf and buf.rstrip().endswith(b"__"):
                break
    os.close(fd)

    text = buf.decode(errors="replace").replace("\r", "")
    if end.decode() not in text:
        sys.stdout.write(text)
        print("\n[timeout]", file=sys.stderr)
        return 124
    out, _, rest = text.partition(end.decode())
    lines = out.split("\n")
    if lines and cmd in lines[0]:
        lines = lines[1:]
    sys.stdout.write("\n".join(lines))
    code = rest.split("__")[0]
    return int(code) if code.isdigit() else 0


if __name__ == "__main__":
    sys.exit(main())
