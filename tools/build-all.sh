#!/usr/bin/env bash
# Build everything from a device backup: kernel, boot images, Ubuntu rootfs image.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export WORK="${WORK:-/mnt/data/android-linux}"
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"
"$HERE/kernel/fetch.sh"
"$HERE/kernel/build.sh"
"$HERE/tools/extract-blobs.sh"
"$HERE/rootfs/build.sh"
"$HERE/rootfs/mkimage.sh"
"$HERE/bootimg/build.sh"
python3 -I "$HERE/tools/mk-vbmeta.py" "$WORK/backup/partitions/vbmeta.img" "$WORK/out/images/vbmeta-linux.img" \
  boot="$WORK/out/images/boot.img" dtbo="$WORK/out/images/dtbo.img"
