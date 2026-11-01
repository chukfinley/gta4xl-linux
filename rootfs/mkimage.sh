#!/usr/bin/env bash
# rootfs.tar -> sparse ext4 image labelled gta4xl-root, rootless via a user namespace
# so that file ownership inside the image is correct.
set -euo pipefail

WORK="${WORK:-/mnt/data/android-linux}"
TAR="$WORK/out/rootfs.tar"
IMG="$WORK/out/rootfs.ext4"
SIZE="${SIZE:-10G}"

rm -f "$IMG"
unshare --map-auto --map-root-user --setuid 0 --setgid 0 bash -euo pipefail -c "
  dir=\$(mktemp -d -p '$WORK/out' rootfs.XXXXXX)
  tar -xpf '$TAR' -C \"\$dir\" --numeric-owner --exclude='./dev/*'
  mke2fs -q -t ext4 -L gta4xl-root -E root_owner=0:0 -d \"\$dir\" '$IMG' '$SIZE'
  rm -rf \"\$dir\"
"
e2fsck -fn "$IMG" | tail -2
ls -lsh "$IMG"
