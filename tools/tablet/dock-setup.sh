#!/usr/bin/env bash
# Dash to Dock with our patch, the dock at the bottom of the screen. Run as root on the tablet.
# Settings: /etc/dconf/db/local.d/52-gta4xl-dock. Window actions: extension gta4xl-tablet, dock.js.
# The new extension needs a new login.
set -euo pipefail
UUID=dash-to-dock@micxgx.gmail.com
TAG=76105 # version 110, GNOME 45 to 51
SHA=b05003e79835a35451e94931539ba1977f2a7a93b652a4fc6b7be60a77c18ae1
DIR=/usr/share/gnome-shell/extensions/$UUID
PATCH=$(dirname "$(readlink -f "$0")")/dash-to-dock.patch
DESKTOP_USER=user
WORK=$(mktemp -d /run/dock.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

command -v patch >/dev/null || apt-get install -y patch
# Ubuntu Dock is the same code and would be a second dock
if dpkg -s gnome-shell-extension-ubuntu-dock >/dev/null 2>&1; then
  apt-get remove -y gnome-shell-extension-ubuntu-dock
fi

curl -fsSL -A 'toolname/1.0' -o "$WORK/dock.zip" \
  "https://extensions.gnome.org/download-extension/$UUID.shell-extension.zip?version_tag=$TAG"
echo "$SHA  $WORK/dock.zip" | sha256sum -c -
mkdir "$WORK/new"
unzip -q "$WORK/dock.zip" -d "$WORK/new"
patch -d "$WORK/new" -p1 < "$PATCH"
rm -rf "$DIR"
mv "$WORK/new" "$DIR"
chmod -R a+rX "$DIR" # the archive has private modes
# gsettings reads the system copy, the extension its own
cp "$DIR"/schemas/*.gschema.xml /usr/share/glib-2.0/schemas/
glib-compile-schemas /usr/share/glib-2.0/schemas
glib-compile-schemas "$DIR/schemas"
dconf update

# The dconf defaults reach only keys that the user has not set. So the first run sets the two keys
# that this user already has. A later run keeps the apps that the user pinned.
home=$(getent passwd "$DESKTOP_USER" | cut -d: -f6)
mark=$home/.config/gta4xl-dock-setup
if [ -S "/run/user/$(id -u "$DESKTOP_USER")/bus" ] && [ ! -e "$mark" ]; then
  as_user() {
    runuser -u "$DESKTOP_USER" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$DESKTOP_USER")" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$DESKTOP_USER")/bus" "$@"
  }
  on=$(as_user gsettings get org.gnome.shell enabled-extensions)
  case "$on" in
  *"$UUID"*) ;;
  *) as_user gsettings set org.gnome.shell enabled-extensions "${on%]}, '$UUID']" ;;
  esac
  as_user gsettings reset org.gnome.shell favorite-apps
  as_user touch "$mark"
fi
sync
