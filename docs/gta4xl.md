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
- Access: ttyACM0 (`tools/tty-run.py`), telnet (debug shell), SSH over WLAN or Tailscale (Ubuntu,
  keys only). The host side is the NetworkManager profile `gta4xl-usb`, MAC
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

## Fixes after the first desktop boot

- USB network: ECM and NCM move no data. TX requests stay queued, `eth_start_xmit` returns
  TX_BUSY, and NET_TX runs 1.4 million times per second on one core. The gadget is serial only.
- DPMS: `decon_disable` followed by `decon_enable` leaves the DPP without a frame interrupt
  ("DPP[2] irq hasn't been occured") and the panel stays black. `decon_kms.c` now switches only
  the backlight. `gta4xl-powerkey` grabs the touchscreen while the panel is off, because mutter
  wakes on any input.
- Night Light: DECON has no gamma LUT here (no DQE driver in dpu20). The extension
  `gta4xl-tablet` applies a colour shader on `uiGroup`, driven by gsd-color.
- Pen: libinput ignores a tablet without a resolution. `61-gta4xl.hwdb` sets 100 units per mm.
- Battery: the driver reports mA, the power supply class needs uA. UPower had rate 0 and no
  time estimate. `sec_battery.c` multiplies by 1000.
- The bootloader ignores the boot.img command line. `audit=0` has no effect, so `CONFIG_AUDIT` is
  off. Check `gta4xl.debug` in recovery before you depend on it.
- Scale: fractional scale needs `scale-monitor-framebuffer`, and ApplyMonitorsConfig accepts only
  the exact values from GetCurrentState, for example 1.498.
- Panel format: the screenshot tool assumes XRGB8888, colours in `tab-shot` can be swapped when
  mutter picks another format.
- A heavy build on all cores makes WLAN drop packets. Check that before you suspect the driver.

## GPU (Mali-G72 r0p1, kbase r38p1) with Panfork

Build on the tablet: `tools/tablet/build-panfork.sh` (copy `gpu/panfork-jm.patch` to `/root` first),
install to `/opt/panfork`. Test: `LD_LIBRARY_PATH=/opt/panfork/lib LIBGL_DRIVERS_PATH=/opt/panfork/lib/dri
GBM_BACKENDS_PATH=/opt/panfork/lib/gbm __EGL_VENDOR_LIBRARY_DIRS=/opt/panfork/share/glvnd/egl_vendor.d
MESA_LOADER_DRIVER_OVERRIDE=exynos glmark2-es2-drm --off-screen -b build`. Panfork opens /dev/mali0
through kmsro when the driver name is exynos.

Fixed for JM on v6:
- `unreachable()` after the IDVS branch, heap bottom without +64, fence compare, job sequence start.
- Tiler Context state words only on v10. Panfork set `tiler.state.word1` and `word3` for all
  arches. On v6 the tiler job got DATA_INVALID_FAULT (0x58) or stopped. This was the draw hang.
  The kernel log showed TERMINATED and a page fault at a job header, these are follow-up errors.
- BO lifetime. kbase holds no BO references. The CSF free callback does nothing on JM, because
  `event_slot_usage` is 0 there. So `pan_bo.c` now waits for `use_count` before it unmaps a BO, and
  the BO cache waits as on the DRM driver. Without this the heavy scenes gave 0x58, 0x59 and 0x42.
- Atom numbers. `pre_dep.atom_id == 0` means no dependency, so the driver must not use atom 0.
  Without this a fragment job after atom 0 started before its tiler job and read an unmapped heap.
  `kbase_throttle_atoms()` keeps 56 atom numbers free, `use_count` is 8 bits.
- Dependencies through the display. `CONFIG_MALI_DMA_FENCE` is off, so a dma-buf has no fence and
  a page flip cannot wait for the GPU. `panfrost_flush()` now waits at the end of each frame.
- EGL surfaceless uses the primary node when the device has no render node. Mutter headless needs
  this, the DRM shim has no render node.
The tiler heap stays growable (`BASE_MEM_GROW_ON_GPF`, 128 MB of VA). Grow on fault works on this
kernel. An earlier note in this file said the opposite. The draw hang was the cause of that note.

State: renderer is "Mali-G72 (Panfrost)". glmark2-es2-drm --off-screen, 1200x2000, 0 GPU faults:
build 544 FPS, shading 488, texture 448, desktop 86, refract 48, terrain 22. All scenes run.
`gpu/gbmtest.c` renders to a GBM scanout surface and reads the dma-buf with the CPU: this path works.

glmark2 `--validate` forces 800x600 on X11. On DRM the surface stays 1200x2000, so the shading and
texture references fail there. That is not a render fault. A better check: a headless gnome-shell
overview on Panfork against llvmpipe, 99.97 % of the pixels differ by at most 8, the rest is the
clock and the panel icons.

## GNOME Shell on Panfork

`tools/tablet/panfork-session.sh enable` (as root) writes a drop-in for
`org.gnome.Shell@wayland.service` with the five Panfork variables. It also adds the extension
`panfork-env@gta4xl`. This extension removes the variables from the shell after start, so apps
stay on system Mesa. Mesa 23 of Panfork does not fit the system libraries, so do not use
`/etc/environment` or `ld.so.conf`. The setting is active after the next login. `disable` undoes
it, `status` shows the state. Keep SSH open for the first login: if the shell fails, run `disable`
and then `systemctl restart gdm`.

Test without a change to the session (a separate instance on a private D-Bus):
`env -i HOME=... XDG_RUNTIME_DIR=... <Panfork variables> dbus-run-session -- gnome-shell --headless
--virtual-monitor 1200x2000 --wayland --no-x11 --wayland-display wl-gpu`, as user `user`.
This instance runs on /dev/mali0 with 0 GPU faults. A system Mesa Wayland client on it uses llvmpipe
and works (57 FPS). A Panfork Wayland client fails with `wl_drm: authenticate failed` on headless,
because headless mutter is not DRM master. Real KMS page flips are not tested yet.

Debug notes:
- Exception status in a job header: bits 7:0 type, 9:8 access, 31:16 source. 0x10258 is 0x58
  DATA_INVALID_FAULT. Read it with `PAN_MESA_DEBUG=trace PANDECODE_DUMP_FILE=/root/tr/pd`.
- `BIFROST_MESA_DEBUG=noidvs` splits a draw into a vertex job and a tiler job. Then the trace shows
  which of the two failed.
- Do not use `PAN_MESA_DEBUG=nocache` on kbase. A freed BO leaves the GPU MMU at once, also while a
  job runs. kbase holds no BO references, so this gives page faults that look like GPU errors.
- Event 0x4 for each atom means that an MMU fault killed the context.

## Browser and GPU

GNOME Shell and Wayland clients with EGL run on Mali through `tools/tablet/panfork-system.sh`.
Chromium (Brave, Electron): its Wayland GPU process needs a GBM device on a DRM render node.
decon-kms has no render node, so shared images fail and the GPU process restarts in a loop
("Cannot create bo with format=RGBA_8888"). Brave under Xwayland with ANGLE probably reset the
tablet (no panic text). Brave and T3 Code use `--disable-gpu` until that works.
