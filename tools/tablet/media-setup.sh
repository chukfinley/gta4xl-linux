#!/bin/bash
# Run as root on the tablet. Gives PipeWire realtime priority and adds the uosc mpv controls.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
VER=5.13.0
SUM=4be9da3289285300fa374496c3f1bfd7bb20ac08e890d25bd5a06b28eebe4882

apt-get install -y -qq --no-install-recommends rtkit unzip >/dev/null

TMP="$(mktemp -d /var/tmp/uosc.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -A 'media-setup/1.0' -o "$TMP/uosc.zip" \
  "https://github.com/tomasklaen/uosc/releases/download/$VER/uosc.zip"
echo "$SUM  $TMP/uosc.zip" | sha256sum -c -
rm -rf /etc/mpv/scripts/uosc
mkdir -p /etc/mpv
unzip -q -o "$TMP/uosc.zip" -d /etc/mpv
dconf update
