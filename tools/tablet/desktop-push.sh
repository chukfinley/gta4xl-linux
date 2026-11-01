#!/bin/sh
# Copy the session files from the overlay to the tablet. Run on the computer.
cd "$(dirname "$0")/../.." || exit 1
tar -C rootfs/overlay -cf - \
  usr/local/bin/tablet-session usr/local/bin/tablet-session-start usr/local/bin/tablet-brightness usr/local/bin/tablet-rotate \
  usr/local/sbin/gta4xl-powerkey \
  etc/systemd/system/tablet-session.service etc/systemd/system/tablet-session-fallback.service \
  etc/systemd/user/tablet-desktop.target etc/systemd/user/tablet-rotate.service etc/systemd/user/tablet-home.service etc/systemd/user/tablet-clipboard-text.service etc/systemd/user/tablet-clipboard-image.service \
  etc/xdg-desktop-portal/wayfire-portals.conf | tools/tab 'tar -C / --no-same-owner -xf -'
for f in session-gnome session-wayfire session-confirm; do
  cat "tools/tablet/$f.sh" | tools/tab "cat > /usr/local/sbin/$f.sh; chmod 755 /usr/local/sbin/$f.sh"
done
# wayfire.ini names the current plugin file: tools/install-plugin.sh of tablet-desktop writes it
tools/tab 'systemctl daemon-reload; sync'
