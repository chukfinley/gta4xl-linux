#!/usr/bin/env bash
# Install a new boot.img over SSH from the running Ubuntu, no buttons and no download mode.
# vbmeta must carry the hash of the new boot image, so both partitions are written.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES="${IMAGES:-/mnt/data/android-linux/out/images}"
BACKUP="${BACKUP:-/mnt/data/android-linux/backup/partitions}"
IP="${GTA4XL_IP:-gta4xl}"
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

python3 -I "$HERE/tools/mk-vbmeta.py" "$BACKUP/vbmeta.img" "$IMAGES/vbmeta-linux.img" \
  boot="$IMAGES/boot.img" dtbo="$IMAGES/dtbo.img"
SUMS="$(cd "$IMAGES" && sha256sum boot.img vbmeta-linux.img)"
# The hotspot drops SSH for up to a minute. Retry the copy, and let a unit on the tablet do the
# writes, so that a lost session cannot stop dd in the middle of the boot partition.
for i in 1 2 3 4 5 6 7 8; do
  scp "${SSHOPTS[@]}" -o ConnectTimeout=8 "$IMAGES/boot.img" "$IMAGES/vbmeta-linux.img" "root@$IP:/run/" && break
  [ "$i" = 8 ] && exit 1
  sleep 10
done
for i in 1 2 3 4 5 6 7 8; do
  "$HERE/tools/tab" "cd /run && echo '$SUMS' | sha256sum -c - && systemd-run --unit=gta4xl-deploy --collect sh -c '
    dd if=/run/boot.img of=/dev/disk/by-partlabel/boot bs=1M conv=fsync status=none &&
    dd if=/run/vbmeta-linux.img of=/dev/disk/by-partlabel/vbmeta bs=64K conv=fsync status=none &&
    sync && rm /run/boot.img /run/vbmeta-linux.img && sleep 1 && systemctl reboot
    sleep 25; echo b > /proc/sysrq-trigger'" && break
  [ "$i" = 8 ] && exit 1
  sleep 10
done
sha256sum "$IMAGES/boot.img" "$IMAGES/vbmeta-linux.img"
echo "rebooting"
