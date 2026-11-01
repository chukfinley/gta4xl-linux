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

- `tools/tab CMD`: root shell on the tablet over Tailscale, host name `gta4xl`.
- `tools/tab-shot`: DRM framebuffer to `_scratch/screen.png`, works under Wayland.
- `tools/tab-tap.py X Y`: inject a touch tap into `/dev/input/event1`.
- `tools/tab-touch.py`: hold, two finger tap, drag, pinch and three finger swipe. Copy it to
  `/usr/local/bin/tab-touch`. Coordinates are panel pixels, in portrait. At rotation 3, a logical
  point (x, y) is the panel pixel (1200 - 1.498 y, 1.498 x).
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
  `gta4xl-tablet` applies a colour shader on `uiGroup`, driven by gsd-color. Settings reads the
  mutter property `NightLightSupported`, and mutter sets it only for a CRTC with `GAMMA_LUT_SIZE`
  above 0. So `decon_kms.c` offers a LUT of 256 entries and ignores it. A commit with only
  `GAMMA_LUT` still sends its event, because the simple pipe adds the plane to each CRTC commit.
  Test on 2026-11-01: 3000 K gave green x 0.69 and blue x 0.43 in the framebuffer, which is the
  shader value once. Six LUT changes in a row gave no `flip_done` timeout.
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

## More apps

`tools/tablet/more-apps.sh` installs the apps below. You can run it again. No app has autostart or a
background service.

Flatpak:
- This kernel calls `sget()` in `proc_mount`, so a proc mount in a new user and PID namespace gives
  EBUSY. Each `flatpak run` as `user` failed. `/usr/bin/bwrap` is now setuid, set with
  `dpkg-statoverride`. The kernel fix is `sget_userns()` with `ns->user_ns`, then remove the bit.
- The runtimes have no Panfork, and the session variables point at `/opt/panfork`. A global override
  removes these variables, sets `LIBGL_ALWAYS_SOFTWARE=1` and `GSK_RENDERER=cairo`, and removes
  `dri`, `x11` and `fallback-x11`. All Flatpak apps render on the CPU, on Wayland only.
- Flathub has no aarch64 Thunderbird. `dev.alextren.Spot` is end-of-life.

Apps, tested on 2026-11-01:
- Spotify: `/usr/local/bin/spotify-web`, Brave `--app` with its own profile in
  `~/.local/share/spotify-web`, on the GPU. App id: `brave-open.spotify.com__-Default`.
- Widevine: `widevine-installer` of Asahi Linux, version 4.10.2662.3, in `/var/lib/widevine`. Brave
  ignores a CDM in its install directory. It needs the file
  `WidevineCdm/latest-component-updated-widevine-cdm` in the profile and
  `brave.widevine_opted_in` in `Local State`. The launcher writes both.
- Test with the Shaka Widevine demo in this profile: license received, 12 s played, 303 frames, 0
  dropped. Real Spotify playback needs a login and is not tested.
- Load in this profile, sum of all processes. Page idle: PSS 419 MB, 14 % of one core. Widevine audio
  only: PSS 480 MB, 43 %. Audio and video: PSS 451 MB, 99 %.
- Audio with the panel off: 100 s with the stream active, no suspend. `gta4xl-powerkey` does not
  suspend while `wpctl status` shows `[active]`. The test did not reach the 120 s limit.
- MPRIS: `org.mpris.MediaPlayer2.brave.instanceN` reports Playing and Pause works. A uinput
  `KEY_PLAYPAUSE` starts playback through gsd-media-keys.
- Thunderbird 140: Mozilla Team PPA with an APT pin, real arm64 deb, on Panfork. It also gives the
  calendar: `gnome-calendar` needs `evolution-data-server` and `goa-daemon`, so it is removed. The
  entry `thunderbird-calendar.desktop` runs `thunderbird -calendar`.
- Signal 8.33: Flatpak, `--disable-gpu`, plain password store because there is no keyring.
- Jellyfin Desktop 2.0: Flatpak, llvmpipe. QtWebEngine stops with a setuid bwrap, so
  `QTWEBENGINE_DISABLE_SANDBOX=1`. It needs Qt Quick on GL for mpv, so no `QT_QUICK_BACKEND`.
- 0 A.D. 0.0.26: apt, Panfork, `SDL_VIDEODRIVER=wayland` in the desktop file.

Test notes:
- `--user-data-dir` is not a separate word in `/proc/PID/cmdline` of Brave, the main process joins
  its arguments. Do not match the full line.
