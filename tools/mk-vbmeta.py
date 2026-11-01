#!/usr/bin/env python3
"""Stock vbmeta with the boot and dtbo hash descriptors updated for our images.

The Samsung bootloader refuses a vbmeta with VERIFICATION_DISABLED set ("ODIN MODE (AVB Fail)").
It accepts the unsigned Lineage vbmeta with flags 0, so the hashes are patched in place.
Usage: mk-vbmeta.py STOCK_VBMETA OUT name=image [name=image ...]
"""
import hashlib
import struct
import sys

HEADER = 256
TAG_HASH = 2


def main() -> int:
    stock, out, *pairs = sys.argv[1:]
    images = dict(p.split("=", 1) for p in pairs)
    d = bytearray(open(stock, "rb").read())
    if d[:4] != b"AVB0":
        raise SystemExit("not a vbmeta image")
    auth, aux = struct.unpack_from(">QQ", d, 12)
    desc_off, desc_size = struct.unpack_from(">QQ", d, 96)
    pos = HEADER + auth + desc_off
    end = pos + desc_size
    done = set()
    while pos < end:
        tag, size = struct.unpack_from(">QQ", d, pos)
        if tag == TAG_HASH:
            name_len, salt_len, digest_len = struct.unpack_from(">III", d, pos + 16 + 8 + 32)
            base = pos + 16 + 8 + 32 + 4 * 4 + 60
            name = bytes(d[base:base + name_len]).decode()
            salt = bytes(d[base + name_len:base + name_len + salt_len])
            if name in images:
                data = open(images[name], "rb").read()
                # An image with an AVB footer is hashed up to its original size
                if data[-64:-60] == b"AVBf":
                    size_orig = struct.unpack_from(">Q", data, len(data) - 64 + 12)[0]
                    data = data[:size_orig]
                struct.pack_into(">Q", d, pos + 16, len(data))
                d[base + name_len + salt_len:base + name_len + salt_len + digest_len] = (
                    hashlib.sha256(salt + data).digest()
                )
                done.add(name)
                print(f"{name}: {len(data)} bytes")
        pos += 16 + size
    if done != set(images):
        raise SystemExit(f"descriptor missing for {set(images) - done}")
    open(out, "wb").write(d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
