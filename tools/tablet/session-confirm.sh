#!/bin/sh
# The new session works: cancel the restore timer. Run as root on the tablet.
systemctl stop session-restore.timer
