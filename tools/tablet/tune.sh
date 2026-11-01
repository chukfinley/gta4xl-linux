#!/bin/bash
# Userland tuning: compressed swap, GNOME power menu, fewer background services.
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y -qq tlp tlp-rdw >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends power-profiles-daemon systemd-zram-generator >/dev/null 2>&1
cat > /etc/systemd/zram-generator.conf <<'CONF'
[zram0]
zram-size = ram
compression-algorithm = lzo-rle
CONF
systemctl daemon-reload
systemctl enable --now power-profiles-daemon
systemctl start systemd-zram-setup@zram0.service
for s in rsyslog e2scrub_reap avahi-daemon avahi-daemon.socket cups cups-browsed ModemManager; do
  systemctl disable --now "$s" 2>/dev/null
done
# Deep sleep works, gta4xl-firstsetup of older images masked it
systemctl unmask sleep.target suspend.target
# File indexing and desktop helpers that a tablet does not need, about 150 MB
systemctl --global mask tracker-miner-fs-3.service tracker-extract-3.service tracker-miner-rss-3.service \
  org.gnome.SettingsDaemon.Sharing.service org.gnome.SettingsDaemon.Smartcard.service \
  org.gnome.SettingsDaemon.PrintNotifications.service org.gnome.SettingsDaemon.UsbProtection.service \
  gnome-remote-desktop.service evolution-addressbook-factory.service evolution-calendar-factory.service \
  evolution-source-registry.service 2>/dev/null
# Brave with touch gestures and the on-screen keyboard, fewer renderer processes
install -o user -g user -d /home/user/.config
cat > /home/user/.config/brave-flags.conf <<'CONF'
--ozone-platform=wayland
--enable-wayland-ime
--touch-events=enabled
--enable-features=TouchpadOverscrollHistoryNavigation
--password-store=basic
--ignore-gpu-blocklist
--disable-gpu-sandbox
--use-gl=angle
--use-angle=gles
--disable-features=Vulkan
--renderer-process-limit=3
--disk-cache-size=104857600
CONF
chown user:user /home/user/.config/brave-flags.conf
# Node priority selects the default sink. A saved choice would pin the speaker over headphones.
rm -f /home/user/.local/state/wireplumber/default-nodes
echo 'vm.swappiness=100' > /etc/sysctl.d/90-gta4xl.conf
sysctl -q -p /etc/sysctl.d/90-gta4xl.conf
sed -i 's#^Exec=/usr/bin/brave-browser-stable#Exec=/usr/local/bin/brave-browser#' /usr/share/applications/brave-browser.desktop
# Electron apps on the GPU through Panfork, on Wayland. The GPU sandbox has no rule for /dev/mali0.
# Do not use Xwayland with ANGLE here, that test reset the tablet.
GPU='--ignore-gpu-blocklist --disable-gpu-sandbox --use-gl=angle --use-angle=gles --disable-features=Vulkan'
D=/usr/share/applications/t3code.desktop
[ -f "$D" ] && sed -i -E "s/ --disable-gpu( |\$)/ /; / --use-angle=gles/! s#^(Exec=.*) %U#\1 $GPU %U#" "$D"
# Its autostart entry has no flags and would run on Xwayland
python3 - <<'PY'
import json
p = "/home/user/.config/Mattermost/config.json"
try:
    c = json.load(open(p))
except OSError:
    c = None
if c:
    c["autostart"] = False
    json.dump(c, open(p, "w"), indent=2)
PY
rm -f /home/user/.config/autostart/mattermost-desktop.desktop
D=/usr/share/applications/mattermost-desktop.desktop
[ -f "$D" ] && sed -i -E "/ --use-angle=gles/! s#^(Exec=.*) %U#\1 --ozone-platform=wayland --enable-wayland-ime $GPU %U#" "$D"
