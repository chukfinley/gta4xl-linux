#!/bin/sh
# Go back to GNOME with gdm. Run as root on the tablet.
systemctl stop session-restore.timer 2>/dev/null
systemctl disable tablet-session.service 2>/dev/null
systemctl stop tablet-session.service 2>/dev/null
rm -f /etc/systemd/system/display-manager.service
ln -sf /usr/lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service
systemctl daemon-reload
systemctl enable gdm.service 2>/dev/null
systemctl start gdm.service