- Brave exits with code 0 when the compositor goes away, this is no Brave fault.
- A new `systemd-run --user` unit has no `WAYLAND_DISPLAY`. Set it with `-E`.

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

## Bluetooth audio

Open: the CMF Buds 2 Plus end each link 1.6 to 10 s after it starts, with HCI reason 0x13 (remote
user). Bead android-linux-tf8 has the state. The trace shows no error on the tablet side:
- With HFP: SLC setup completes (`AT+BRSF` to `AT+BIEV`), A2DP SBC is open, 0.9 s later the buds
  end the link. "Unable to get io data" in the bluetoothd log comes after that, it is no cause.
- Without HFP: AVDTP and AVRCP complete, the buds read our SDP records, 0.7 s later they end the
  link. So HFP is no cause.
- One link that the buds started themselves stayed 10 s and the sink came up. The tablet has no
  kernel change in Bluetooth since the night it worked. Page timeouts come for 20 min at a time.
- The likely cause is on the side of the buds: the two places of Dual Connection are in use by
  other devices. This is not proven.

HFP is off (`51-gta4xl.lua`). WirePlumber 0.4 reads those two keys, the adapter then has no
Handsfree UUID. HFP has no use here: `SCO MTU 0:0` and no microphone. The node priority 2000 makes
Bluetooth the default sink when it connects, the speaker has 800. A saved default sink would pin the
speaker, so `tune.sh` removes `default-nodes`.

Trace method: `btmon -w FILE`, then `btmon -T -r FILE`. A text pipe loses the end when btmon stops.

Deep sleep ends all Bluetooth links. The Targus connects again at the next key press.

## Video

- `h264_v4l2m2m` did not hang in the MFC. ffmpeg scans all `/dev/video*`, and the fimc-is stubs
  return 0 with no format for each index, so the loop did not end. `v4l2-ioctl.c` now returns
  EINVAL. This also stopped most `v4l_enum_fmt` warnings. ffmpeg now fails after 0.3 s.
- Brave on YouTube: no h264ify. It would need a Web Store extension, the gain is small and
  software decode already handles 1080p.
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

## Touch and windows

All of this is in the extension `gta4xl-tablet`, except the on-screen keyboard.

Swipes:
- Bottom edge: overview.
- Top edge, by start position: right third quick settings, middle third calendar and
  notifications, left third leaves full screen. This works in full screen and in all rotations.
  GNOME has the action `unfullscreen` on the same gesture, and it fires from all of the edge. So
  the extension removes that action and does its work in the left third.
- `EdgeDragAction` emits `activated` when the finger goes up, so the menus do not fight the grab.

Window grabbers, from iPadOS: a thin arc at the bottom right corner and a bar at the top centre.
- They draw only. A tap in the zone still reaches the app. A drag of more than 4 px takes the touch.
  GTK starts its title bar drag at 8 px, and then a mutter grab takes all touch events, so the
  extension must act first. The end of such a client drag never arrives: `TOUCH_BEGIN` on a used
  slot resets the state.
- Corner drag: an outline and the arc follow the finger in the compositor. The client gets one
  resize at the end. A maximized window leaves that state at the end of the drag.
- Bar drag: moves the window, which stays on the screen. Drop at the left or right edge fills that
  half, drop at the top maximizes. A preview shows the target. A drag from a half restores the size.
- A half in portrait is 400 px. Brave has a larger minimum width and does not snap there.

Frame time, stage `after-paint` intervals during a drag, 2026-11-01:

| Drag | Input | p50 | p95 | max |
|---|---|---|---|---|
| Corner, client resize at 30 Hz, Text Editor | 13 Hz | 165 ms | 173 ms | 219 ms |
| Corner, outline, Electron window | 120 Hz | 17.7 ms | 27.9 ms | 55 ms |
| Bar, move, Electron window | 120 Hz | 16.6 ms | 26.7 ms | 47 ms |

Secondary click (touch points cancel with `wl_touch.cancel`, then a virtual pointer clicks):
- Long press: 450 ms, before the 500 ms timers of GTK and Chromium. The click comes when the finger
  goes up. With a finger down mutter drops the pointer focus and the press is lost.
- Two finger tap: both fingers down and up in 350 ms, click at the middle.
- Mutter has no API to cancel touch points. It sends the cancel when a stage gesture begins. So a
  `Clutter.GestureAction` with 9 points, which Clutter never starts, emits `gesture-begin`.
