#!/bin/bash
# System parts of the Wayfire desktop. Run as root on the tablet, you can run it again.
# The session files come from the overlay, see desktop-push.sh.
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq --no-install-recommends alacritty wlr-randr wlopm wl-clipboard \
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
# The desktop is Wayfire: no GNOME session, shell, Settings or gdm. GTK apps stay, with their libraries
apt-get purge -y -qq gdm3 gnome-shell gnome-shell-common gnome-shell-extensions gnome-shell-extension-prefs \
  gnome-shell-extension-manager yaru-theme-gnome-shell gnome-session gnome-session-bin gnome-session-common \
  gnome-settings-daemon gnome-settings-daemon-common gnome-control-center gnome-control-center-data \
  xdg-desktop-portal-gnome gnome-tweaks foot wf-shell swaybg sway labwc weston wayfire 2>&1 | tail -1
apt-mark manual libwlroots12t64 >/dev/null
systemctl mask accounts-daemon colord 2>/dev/null
ln -sf /etc/systemd/system/tablet-session.service /etc/systemd/system/display-manager.service
systemctl set-default graphical.target
# Terminal tools stay, their launchers stay hidden
for a in btop htop vim nvim; do
  [ -f "/usr/local/share/applications/$a.desktop" ] || \
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\nNoDisplay=true\n' "$a" > "/usr/local/share/applications/$a.desktop"
done
update-desktop-database -q /usr/local/share/applications
sync
