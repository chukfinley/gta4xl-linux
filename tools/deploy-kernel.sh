#!/usr/bin/env bash
# Install a new boot.img over SSH from the running Ubuntu, no buttons and no download mode.
# vbmeta must carry the hash of the new boot image, so both partitions are written.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES="${IMAGES:-/mnt/data/android-linux/out/images}"
BACKUP="${BACKUP:-/mnt/data/android-linux/backup/partitions}"
IP="${GTA4XL_IP:-10.42.0.125}"
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

python3 -I "$HERE/tools/mk-vbmeta.py" "$BACKUP/vbmeta.img" "$IMAGES/vbmeta-linux.img" \
  boot="$IMAGES/boot.img" dtbo="$IMAGES/dtbo.img"
scp "${SSHOPTS[@]}" "$IMAGES/boot.img" "$IMAGES/vbmeta-linux.img" "root@$IP:/run/"
"$HERE/tools/tab" 'set -e
  sha256sum /run/boot.img /run/vbmeta-linux.img
  dd if=/run/boot.img of=/dev/disk/by-partlabel/boot bs=1M conv=fsync status=none
  dd if=/run/vbmeta-linux.img of=/dev/disk/by-partlabel/vbmeta bs=64K conv=fsync status=none
  sync; rm /run/boot.img /run/vbmeta-linux.img
  (sleep 1; systemctl reboot) >/dev/null 2>&1 &'
sha256sum "$IMAGES/boot.img" "$IMAGES/vbmeta-linux.img"
echo "rebooting"