- Brave needs no flag. Result on an image: `touchcancel`, `mousedown` button 2, `contextmenu`, no
  `dragstart`, and the menu has "Bild speichern unter".
- Drag, pinch, three finger swipe and the edge swipes give no click.

Test without hands in the live session is a risk, a touch reaches what is open. A separate shell is
safe: a new `HOME`, `dbus-run-session`, `gnome-shell --headless --unsafe-mode --virtual-monitor
1200x2000 --wayland --no-x11 --wayland-display wl-hs`. Use `busctl call ... Eval` with a virtual
touchscreen and `WAYLAND_DEBUG=1` on a client. Eval needs
`import("resource:///org/gnome/shell/ui/main.js")`, `imports.ui.main` fails. Input there is slow,
events arrive in batches of about 1 s, so timing tests belong on the hardware.

New extension code needs a new session. Use `systemctl restart gdm`, this logs in again.

On-screen keyboard: the GNOME Shell keyboard with a tool row, from Tablet Shell.
- The zip has private file modes and no compiled schema, both stop the extension.
- It has no rule for a physical keyboard. Its setting "never" still opens it for a touch on a shell
  text field. So `gta4xl-tablet` turns the extension off while an external keyboard is connected.
  `gpio_keys`, the touchscreen, the headset jack and BlueZ `(AVRCP)` devices do not count.
- It opens on any touch while a text field has focus.
- It runs only in the user session, so the lock screen keeps the PIN pad.

Targus keyboard: `61-gta4xl.hwdb` maps Caps Lock to Super for this keyboard. The HID report offers
Super on all keyboards, so the input capabilities do not show if the key exists.

A shell crash: `org.gnome.Shell-disable-extensions.service` sets `disable-user-extensions`, this
stays after a new login, and the PIN pad and all gestures are gone. The unit is masked. Reset with
`gsettings set org.gnome.shell disable-user-extensions false`.

Known crash: mutter 46.2 ends with SIGSEGV when a Wayland client dies with an open menu. It occurs
with a normal mouse and with both extensions off. Close the menu first. See bead android-linux-8iv.

## Desktop

All general UI is the project Tablet Shell (`tablet-shell@gnome-tablet`): Home Screen, Dock, gestures,
window controls, Control Center, Notification Center, lock screen, widgets, on-screen keyboard.
Install: `tools/tablet/tablet-shell.sh DIR` on the computer, `tools/tablet/slim-session.sh` as root
on the tablet. `gta4xl-tablet` keeps only the Night Light shader and the lock after boot.

Lock rule: the session locks only after a boot or a session start, and by hand. Short press on Power
switches the panel, a press of 1 s or more locks. Deep sleep does not lock.

Removed for speed: gsd plugins A11ySettings, Datetime, Housekeeping, Keyboard, PrintNotifications,
ScreensaverProxy, Sharing, Smartcard, Sound, UsbProtection, Wacom, Wwan (masks in
`etc/systemd/user`, hidden autostarts), tracker, power-profiles-daemon, apt and man-db timers.

Load average near 17 on an idle desktop: about 15 Samsung TEE kernel threads wait in D state
(`tz_worker_thread`, `tz_iwsock`, `ree_time`, `scsi_srpmb_work`, `simpleinteractive`). The CPU is 99 %
idle. A fix needs `TASK_IDLE` in those drivers.

Trap: on battery the panel off state starts deep sleep after 120 s, and then WLAN and SSH go. For
tests hold `systemd-inhibit --what=sleep --mode=block`.

## Access and security

- sshd accepts connections from 100.64.0.0/10 only. `user` logs in with the password, root with a
  key only. Tailscale SSH is off, the default tailnet policy asks for an interactive check. Serial
  console has no auto login.
- The session starts with auto login and locks at once. The PIN pad of the extension sends the
  digits to the normal password prompt. Default PIN: `1234`, the password of `user`.
- The disk is not encrypted and the bootloader is unlocked: physical access gives access to data.

## Network interfaces, hotspot, battery log

The SCSC driver makes 4 WLAN interfaces: `wlan0`, `wlan1`, `p2p0`, `wifi-aware0`. Without a filter GNOME shows 4 adapters. `etc/NetworkManager/conf.d/51-gta4xl-unmanaged.conf` keeps only `wlan0` under NetworkManager.

