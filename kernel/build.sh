#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-/mnt/data/android-linux/kernel}"
OUT="${OUT:-/mnt/data/android-linux/out/kernel}"

export ARCH=arm64
MAKEFLAGS=(-C "$SRC" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=clang
  CLANG_TRIPLE=aarch64-linux-gnu- -j"$(nproc)")

mkdir -p "$OUT"
make "${MAKEFLAGS[@]}" exynos9611-gta4xl_defconfig
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$HERE/linux-desktop.config"
make "${MAKEFLAGS[@]}" olddefconfig
make "${MAKEFLAGS[@]}" Image dtbs "$@"

# Report fragment options that Kconfig dropped
while IFS= read -r line; do
  case "$line" in
    CONFIG_*=*) grep -qxF "$line" "$OUT/.config" || echo "NOT APPLIED: $line" ;;
  esac
done < "$HERE/linux-desktop.config"
