#!/usr/bin/env bash
# Get the LineageOS kernel at the tested commit and apply our patch.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-/mnt/data/android-linux/kernel}"
URL=https://github.com/LineageOS/android_kernel_samsung_gta4xl.git
COMMIT=8d1f7a68b0d0eef5aa6a12479429333e27482673

if [ ! -d "$SRC/.git" ]; then
  git clone "$URL" "$SRC"
fi
git -C "$SRC" checkout -q "$COMMIT"
git -C "$SRC" apply "$HERE"/patches/*.patch
