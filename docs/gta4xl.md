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
- Suspend: see "System sleep".
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
Brave and Electron (T3 Code, Mattermost) run on the GPU with these flags, see `tools/tablet/tune.sh`:
`--ozone-platform=wayland --ignore-gpu-blocklist --disable-gpu-sandbox --use-gl=angle --use-angle=gles
--disable-features=Vulkan`. The GPU sandbox has no rule for /dev/mali0. `--disable-gpu` is gone.

Chromium needed four changes:
- `DRIVER_RENDER` in `decon_kms.c`. `/dev/dri/renderD128` now exists. The dumb ioctls of this kernel
  already have `DRM_RENDER_ALLOW`. Mutter works with the new node.
- The GPU process opens `card0`, not the render node. `DRM_IOCTL_PRIME_HANDLE_TO_FD` needs
  `DRM_AUTH` on a primary node, so GBM failed with EACCES ("failed to export dumb buffer"). The
  flag is gone from the two PRIME ioctls in `drm_ioctl.c`. Upstream removed it too.
- `PIPE_CAP_NATIVE_FENCE_FD` is 0 on kbase. kbase cannot export a sync file,
  eglDupNativeFenceFDANDROID failed and the GPU process stopped with exit code 5.
- Panfork found the same dma-buf with kcmp, but this kernel has no `CONFIG_CHECKPOINT_RESTORE`.
  Each import made a new BO and printed "error in os_same_file_description". It now compares
  the inode, each dma-buf has its own inode.

Results on 2026-11-01, Brave 1.98 (Chromium 156), 2000x947, ANGLE on "Mali-G72 (Panfrost)", OpenGL ES
3.1, `gpu_compositing` enabled: example.com and Wikipedia at 60 FPS, correct colours. WebGL 2 full
screen shader 1200x800 at 62 FPS. 20 s test clips, software decode: VP9 720p30 0 dropped frames,
VP9 1080p30 1 dropped, H.264 1080p30 0 dropped. 5 min soak with video, canvas, 30 CSS animations and
DOM churn: 0 GPU faults, GPU process alive, 75 C. T3 Code (Electron 44) and Mattermost start and load
exynos_dri. The GPU process exit 8704 and the restart loop are gone.

Test notes:
- `vkCreateInstance() failed: -9` and `vaInitialize failed` in the log are harmless.
- Do not use Xwayland with ANGLE, that test probably reset the tablet. Mattermost has `autostart`
  on by default and its autostart entry has no flags. `tune.sh` turns it off.
- `systemctl stop` on a test unit can leave the Brave main process alive, it then starts a new GPU
  process with `--gpu-recent-crash-count=1`. That is no crash.
- Do not use `pkill -f` with a text that is also in your own SSH command line.
- Tests over CDP: `ssh -L 9222:127.0.0.1:9222`, `--remote-debugging-port=9222`, `SystemInfo.getInfo`,
  `Page.captureScreenshot`, `getVideoPlaybackQuality()`.

## System sleep

Deep sleep works, PSCI and resume on this kernel are fine. Three problems hid that.

- Multistage watchdog. `kernel/power/process.c` (Samsung code) stops `10060000.watchdog_cl1` before
  each freeze and starts it after. Android runs this watchdog, Linux does not. So the freezer started
  a watchdog with count 0 that nobody serves. About 16 s later CPU0 stayed in c2, all interrupts go
  to CPU0, then came I2C, UFS and Mali timeouts and a hard lockup panic ("IDLE STUCK"). Even
  `pm_test=freezer` reset the tablet. `s3c2410_wdt.c` now starts it only if it was on before.
- Touch. `himax_tp` was a wake interrupt and ran while the SPI controller slept: "failed to prepare
  transfer hardware: -13" and the abort of sleep with `pm_wakeup_irq` 270. The driver now has system
  sleep ops that stop the interrupt, and the wake flag is gone.
