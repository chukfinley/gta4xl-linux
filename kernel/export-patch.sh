#!/usr/bin/env bash
# Write all changes in the kernel tree, new files included, to kernel/patches.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-/mnt/data/android-linux/kernel}"
mkdir -p "$HERE/patches"
git -C "$SRC" add -N .
git -C "$SRC" diff --binary > "$HERE/patches/0001-gta4xl-linux.patch"
git -C "$SRC" reset -q
wc -l "$HERE/patches/0001-gta4xl-linux.patch"
