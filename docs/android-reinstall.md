# Back to LineageOS from Linux

This replaces Linux with LineageOS 23.2 without Google apps, with Magisk root. It deletes the Linux rootfs on userdata. The SD card is not touched.

Files on the PC: `/mnt/data/android-linux/tools/lineage/new/` (LineageOS zip, recovery, vbmeta, dtbo, boot, `SHA256`, `Magisk-v31.1.apk`). Source: https://download.lineageos.org/devices/gta4xl/builds. User data from Linux: `/mnt/data/android-linux/backup/from-linux/`.

## Steps

1. Connect the tablet to the PC with a USB cable.
2. From the running Linux, write the LineageOS images and start the recovery. Write vbmeta only directly before the reboot: with the LineageOS vbmeta the Linux boot image fails AVB, and the bootloader stops in "ODIN MODE (AVB Fail)".

   ```sh
   D=/mnt/data/android-linux/tools/lineage/new
   scp $D/recovery.img $D/vbmeta.img $D/dtbo.img gta4xl:/run/
   tools/tab 'dd if=/run/recovery.img of=/dev/disk/by-partlabel/recovery bs=1M conv=fsync &&
     dd if=/run/dtbo.img of=/dev/disk/by-partlabel/dtbo bs=1M conv=fsync &&
     dd if=/run/vbmeta.img of=/dev/disk/by-partlabel/vbmeta bs=64K conv=fsync && sync && reboot recovery'
   ```

3. In the recovery: "Factory reset", then "Format data / factory reset". Then "Apply update", "Apply from ADB", and on the PC: `adb sideload lineage-23.2-*.zip`. When the recovery asks for more packages (Google apps), answer no. Then "Reboot system now".
4. After the first start: enable Developer options and USB debugging, then `adb install Magisk-v31.1.apk`. Push `boot.img` to `/sdcard/Download`, patch it in the Magisk app, and pull the patched file. Then `adb reboot recovery`, enable ADB in the recovery, and write the patched file to the boot partition with `dd` in `adb shell`.
5. Set up SSH (Magisk module or Termux `sshd`) and Tailscale.

If the tablet stops in download mode: flash recovery and vbmeta with `heimdall flash --RECOVERY recovery.img --VBMETA vbmeta.img`.

To go back to Linux: see `README.md` and `tools/flash-linux.sh`.