- WLAN. `INT_MBOX_WLBT2AP` ends sleep at once for each scan result and broadcast frame.
  `SETSUSPENDMODE 1` does not stop the MLME frames. The hook
  `/usr/lib/systemd/system-sleep/gta4xl` turns the radio off before sleep and on after sleep.
  WLAN is connected again 25 s after resume or earlier. There is no wake on WLAN.

`gta4xl-powerkey` starts `systemctl suspend` when the panel was off for 120 s, on battery only, with
no `[active]` entry in `wpctl status` and no block inhibitor for sleep. A tablet on the charger stays
awake, so SSH and background jobs continue there. The hook sends SIGUSR1 after resume and the daemon
switches the panel on. Key presses in the next 3 s are ignored, because the press that woke the
tablet arrives as an input event. `sleep.target` and `suspend.target` are unmasked, the hibernate
targets stay masked.

Mutter wakes on any input, also on the release of a key. So the daemon acts on the release, and it
reads the panel state at the press from `/sys/class/drm/card0-DSI-1/dpms`. A D-Bus call at the press
already sees the state after the wake. The key test without hands: write `EV_KEY` 116 to the
`gpio_keys` event node, evdev delivers it to the readers.

Test without hands: `batt_slate_mode` 1 stops charging, the status is then Discharging and the
daemon path runs.

Results on 2026-11-01: 5 of 5 cycles of `systemctl suspend` with 30 s RTC wake, while Brave played
1080p video. After each cycle: `suspend_stats` fail 0, WLAN connected, panel at 120 interrupts/s,
0 GPU faults, all CPUs online, Brave GPU process alive. The daemon path worked once with the
panel off on battery, the panel came back on after resume. Power key wake is not tested, that
needs hands.

Power, measured with `batt_slate_mode` 1 at about 4.28 V: awake with the panel off and WLAN on about
130 mA (0.55 W), the voltage fell 15 mV in 10 min. In 10 min of sleep the voltage did not fall. There
is no number in mA for sleep: at full charge the fuel gauge reports 0x6400 all the time, and it
cannot read while the system sleeps. For a number, start below 95 % and compare the SOC.

Open: each sleep logs "MIF blocked. prev_conn_req: 0x1" and `mif_count` stays 0, so the memory bus
does not go down. CP_STAT is 1, and Linux never boots the modem. This can cost battery in sleep.

Wake sources: Power (`gpio-key,wakeup` in the DT, `gpio_keys` simulates the press), PMIC RTC. Check
after a sleep: `dmesg | grep "Resume caused"`, `/sys/power/suspend_stats`.

Debug:
- `/proc/last_kmsg` holds the kernel log of the last boot, also after a panic. It contains NUL
  bytes: `tr -d '\000' < /proc/last_kmsg | grep -a '^<[0-9]>\['`.
- Test levels: `echo LEVEL > /sys/power/pm_test; echo mem > /sys/power/state`. Wait 40 s after each
  test, the lockup came 16 s after the test ended.
- "Abort: Disabling non-boot cpus failed" at level `processors` is only the label of the test.
- `cat /sys/power/wakeup_count` blocks while a wakeup source is active.
- There is no debugfs on this kernel, so no `wakeup_sources` file.
- Test without hands: `echo +30 > /sys/class/rtc/rtc0/wakealarm; systemctl suspend`.

## Audio

Card 0 is the ABOX DSP with the RT5665 (headphone, UAIF0) and two TAS2562 amps (speaker, UAIF2).

- EBUSY from `aplay` did not come from a process. `fuser` shows nothing. The DSP was off:
  "Invalid calliope state: 0". The driver requests `calliope_sram.bin` in the probe, when only the
  initramfs exists. Android serves the file through ueventd. `abox.c` now tries again every 3 s.
  Check: dmesg "Calliope is ready to sing", about 5.6 s after boot.
