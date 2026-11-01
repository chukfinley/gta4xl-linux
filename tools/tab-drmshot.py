#!/usr/bin/env python3
"""Dump the framebuffer on the DRM CRTC to a PPM file, works under Wayland: tab-drmshot.py OUT."""
import fcntl
import mmap
import os
import struct
import sys


def iowr(nr, size):
    return 0xC0000000 | (size << 16) | (0x64 << 8) | nr


fd = os.open("/dev/dri/card0", os.O_RDWR)
crtcs = bytearray(4 * 4)
crtc_buf = (ctypes := __import__("ctypes")).create_string_buffer(4 * 4)
res = bytearray(struct.pack("QQQQIIIIIIII", 0, ctypes.addressof(crtc_buf), 0, 0, 0, 4, 0, 0, 0, 0, 0, 0))
fcntl.ioctl(fd, iowr(0xA0, 64), res)
crtc_id = struct.unpack("I", crtc_buf.raw[:4])[0]
crtc = bytearray(struct.pack("QIII", 0, 0, crtc_id, 0) + bytes(104 - 20))
fcntl.ioctl(fd, iowr(0xA1, 104), crtc)
fb_id = struct.unpack_from("I", crtc, 16)[0]
fb = bytearray(struct.pack("7I", fb_id, 0, 0, 0, 0, 0, 0))
fcntl.ioctl(fd, iowr(0xAD, 28), fb)
_, w, h, pitch, bpp, depth, handle = struct.unpack("7I", fb)
md = bytearray(struct.pack("IIQ", handle, 0, 0))
fcntl.ioctl(fd, iowr(0xB3, 16), md)
offset = struct.unpack_from("Q", md, 8)[0]
m = mmap.mmap(fd, pitch * h, mmap.MAP_SHARED, mmap.PROT_READ, offset=offset)
data = m[:]
with open(sys.argv[1], "wb") as out:
    out.write(f"P6\n{w} {h}\n255\n".encode())
    row = bytearray(w * 3)
    for y in range(h):
        line = data[y * pitch:y * pitch + w * 4]
        row[0::3] = line[2::4]
        row[1::3] = line[1::4]
        row[2::3] = line[0::4]
        out.write(row)
print(w, h, pitch, bpp)
