#!/usr/bin/env python3
"""Inject a touch tap into sec_touchscreen on the tablet: tab-tap.py X Y [duration_s]."""
import struct
import sys
import time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, BTN_TOOL_FINGER = 0x14a, 0x145
ABS_SLOT, ABS_X_MT, ABS_Y_MT, ABS_TRACK, ABS_TOUCH_MAJOR = 0x2f, 0x35, 0x36, 0x39, 0x30

fd = open("/dev/input/event1", "wb", buffering=0)


def ev(t, c, v):
    fd.write(struct.pack("qqHHi", 0, 0, t, c, v))


def tap(x, y, hold):
    ev(EV_ABS, ABS_SLOT, 0)
    ev(EV_ABS, ABS_TRACK, 1)
    ev(EV_ABS, ABS_X_MT, x)
    ev(EV_ABS, ABS_Y_MT, y)
    ev(EV_ABS, ABS_TOUCH_MAJOR, 5)
    ev(EV_KEY, BTN_TOUCH, 1)
    ev(EV_KEY, BTN_TOOL_FINGER, 1)
    ev(EV_SYN, 0, 0)
    time.sleep(hold)
    ev(EV_ABS, ABS_TRACK, -1)
    ev(EV_KEY, BTN_TOUCH, 0)
    ev(EV_KEY, BTN_TOOL_FINGER, 0)
    ev(EV_SYN, 0, 0)


tap(int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]) if len(sys.argv) > 3 else 0.08)