- After the DSP boot, the driver adds card `abox_dump`. Its `dma_area` is device memory.
  `snd_pcm_hw_params` cleared it with `memset`, and DC ZVA on device memory gives an alignment
  fault. WirePlumber opened the card 1.5 s after the boot of the DSP and the kernel panicked.
  `pcm_native.c` now uses `memset_io`. The firmware fix must not ship without this fix.
- PipeWire ignores all three cards through `ACP_IGNORE` in `60-gta4xl-audio.rules`, because ACP
  finds no usable profile. The sink is a fixed node on `hw:0,0`, see `50-gta4xl-speaker.conf`.
- Keep `api.alsa.period-num` at 8. With 32 periods of 1024 frames PipeWire restarts the PCM every
  0.3 s. `abox_rdma_pointer` probably causes this. Not analysed further.
- Android route: RDMA0 goes through the DSM of the DSP to RDMA7, SIFS1, UAIF2. The DSP owns RDMA7,
  and `aplay` on hw:0,7 ends with EIO. Linux uses RDMA0, SPUS, SIFS0, UAIF2 and no DSM.
- There is no speaker protection on this path. `gta4xl-audio` sets Amp Output Level to 2
  (12 dBV full scale). Android uses 20 (21 dBV) behind the DSM. Do not raise it without the DSM.
- `gta4xl-audio` follows the input "Exynos9610-Audio Headset Jack" and selects UAIF2 or UAIF0.
  Route change during playback: tested with the command, no plug test yet.
- Capture on WDMA3 and WDMA4 (hw:0,11, hw:0,12) ends with EIO after 1 s. So there is no microphone
  and no IV sense measurement. Card 1 is the voice wake chip.
- Checks without ears: `/proc/asound/card0/pcm0p/sub0/status` RUNNING and hw_ptr at 48000/s. dmesg
  "tas2562_mute,0", "IRQ status : 0x0". The close of the PCM 3 s after the end of playback.

A test module that calls kernel functions by kallsyms name needs care here: the two test loads
of 2026-11-01 each caused a panic and a restart before the cause was clear. Panic text:
`/proc/last_kmsg`.

## Video

- `h264_v4l2m2m` did not hang in the MFC. ffmpeg scans all `/dev/video*`, and the fimc-is stubs
  return 0 with no format for each index, so the loop did not end. `v4l2-ioctl.c` now returns
  EINVAL. This also stopped most `v4l_enum_fmt` warnings. ffmpeg now fails after 0.3 s.
- The MFC firmware (v12.2) loads, but ffmpeg cannot use the driver. `mfc_dec_reqbufs` refuses
  V4L2_MEMORY_MMAP, and VIDIOC_SUBSCRIBE_EVENT does not exist. The driver expects DMABUF from
  ION and the flow of the Samsung HAL. This is a large job, so it stops here.
- mpv needs Panfork: `vo=gpu` gives 1080p30 with 0 to 2 dropped frames. `vo=wlshm` drops half of
  the frames. Celluloid uses about 170 % CPU on the same file.
- `tools/tablet/media-setup.sh` installs uosc 5.13.0 and rtkit. Options: `/etc/mpv`.

## Battery and idle

- UPower: 29.9 Wh, correct percent, state and time to full. Discharge time not tested.
- CPU idle works: more than 96 % of the time in the deep state on both clusters.
- Load average 16 on an idle tablet is no CPU work. About 16 TEE kernel threads stay in D state.
- Idle: 450 interrupts/s and 400 context switches/s. i2c 13840000 (charger, fuel gauge) gives 45/s
  on the charger. DECON gives no interrupts while nothing changes on the panel.
- `kernel.printk` is already 4, and the console goes only to RAM. A change has no effect.
- journald woke for each kernel line, so `ReadKMsg=no`. Use `dmesg`. The WirePlumber v4l2 and
  libcamera monitors are off, because 45 dead camera nodes gave log noise on each scan.
- `tools/deploy-kernel.sh` now does the writes in a unit on the tablet. A lost SSH session in the
  middle of dd would leave a broken boot partition.
