# gta4xl (SM-P615) bring-up notes

Work data is on the second disk: `work` -> `/mnt/data/android-linux`
(kernel source, build output, images, backups, logs).

## Build and flash

```bash
kernel/build.sh                # kernel + dtbs, out/kernel
bootimg/build.sh               # out/images: boot.img, recovery-debug.img, dtbo.img
rootfs/build.sh                # out/rootfs.tar (TMPDIR must be on /mnt/data)
rootfs/mkimage.sh              # out/rootfs.ext4, label gta4xl-root
tools/flash-linux.sh           # waits for download mode, flashes BOOT RECOVERY VBMETA DTBO
tools/write-to-gadget.py IMG   # writes the rootfs to userdata (debug shell, polkit dialog)
```

`logs/pit.txt` exists only after `flash-linux.sh` ran. `flash.log` is from the old
recovery-only script `flash-recovery-and-boot.sh`.

`vbmeta-linux.img`: `tools/mk-vbmeta.py` takes the stock vbmeta and writes the hashes of our boot
and dtbo. The bootloader refuses VERIFICATION_DISABLED ("ODIN MODE (AVB Fail)"), the flag must
stay 0. The stock vbmeta is unsigned, so no key is needed. Partition change without download
mode: `tools/deploy-kernel.sh`.

heimdall failures: "Failed to send file part packet" ended two sessions with several partitions.
Each time a USB device was plugged into the PC during the upload. One partition per session
works, about 10 s. An aborted session leaves "An error has occurred while updating the device
software". That screen still accepts a flash, and a clean session clears it.

## Boot paths

- BOOT: initramfs binds the USB gadget, then `switch_root` into `LABEL=gta4xl-root`.
- RECOVERY: same kernel with `gta4xl.debug`. It stays in the debug shell and exports userdata
  as a USB drive.
- Files in the initramfs `/overlay` are copied onto the rootfs at each boot. Use this to change
  the rootfs without SSH.
- Access: ttyACM0 (`tools/tty-run.py`), telnet (debug shell), SSH `user@172.16.42.1` (Ubuntu,
  password `gta4xl`). The host side is the NetworkManager profile `gta4xl-usb`, MAC
  `02:47:54:41:34:02`, 172.16.42.2/24.

## Button sequences

Download mode:
1. Hold Volume Down + Power until the screen goes black.
2. At that moment add Volume Up and release Power. Do not hold all three for longer.
3. Hold Volume Up + Volume Down until the blue warning screen comes. Press Volume Up once.

If the tablet is off: hold Volume Up + Volume Down and plug in the USB cable.

The LineageOS recovery entry "Reboot to bootloader" is a fastbootd that accepts no data.

## Partition state

- 2026-10-15: userdata contains Ubuntu, so Android cannot boot any more. BOOT still contained
  LineageOS until `flash-linux.sh` ran. The boot where "Samsung logo, then black, no GDM" was
  seen did not use the Linux kernel.
- Restore: partition images are in `backup/partitions`, the Lineage recovery is in
  `tools/lineage`.

## Hardware facts from logs (kernel 4.14 gta4xl-linux)

- Touch: Himax HX83102E on spi6, IC ID 83,10,2E, FW 201, input `sec_touchscreen`.
  The firmware is built into the kernel (`tsp_himax/hx83102e_gta4xl.fw`).
- Pen: Wacom W9019 on i2c-8, input `sec_e-pen`, 22560x13536, firmware 0x258.
- Finger events reach the kernel and GNOME Wayland. Under Xorg taps only hover.
- `/etc/udev/rules.d/65-gta4xl-input.rules` removes the key tag from the touchscreen.
- Himax used `CONFIG_DRM` to select a Qualcomm path. It now tests `CONFIG_DRM_MSM` and uses the
  fb notifier for suspend and resume.
- The panel is a command-mode panel: it shows nothing until a frame is sent. fbcon deadlocks
  against the DECON unblank path, so VTs use the dummy console. There is no text on the panel.
- ext4 on `rootfs.ext4` has no `orphan_file`, so kernel 4.14 can mount it read-write.
- `CONFIG_PANIC_TIMEOUT=5`. Panic logs: `/sys/fs/pstore` or `/proc/last_kmsg`.

## Userland facts

- GNOME session: glib >= 2.74 uses `pidfd_open` and `waitid(P_PIDFD)`. The kernel had only the
  first, so child watches failed with EINVAL, children stayed zombies and gnome-session timed
  out after 90 s. `kernel/exit.c` now has P_PIDFD.
- `CONFIG_DEBUG_PREEMPT` printed a stack per IPv6 packet, load 18 on an idle desktop. It is off.
- `audit=0` on the kernel command line stops the kauditd log flood.
- Power key: logind ignores it, GNOME has power-button-action `nothing`, and
  `gta4xl-powerkey` sets mutter PowerSaveMode. The greeter has a private session bus, so the
  address comes from the gnome-shell environment.
- Suspend: "PM: suspend entry" is the last log line, the tablet then restarts. All sleep targets
  are masked.
- WLAN: the driver reads `/vendor/etc/wifi/slsi_reg_database.bin` and needs that exact path.
  NetworkManager must turn power save off, otherwise SSH sessions stop.
- Bluetooth: there is no rfkill start in old configs. `gta4xl-bluetooth.service` writes 1 to
  `/sys/module/scsc_bt/parameters/power_control`.
- Sensor hub: it stays off until `1` is written to `.../11980000.contexthub/poweron`. The
  firmware is built into the kernel. Then `/sys/class/sensors/ssp_sensor/enable` takes
  `<type>1` (accelerometer 1, light 3) and `/dev/iio:deviceN` gives packed samples: accelerometer
  x, y, z as s16 (4096 = 1 g) plus timestamp, 14 bytes. `gta4xl-sensors` offers this as
  net.hadess.SensorProxy and replaces the unit `iio-sensor-proxy.service`.

## Test tools

- `tools/tab CMD`: root shell on the tablet over WLAN. Hotspot HIBY on the PC, tablet 10.42.0.125.
- `tools/tab-shot`: DRM framebuffer to `_scratch/screen.png`, works under Wayland.
- `tools/tab-tap.py X Y`: inject a touch tap into `/dev/input/event1`.
- `tools/tty-run.py`, `tools/tty-push.py`: command and file over the USB serial console.
  ModemManager holds ttyACM0 for some seconds after each USB connect.
