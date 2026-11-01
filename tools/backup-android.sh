#!/usr/bin/env bash
# Back up the partitions and /vendor from a tablet that runs LineageOS, before anything is flashed.
# Needs "Rooted debugging" in the developer options. Output: $WORK/backup
set -euo pipefail
WORK="${WORK:-/mnt/data/android-linux}"
OUT="$WORK/backup"
mkdir -p "$OUT/partitions"
adb root
adb wait-for-device
for p in boot recovery dtbo vbmeta vbmeta_samsung efs sec_efs param up_param keydata keyrefuge \
         persistent metadata misc uh blcmd; do
  adb exec-out "dd if=/dev/block/by-name/$p 2>/dev/null" > "$OUT/partitions/$p.img" || true
done
adb exec-out "tar -cf - -C / vendor" > "$OUT/vendor.tar"
(cd "$OUT/partitions" && sha256sum ./*.img > SHA256SUMS)
ls -la "$OUT" "$OUT/partitions"
