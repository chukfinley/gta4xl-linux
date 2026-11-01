#!/usr/bin/env bash
# Copy the device firmware from $WORK/backup/vendor.tar into the rootfs tree $WORK/out/blobs.
# The files belong to Samsung and stay out of this repository.
set -euo pipefail
WORK="${WORK:-/mnt/data/android-linux}"
OUT="$WORK/out/blobs"
TMP="$(mktemp -d -p "$WORK")"
trap 'rm -rf "$TMP"' EXIT
tar -xf "$WORK/backup/vendor.tar" -C "$TMP" vendor/firmware vendor/etc/wifi
mkdir -p "$OUT/usr/lib/firmware/scsc" "$OUT/vendor/etc/wifi"
cp "$TMP"/vendor/firmware/* "$OUT/usr/lib/firmware/"
cp "$TMP"/vendor/etc/wifi/* "$OUT/usr/lib/firmware/scsc/"
# The WLAN driver reads the regulatory database from the Android path
cp "$TMP"/vendor/etc/wifi/slsi_reg_database.bin "$OUT/vendor/etc/wifi/"
ls "$OUT/usr/lib/firmware" | wc -l