The test hotspot on the PC is the NetworkManager profile `Hotspot-1` (SSID `HIBY`, open network, USB adapter RTL8812AU). It has no autoconnect. After you connect the adapter again, run `nmcli connection up Hotspot-1`.

`gta4xl-batterylog.service` writes state changes to `/var/lib/gta4xl-battery/events.jsonl`. `akku-statistik` reads this file, and `akku-statistik --text` prints the same data. The service reads the screen state from `/sys/class/backlight/panel/brightness`, which is 0 at DPMS off. The `otg` power supply reports online with a USB mouse attached, so it does not count as charger.

## GTK4 dumb buffers

GTK4 with the GL renderer can ask Panfrost for a scanout buffer that is not 32 bpp. Mesa then calls `DRM_IOCTL_MODE_CREATE_DUMB`. `decon_kms.c` accepted only 32 bpp and returned EINVAL, so `get_back_bo` failed and the old code kept a back buffer with a NULL image. The next swap then crashed in `create_wl_buffer`. Mesa now clears the back buffer on failure, and `dk_dumb_create` accepts each size that is a multiple of 8 bits.

## USB-C monitor test

A USB-C monitor charges the tablet with USB PD and shows a Realtek Billboard device (`0bda:5450`). This device reports SVID `0xFF01`, so the monitor offers DisplayPort Alt Mode and the tablet does not enter it.

Facts from the kernel source:

- `include/dt-bindings/clock/exynos9610.h` has `DP_LINK` clocks in CMU_USB, and `dpu20/cal_9610` has DisplayPort registers. So the SoC appears to have a DisplayPort block.
- `sm5713_policy.c` has PD messages for discover, enter mode and DP configure.
- `CONFIG_EXYNOS_DISPLAYPORT` is off, the device tree has no DisplayPort node, `has_combo_phy` is 0, and dwc3 runs with `maximum-speed = high-speed`.

The open question is the board: DisplayPort needs the SuperSpeed lanes at the connector, and public sources describe this port as USB 2.0. Test: set dwc3 to `super-speed`, attach a USB 3 device, and look for it on bus 002. If it stays on bus 001 in both plug directions, the lanes are probably not connected, and native video out is not possible.

## Zed on the GPU

Zed uses wgpu. Panfork has no Vulkan, but the wgpu GL backend works on Panfork with three changes. `tools/tablet/zed.sh` installs Zed and `/usr/local/bin/zed` sets the variables.

- `/opt/panfork/share/glvnd/egl_vendor.d/50_mesa.json` has the full library path. The RPATH of Zed has `/usr/lib/aarch64-linux-gnu`, so without it Zed loads the Ubuntu `libEGL_mesa`, which has no driver for this GPU.
- `PANFORK_EGL_WL_PBUFFER=1`: wgpu looks for an EGL config with the pbuffer bit in each tier and never makes a pbuffer. The Wayland configs have this bit only with this variable.
- `PANFORK_VS_SSBO=1`: Panfrost reports 0 storage buffers for vertex shaders. Zed reads them in the vertex shader, so the pipelines were invalid. Do not set this variable system wide.

Check: `~/.local/share/zed/logs/Zed.log` shows `Selected GPU adapter: "Mali-G72 (Panfrost)" (Gl)` and no `GPU error`. Zed uses about 18 % of one core after start, and about 160 % on lavapipe.

The Spotify web app is optional now: `WITH_SPOTIFY=1 tools/tablet/more-apps.sh`.

## Creative apps

`tools/tablet/creative-apps.sh` installs the apps. `tools/tablet/apps.json` has the state of each app on the tablet: source, install command, renderer, memory, touch rating, and the type of evidence.

`tools/tablet/gpu-probe.sh ID SECONDS -- CMD` starts an app in the session and writes one JSON line. An app is on the GPU only if a process has `/dev/mali0` open and has `/opt/panfork/lib/dri` mapped. The driver file alone is not proof, llvmpipe uses the same file. Flatpak moves an app to a different cgroup, so the probe reports `exited` while the window is open.

Rules:
- Flatpak apps have no GPU. The system override of `more-apps.sh` removes `/dev/dri` and sets `GSK_RENDERER=cairo`.
- GTK3 apps draw with cairo on the CPU, so they are `software`.
- Krita starts on X11 by default. `QT_QPA_PLATFORM=wayland` and `qtwayland5` put it on Mali with no Xwayland.
- Xwayland starts on demand, with glamor on Panfork. The test had no reset and no GPU fault.
- Blender 4.0 needs OpenGL 4.3. Panfork has OpenGL 3.1 (`eglinfo -p wayland`), so Blender is not installed.
- Kdenlive is removed. `user@1000.service` got SIGKILL at 15:17:00 on 2026-11-01 while Kdenlive started. dmesg has no OOM entry and the kernel has no low memory killer, so the cause is not known. Do not treat this as proof against Kdenlive.

