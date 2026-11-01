#!/usr/bin/env python3
"""Pen test on the tablet.
  pen-test.py view LOG          as the desktop user: full screen GTK window, writes pointer events
  pen-test.py stroke X0 Y0 X1 Y1 [STEPS]   as root: pen stroke into sec_e-pen, raw units, pressure ramp
  pen-test.py axes              as root: raw axis ranges
evdev delivers written events to all readers, so this runs the path libinput, mutter, app.
"""
import fcntl
import struct
import sys
import time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, BTN_TOOL_PEN = 0x14a, 0x140
ABS_X, ABS_Y, ABS_PRESSURE, ABS_DISTANCE = 0, 1, 0x18, 0x19
NODE = "/dev/input/event2"


def absinfo(fd, code):
    buf = bytearray(24)
    fcntl.ioctl(fd, 0x80184540 + code, buf)
    return struct.unpack("6i", buf)


def axes():
    with open(NODE, "rb") as fd:
        for name, code in (("X", ABS_X), ("Y", ABS_Y), ("P", ABS_PRESSURE), ("D", ABS_DISTANCE)):
            print(name, absinfo(fd, code))


def stroke(x0, y0, x1, y1, steps):
    with open(NODE, "rb") as rd:
        pmax = absinfo(rd, ABS_PRESSURE)[2]
    fd = open(NODE, "wb", buffering=0)

    def ev(t, c, v):
        fd.write(struct.pack("qqHHi", 0, 0, t, c, v))

    def syn():
        ev(EV_SYN, 0, 0)

    ev(EV_ABS, ABS_X, x0)
    ev(EV_ABS, ABS_Y, y0)
    ev(EV_ABS, ABS_DISTANCE, 10)
    ev(EV_KEY, BTN_TOOL_PEN, 1)
    syn()
    time.sleep(0.15)
    ev(EV_ABS, ABS_PRESSURE, pmax // 10)
    ev(EV_ABS, ABS_DISTANCE, 0)
    ev(EV_KEY, BTN_TOUCH, 1)
    syn()
    time.sleep(0.03)
    for i in range(1, steps + 1):
        f = i / steps
        ev(EV_ABS, ABS_X, int(x0 + (x1 - x0) * f))
        ev(EV_ABS, ABS_Y, int(y0 + (y1 - y0) * f))
        ev(EV_ABS, ABS_PRESSURE, int(pmax * (0.1 + 0.8 * f)))
        syn()
        time.sleep(0.008)
    ev(EV_ABS, ABS_PRESSURE, 0)
    ev(EV_KEY, BTN_TOUCH, 0)
    syn()
    time.sleep(0.05)
    ev(EV_KEY, BTN_TOOL_PEN, 0)
    syn()


def view(path):
    import gi

    gi.require_version("Gdk", "3.0")
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, Gtk

    log = open(path, "w", buffering=1)
    win = Gtk.Window()
    win.fullscreen()
    win.add_events(Gdk.EventMask.ALL_EVENTS_MASK)

    def on(_w, e):
        dev = e.get_source_device()
        src = dev.get_source().value_nick if dev else "?"
        ok, p = e.get_axis(Gdk.AxisUse.PRESSURE)
        _, x = e.get_axis(Gdk.AxisUse.X)
        _, y = e.get_axis(Gdk.AxisUse.Y)
        w, h = win.get_size()
        log.write(f"{e.type.value_nick} {src} x={x:.1f} y={y:.1f} p={p if ok else -1:.3f} win={w}x{h} name={dev.get_name() if dev else '?'}\n")
        return False

    for sig in ("motion-notify-event", "button-press-event", "button-release-event", "touch-event"):
        win.connect(sig, on)
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()


cmd = sys.argv[1]
if cmd == "axes":
    axes()
elif cmd == "stroke":
    a = list(map(int, sys.argv[2:6]))
    stroke(*a, int(sys.argv[6]) if len(sys.argv) > 6 else 60)
elif cmd == "view":
    view(sys.argv[2])
