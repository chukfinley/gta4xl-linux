#!/usr/bin/env bash
# Flash Linux into BOOT (normal power-on), the debug initramfs into RECOVERY, the matching DTBO,
# and a vbmeta with verification disabled. Enter download mode first: `reboot-to download` on the tablet, or buttons.
set -euo pipefail
IMAGES="${IMAGES:-/mnt/data/android-linux/out/images}"
PIT=/mnt/data/android-linux/logs/pit.txt

if adb get-state >/dev/null 2>&1; then
  adb reboot download
fi
echo "waiting for download mode"
until heimdall detect >/dev/null 2>&1; do sleep 1; done
sleep 1

heimdall print-pit --no-reboot > "$PIT" 2>&1
for p in BOOT RECOVERY VBMETA DTBO; do
  grep -q "Partition Name: $p\$" "$PIT" || { echo "partition $p missing in PIT, see $PIT"; exit 1; }
done

# VBMETA first: a rejected image then fails before the long uploads
heimdall flash --resume \
  --VBMETA "$IMAGES/vbmeta-linux.img" \
  --DTBO "$IMAGES/dtbo.img" \
  --BOOT "$IMAGES/boot.img" \
  --RECOVERY "$IMAGES/recovery-debug.img" 2>&1 | grep -E "successful|ERROR|Failed|Uploading"
echo "flashed; the tablet reboots into Linux"
