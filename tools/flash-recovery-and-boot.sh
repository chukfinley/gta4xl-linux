#!/usr/bin/env bash
# Wait for download mode, flash the debug image to RECOVERY, let Android boot, then reboot into it.
set -uo pipefail
IMG="${1:-/mnt/data/android-linux/out/images/recovery-debug.img}"

if adb get-state >/dev/null 2>&1; then
  adb reboot download
fi
echo "waiting for download mode"
until heimdall detect >/dev/null 2>&1; do sleep 1; done
sleep 1
heimdall flash --RECOVERY "$IMG" 2>&1 | grep -E "successful|ERROR|Failed"

echo "waiting for Android"
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'
adb reboot recovery

echo "waiting for the Linux USB gadget"
for _ in $(seq 1 90); do
  if lsusb | grep -q "18d1:d001"; then
    lsusb | grep "18d1:d001"
    exit 0
  fi
  sleep 1
done
echo "gadget did not appear"
exit 1
