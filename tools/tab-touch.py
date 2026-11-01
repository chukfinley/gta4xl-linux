#!/usr/bin/env python3
"""Inject touch gestures into sec_touchscreen on the tablet. Copy to the tablet and run as root.

tab-touch.py hold X Y SECONDS          one finger
tab-touch.py two X1 Y1 X2 Y2 SECONDS   two fingers, down and up together
tab-touch.py move X Y DX DY SECONDS [HOLD]  one finger drag, HOLD seconds at the end
tab-touch.py pinch X Y DIST SECONDS    two fingers move apart
tab-touch.py three X Y DX DY SECONDS   three finger swipe
Coordinates are panel pixels, portrait, 1200x2000.
"""
import struct
import sys
import time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, BTN_TOOL_FINGER = 0x14a, 0x145
ABS_SLOT, ABS_X_MT, ABS_Y_MT, ABS_TRACK, ABS_TOUCH_MAJOR = 0x2f, 0x35, 0x36, 0x39, 0x30

fd = open("/dev/input/event1", "wb", buffering=0)


def ev(t, c, v):
    fd.write(struct.pack("qqHHi", 0, 0, t, c, v))


def down(slot, x, y):
    ev(EV_ABS, ABS_SLOT, slot)
    ev(EV_ABS, ABS_TRACK, 100 + slot)
    ev(EV_ABS, ABS_X_MT, x)
    ev(EV_ABS, ABS_Y_MT, y)
    ev(EV_ABS, ABS_TOUCH_MAJOR, 5)


def move(slot, x, y):
    ev(EV_ABS, ABS_SLOT, slot)
    ev(EV_ABS, ABS_X_MT, x)
    ev(EV_ABS, ABS_Y_MT, y)


def up(slot):
    ev(EV_ABS, ABS_SLOT, slot)
    ev(EV_ABS, ABS_TRACK, -1)


def press():
    ev(EV_KEY, BTN_TOUCH, 1)
    ev(EV_KEY, BTN_TOOL_FINGER, 1)
    syn()


def release():
    ev(EV_KEY, BTN_TOUCH, 0)
    ev(EV_KEY, BTN_TOOL_FINGER, 0)
    syn()


def syn():
    ev(EV_SYN, 0, 0)


a = sys.argv
kind, n = a[1], [float(v) for v in a[2:]]
if kind == "hold":
    down(0, int(n[0]), int(n[1]))
    press()
    time.sleep(n[2])
    up(0)
    release()
elif kind == "two":
    down(0, int(n[0]), int(n[1]))
    down(1, int(n[2]), int(n[3]))
    press()
    time.sleep(n[4])
    up(0)
    up(1)
    release()
elif kind == "move":
    x, y = n[0], n[1]
    down(0, int(x), int(y))
    press()
    steps = max(20, int(n[4] * 120))
    for i in range(1, steps + 1):
        move(0, int(x + n[2] * i / steps), int(y + n[3] * i / steps))
        syn()
        time.sleep(n[4] / steps)
    if len(n) > 5:
        time.sleep(n[5])
    up(0)
    release()
elif kind == "three":
    x, y = n[0], n[1]
    for s in range(3):
        down(s, int(x + 150 * s), int(y))
    press()
    for i in range(1, 21):
        for s in range(3):
            move(s, int(x + 150 * s + n[2] * i / 20), int(y + n[3] * i / 20))
        syn()
        time.sleep(n[4] / 20)
    for s in range(3):
        up(s)
    release()
elif kind == "pinch":
    x, y, d = n[0], n[1], n[2]
    down(0, int(x - 60), int(y))
    down(1, int(x + 60), int(y))
    press()
    for i in range(1, 21):
        move(0, int(x - 60 - d * i / 20), int(y))
        move(1, int(x + 60 + d * i / 20), int(y))
        syn()
        time.sleep(n[3] / 20)
    up(0)
    up(1)
    release()
