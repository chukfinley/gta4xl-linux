#!/usr/bin/env bash
# System parts of the slim session. Run as root on the tablet, also after a fresh install. The
# masks for the user session and the hidden autostarts are in the overlay.
set -euo pipefail
systemctl disable --now power-profiles-daemon.service apt-daily.timer apt-daily-upgrade.timer \
  man-db.timer motd-news.timer e2scrub_all.timer dpkg-db-backup.timer 2>/dev/null || true
systemctl mask power-profiles-daemon.service
apt-get install -y -qq --no-install-recommends adwaita-qt adwaita-qt6 || true
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
update-desktop-database /usr/local/share/applications 2>/dev/null || true
dconf update
systemctl daemon-reload
# One window control: Brave leaves its own title buttons (the shell draws the controls)
if ! pgrep -x brave >/dev/null; then
  python3 - <<'PY' || true
import json
f = '/home/user/.config/BraveSoftware/Brave-Browser/Default/Preferences'
d = json.load(open(f))
d.setdefault('browser', {})['custom_chrome_frame'] = False
json.dump(d, open(f, 'w'))
PY
fi
sync
