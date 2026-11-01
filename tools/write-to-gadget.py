#!/usr/bin/env python3
"""Write a (sparse) image to the tablet's USB mass-storage LUN through udisks, no sudo.

udisks asks for the password once via the desktop polkit dialog.
Only devices whose model is the Linux "File-Stor Gadget" are accepted.
"""
import os
import sys

import gi

gi.require_version("UDisks", "2.0")
from gi.repository import GLib, UDisks  # noqa: E402

CHUNK = 4 * 1024 * 1024


def find_gadget(client, min_size):
    for obj in client.get_object_manager().get_objects():
        block = obj.get_block()
        if block is None or obj.get_partition() is not None:
            continue
        drive = client.get_drive_for_block(block)
        if drive and "File-Stor" in (drive.props.model or "") and block.props.size >= min_size:
            return block
    return None


def main() -> int:
    img = sys.argv[1]
    size = os.path.getsize(img)
    client = UDisks.Client.new_sync(None)
    block = find_gadget(client, size)
    if block is None:
        print("no gadget mass-storage LUN large enough", file=sys.stderr)
        return 1
    print(f"target {block.props.device} ({block.props.size / 2**30:.1f} GiB)")

    opts = GLib.Variant("a{sv}", {"auth.no_user_interaction": GLib.Variant("b", False)})
    ret = block.call_open_for_restore_sync(opts, None, None)
    fd_index, fd_list_out = ret[0], ret[1]
    fd = fd_list_out.get(fd_index.get_handle())

    # Holes are written as zeros too: the target still holds encrypted Android data
    src = os.open(img, os.O_RDONLY)
    pos = 0
    try:
        while pos < size:
            buf = os.pread(src, min(CHUNK, size - pos), pos)
            os.pwrite(fd, buf, pos)
            pos += len(buf)
            print(f"\r{pos / size * 100:5.1f}%  {pos / 2**20:8.0f} MiB", end="", flush=True)
        os.fsync(fd)
    finally:
        os.close(src)
        os.close(fd)
    print("\ndone")
    return 0


if __name__ == "__main__":
    sys.exit(main())
