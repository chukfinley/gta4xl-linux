#!/bin/bash
# T3 Code desktop app from the official ARM64 package. It starts its own backend.
export DEBIAN_FRONTEND=noninteractive
V=0.1.6
cd /var/tmp
curl -fsSLO "https://github.com/pingdotgg/t3code/releases/download/v$V/T3-Code-$V-arm64.deb"
apt-get install -y -qq --no-install-recommends "./T3-Code-$V-arm64.deb"
rm -f "T3-Code-$V-arm64.deb"
systemctl disable --now t3code 2>/dev/null
rm -f /etc/systemd/system/t3code.service
systemctl daemon-reload
# Wayland for touch and the on-screen keyboard
D=/usr/share/applications/t3code.desktop
[ -n "$D" ] && sed -i -E 's#^(Exec=.*) %U#\1 --ozone-platform=wayland --enable-wayland-ime %U#' "$D"
echo "desktop=$D"; grep -m1 '^Exec=' "$D"
echo T3-DONE
