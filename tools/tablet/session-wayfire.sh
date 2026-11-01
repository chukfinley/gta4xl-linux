#!/bin/sh
# Make the Wayfire desktop the default session and start it. Run as root on the tablet.
# A timer restores GNOME after 15 minutes, unless session-confirm.sh cancels it.
# GNOME packages stay on disk. session-gnome.sh goes back.
set -e
systemd-run --on-active=15min --unit=session-restore --collect /usr/local/sbin/session-gnome.sh
systemctl disable gdm.service 2>/dev/null || true
systemctl stop gdm.service 2>/dev/null || true
systemctl daemon-reload
ln -sf /etc/systemd/system/tablet-session.service /etc/systemd/system/display-manager.service
systemctl enable tablet-session.service
systemctl reset-failed tablet-session.service 2>/dev/null || true
systemctl restart tablet-session.service