ArtCraft has two parts. The Crafting Apps (PhotoCraft, VectorCraft, LightCraft, PdfCraft) are Rust and egui, Apache-2.0 or MIT, with official `linux-aarch64` packages. They use the wgpu GL backend on Panfork. LightCraft does the photo work on the CPU, because it asks for Vulkan. ArtCraft Studio is a client for cloud models, there is no Linux package. `artcraft-native` (egui) builds in an amd64 Ubuntu container with arm64 multiarch libraries:
`cargo build -p artcraft_native --release --target aarch64-unknown-linux-gnu`, with `SQLX_OFFLINE=true`, `PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig` and `make`, `cmake`, `nasm`, `clang`. The link needs `libwebkit2gtk-4.1-dev:arm64`.

Flutter Linux arm64 release: an `ubuntu:24.04` arm64 container under qemu with the Flutter 3.47.0 SDK and `make gcc g++ clang cmake ninja-build libgtk-3-dev libsecret-1-dev`. The `webcrypto` build hook looks for `aarch64-linux-gnu-gcc`, so `gcc` is necessary next to clang. A clean build takes about 15 min. Keep the source in a copy under `/mnt/data/android-linux/tmp`. Install the bundle to `/opt/notebookllm`.

Flutter results: Impeller on Mali (`OpenGLESSDF`), 0 GPU faults, touch events arrive as `kind=touch`. On touch the engine gives `pressureMin` and `pressureMax` values with no meaning, so use them only for a stylus. A filled freehand path of about 2 px has gaps, because this path has no MSAA.

Pen: `tools/tablet/pen-test.py` writes events to `sec_e-pen` and logs what a GTK window receives. Axes: X 0 to 13536 on the short side, Y 0 to 22560, pressure 0 to 4095, no tilt. libinput gets position and pressure.

The panel goes off on battery and the tablet sleeps after 120 s. Then only the Power key wakes it, and all SSH work stops. Connect the charger before long tests.

Kernel #23: `dk_dumb_create` accepts each size in bits that is a multiple of 8, and `proc_mount` uses `sget_userns`. So Settings no longer needs `GSK_RENDERER=cairo`, and `bwrap` is no longer setuid.

## Wayfire session

`tablet-session.service` (PAM login, tty7, logind seat) starts `/usr/local/bin/tablet-session`. It replaces gdm: `tools/tablet/session-wayfire.sh`, `session-gnome.sh`, `session-confirm.sh`. Files: `tools/tablet/desktop-push.sh`, packages: `tools/tablet/desktop-install.sh`. Four failures in one minute start gdm.

Facts found on the way:

- Do not set `WLR_DRM_NO_ATOMIC`. The legacy path calls `drmModeSetCursor`, the shim has no cursor plane, so the commit fails and Wayfire stops in `post_init`. Atomic works. The cursor is a software cursor.
- GTK apps hung at start while `xdg-desktop-portal` waited for its GNOME back end: `XDG_CURRENT_DESKTOP=wayfire` and `/etc/xdg-desktop-portal/wayfire-portals.conf`.
- Power key: `wlopm` through wlr-output-power, the backlight goes to 0 and comes back. Panel state stays readable in `/sys/class/drm/card0-DSI-1/dpms`.
- Wayfire IPC: the session sets `_WAYFIRE_SOCKET=/run/user/1000/wayfire-session.socket`. A second Wayfire on the default path unlinks the socket of the first.
- WLAN firmware restarts: "Received DEAUTH, reason = 7" after `WIFI_EVENT_ROAM_SEARCH_STARTED`, then a minimoredump, every few minutes on the test hotspot. NCHO mode resets at each association, so the dispatcher sets the roam limits again at `dhcp4-change`. Effect on the drops is not proven yet.
- Output scale 1.5: Qt 6.4 and GTK 3 have no fractional scale, they draw at scale 2 and the compositor scales down. On gradients this gives a grid of stripes, so the wallpaper is drawn in the compositor at panel pixels. GTK 4 uses `GDK_DEBUG=gl-fractional`.
