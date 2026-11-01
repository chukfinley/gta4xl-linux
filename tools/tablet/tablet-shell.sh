#!/usr/bin/env bash
# Install Tablet Shell on the tablet. Run on the computer: tools/tablet/tablet-shell.sh DIR, with
# DIR as the tablet-shell checkout. Also needed after a fresh install.
set -euo pipefail
SRC=${1:?usage: tablet-shell.sh TABLET_SHELL_DIR}
HERE=$(cd "$(dirname "$0")/.." && pwd)
UUID=tablet-shell@gnome-tablet
glib-compile-schemas "$SRC/extension/schemas"
tar czf - -C "$SRC" extension data apps | "$HERE/tab" "
set -e
rm -rf /run/ts-new; mkdir -p /run/ts-new; tar xzf - -C /run/ts-new
EXT=/usr/share/gnome-shell/extensions/$UUID
rm -rf \$EXT; cp -r /run/ts-new/extension \$EXT
cp /run/ts-new/data/wallpaper/tablet-shell.jpg /usr/share/backgrounds/
mkdir -p /usr/local/share/tablet-shell/apps/data /etc/environment.d
cp /run/ts-new/apps/recommended-apps.js /usr/local/share/tablet-shell/apps/
cp /run/ts-new/data/apps.json /usr/local/share/tablet-shell/apps/data/
sed 's|APPDIR|/usr/local/share/tablet-shell/apps|; s|gjs -m|TABLET_APPS_DATA=/usr/local/share/tablet-shell/apps/data/apps.json gjs -m|' \
  /run/ts-new/data/tablet-recommended-apps.desktop > /usr/local/share/applications/tablet-recommended-apps.desktop
cp /run/ts-new/data/environment.d/60-tablet-shell.conf /etc/environment.d/
for v in gtk-3.0 gtk-4.0; do
  for h in /etc/skel /home/user; do
    mkdir -p \$h/.config/\$v
    cp /run/ts-new/data/gtk/tablet-shell.css \$h/.config/\$v/
    grep -qs tablet-shell.css \$h/.config/\$v/gtk.css || sed -i '1i @import url(\"tablet-shell.css\");' \$h/.config/\$v/gtk.css 2>/dev/null ||
      echo '@import url(\"tablet-shell.css\");' > \$h/.config/\$v/gtk.css
  done
done
chown -R user:user /home/user/.config/gtk-3.0 /home/user/.config/gtk-4.0
sync
"
echo installed
