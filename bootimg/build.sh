#!/usr/bin/env bash
# Build Samsung header-v2 images for gta4xl:
#   out/boot.img          normal boot (initramfs -> SD rootfs)
#   out/recovery-debug.img recovery partition, always stays in the USB debug shell
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-/mnt/data/android-linux}"
KOUT="$WORK/out/kernel"
OUT="$WORK/out/images"
TOOLS="$WORK/tools"
mkdir -p "$OUT"

# initramfs
RD="$OUT/initramfs"
rm -rf "$RD"
mkdir -p "$RD/bin"
cp "$TOOLS/bb/usr/bin/busybox" "$RD/bin/busybox"
install -m 0755 "$HERE/initramfs/init" "$RD/init"
# Rootfs files that the initramfs copies at each boot, see initramfs/init
OV="$HERE/rootfs/overlay"
install -D -m 0755 "$OV/usr/local/sbin/gta4xl-usb-gadget" "$RD/overlay/usr/local/sbin/gta4xl-usb-gadget"
install -D -m 0644 "$OV/etc/fstab" "$RD/overlay/etc/fstab"
clang --target=aarch64-linux-gnu -O2 -static -nostdlib -ffreestanding -fno-stack-protector \
  -fuse-ld=lld -o "$RD/bin/reboot-to" "$HERE/initramfs/reboot-to.c"
(cd "$RD" && find . | cpio -o -H newc --owner=0:0 --quiet | gzip -9) > "$OUT/initramfs.cpio.gz"

# DTB / DTBO tables in the format the Samsung bootloader expects
DTS="$KOUT/arch/arm64/boot/dts"
cat > "$OUT/dtb.cfg" <<EOF
$DTS/exynos/exynos9610.dtb
    custom0=0x00000000
    custom1=0xff000000
EOF
{
  for rev in 01:0x02000000:0x02000000 03:0x03000000:0x03000000 04:0x04000000:0x06000000 \
             05:0x07000000:0x07000000 08:0x08000000:0x08000000 09:0x09000000:0xff000000; do
    IFS=: read -r r c0 c1 <<<"$rev"
    printf '%s\n    custom0=%s\n    custom1=%s\n\n' "$DTS/samsung/exynos9611-gta4xl_eur_open_$r.dtbo" "$c0" "$c1"
  done
} > "$OUT/dtbo.cfg"
python3 "$TOOLS/mkdtboimg.py" cfg_create "$OUT/dtb.img" "$OUT/dtb.cfg"
python3 "$TOOLS/mkdtboimg.py" cfg_create "$OUT/dtbo.img" "$OUT/dtbo.cfg"

CMDLINE="console=tty0 loglevel=4 selinux=0 audit=0"
COMMON=(--kernel "$KOUT/arch/arm64/boot/Image" --ramdisk "$OUT/initramfs.cpio.gz" --dtb "$OUT/dtb.img"
  --base 0x10000000 --pagesize 2048 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000
  --tags_offset 0x00000100 --dtb_offset 0x00000000 --header_version 2
  --os_version 16.0.0 --os_patch_level 2026-03)

python3 "$TOOLS/mkbootimg/mkbootimg.py" "${COMMON[@]}" --cmdline "$CMDLINE" -o "$OUT/boot.img"
python3 "$TOOLS/mkbootimg/mkbootimg.py" "${COMMON[@]}" --cmdline "$CMDLINE gta4xl.debug" --recovery_dtbo "$OUT/dtbo.img" -o "$OUT/recovery-debug.img"

ls -la "$OUT"/*.img

# Lineage chains boot/recovery in vbmeta with the public AVB test key; sign the same way
python3 "$TOOLS/avbtool.py" add_hash_footer --image "$OUT/recovery-debug.img" --partition_name recovery \
  --partition_size 71106560 --algorithm SHA256_RSA4096 --key "$TOOLS/testkey_rsa4096.pem" --rollback_index 1
python3 "$TOOLS/avbtool.py" add_hash_footer --image "$OUT/boot.img" --partition_name boot \
  --partition_size "${BOOT_PARTITION_SIZE:-61865984}"
