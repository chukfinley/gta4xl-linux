#!/usr/bin/env python3
"""Type text on the tablet through a virtual uinput keyboard: tab-type.py TEXT [enter]."""
import fcntl
import struct
import sys
import time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x5501, 0x5502
KEYS = {c: k for k, c in {2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9",
                          11: "0", 16: "q", 17: "w", 18: "e", 19: "r", 20: "t", 21: "z", 22: "u",
                          23: "i", 24: "o", 25: "p", 30: "a", 31: "s", 32: "d", 33: "f", 34: "g",
                          35: "h", 36: "j", 37: "k", 38: "l", 44: "y", 45: "x", 46: "c", 47: "v",
                          48: "b", 49: "n", 50: "m", 57: " "}.items()}
ENTER = 28
fd = open("/dev/uinput", "wb", buffering=0)
fcntl.ioctl(fd, UI_SET_EVBIT, 1)
for code in list(KEYS.values()) + [ENTER]:
    fcntl.ioctl(fd, UI_SET_KEYBIT, code)
fd.write(struct.pack("80sHHHHi", b"tab-type", 3, 1, 1, 1, 0) + bytes(4 * 64 * 4))
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(1.5)


def key(code):
    for value in (1, 0):
        fd.write(struct.pack("qqHHi", 0, 0, 1, code, value))
        fd.write(struct.pack("qqHHi", 0, 0, 0, 0, 0))
        time.sleep(0.04)


for ch in sys.argv[1]:
    key(KEYS[ch])
if len(sys.argv) > 2:
    key(ENTER)
time.sleep(0.5)
fcntl.ioctl(fd, UI_DEV_DESTROY)
