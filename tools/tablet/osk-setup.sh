#!/usr/bin/env bash
# GJS OSK, the on-screen keyboard with Esc, Ctrl, Tab and arrows. Run as root on the tablet.
# The extension gta4xl-tablet turns it on and off, it runs only with no physical keyboard.
# Settings: /etc/dconf/db/local.d/51-gta4xl-osk. The new extension needs a new login.
set -euo pipefail
UUID=gjsosk@vishram1123.com
TAG=74269 # version 53, GNOME 45 to 50
SHA=38578bfb54880c8fec13e24783406d4c77ad047b5bc205b7a5814dc631231b6d
DIR=/usr/share/gnome-shell/extensions/$UUID
WORK=$(mktemp -d /run/osk.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

curl -fsSL -A 'toolname/1.0' -o "$WORK/osk.zip" \
  "https://extensions.gnome.org/download-extension/$UUID.shell-extension.zip?version_tag=$TAG"
echo "$SHA  $WORK/osk.zip" | sha256sum -c -
mkdir -p "$DIR"
unzip -q -o "$WORK/osk.zip" -d "$DIR"
chmod -R a+rX "$DIR" # the archive has private modes
# The zip has no compiled schema. gsettings reads the system copy, the extension its own.
cp "$DIR"/schemas/*.gschema.xml /usr/share/glib-2.0/schemas/
glib-compile-schemas /usr/share/glib-2.0/schemas
glib-compile-schemas "$DIR/schemas" # the shell loads the schema from the extension directory
dconf update
sync
