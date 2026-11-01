#!/bin/bash
# System parts of the Wayfire desktop. Run as root on the tablet, you can run it again.
# The session files come from the overlay, see desktop-push.sh.
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq --no-install-recommends alacritty wlr-randr wlopm wf-shell swaybg \
  fonts-inter python3-gi 2>&1 | tail -1
# One terminal: Alacritty
apt-get purge -y -qq gnome-terminal gnome-terminal-data gnome-console nautilus-extension-gnome-terminal 2>&1 | tail -1
rm -f /usr/local/share/applications/org.gnome.Console.desktop
update-alternatives --set x-terminal-emulator /usr/bin/alacritty 2>/dev/null
mkdir -p /etc/xdg/alacritty
cat > /etc/xdg/alacritty/alacritty.toml <<'CONF'
[window]
padding = { x = 8, y = 6 }
decorations = "Full"

[font]
normal = { family = "JetBrains Mono" }
size = 11.0
CONF
# Terminal tools stay, their launchers stay hidden
for a in btop htop vim nvim; do
  [ -f "/usr/local/share/applications/$a.desktop" ] || \
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\nNoDisplay=true\n' "$a" > "/usr/local/share/applications/$a.desktop"
done
update-desktop-database -q /usr/local/share/applications
sync
