# Ubuntu with GNOME on the Galaxy Tab S6 Lite LTE (SM-P615, gta4xl)

Ubuntu 24.04 arm64 with a GNOME Wayland desktop on the Exynos 9611 tablet. It uses the LineageOS
kernel 4.14 with patches for a normal Linux userland. There is no VM and no Android container.

This erases Android on the tablet. You need an unlocked bootloader and LineageOS. Other models
are not tested. You do this at your own risk.

## Status

| Part | State |
|---|---|
| Boot, systemd, GDM | works |
| Display (own DRM/KMS driver over DECON) | works, GNOME Wayland |
| Touch | works |
| On-screen keyboard | works |
| Bottom edge swipe, touch resize handle, maximized windows | works, gnome-shell extension |
| Night Light | works, shader in the extension (no gamma LUT) |
| Power key | panel off and on, touch locked while off |
| Battery | percent and time estimate through UPower |
| SD card | works, ext4 on /media/sd |
| Tailscale, Brave, T3 Code, Claude and Codex CLI | work |
| WLAN | works |
| Bluetooth (BlueZ, A2DP) | works, SBC codec |
| Sensor hub, auto rotation | works |
| Pen | detected by libinput, test open |
| Audio | Bluetooth A2DP works. Speaker route tool exists, test open |
| GPU (Mali-G72) | Panfork clears at 600 FPS, draws still hang. GNOME runs on software rendering |
| Suspend | does not resume, disabled |
| Hardware video decode | open, software decode handles 1080p |
| USB network | does not work, disabled. USB serial console works |

Details and test results: [docs/gta4xl.md](docs/gta4xl.md).

## Build

Debian or Ubuntu host with `clang lld gcc-aarch64-linux-gnu mmdebstrap qemu-user-static
binfmt-support heimdall-flash adb e2fsprogs cpio`. Space: about 40 GB. Set `WORK` to the build
directory, default `/mnt/data/android-linux`.

```bash
tools/backup-android.sh   # tablet on LineageOS with rooted debugging
tools/build-all.sh
```

The firmware comes from your own tablet. Samsung files are not part of this repository.

## Install

1. Get `mkbootimg`, `avbtool` and `mkdtboimg` from AOSP into `$WORK/tools`, see `bootimg/build.sh`.
2. Put the tablet into download mode, see the button sequence in `docs/gta4xl.md`.
3. Run `tools/flash-linux.sh`. Run one heimdall session per step if a session fails.
4. Boot the debug recovery, then write the rootfs: `tools/write-to-gadget.py out/rootfs.ext4`.
5. Start normally. Login: `user`, password `gta4xl`. Change it.

After the first boot, new kernels install from Ubuntu with `tools/deploy-kernel.sh`.
Run `tools/tablet/tune.sh`, `tools/tablet/install-apps.sh` and `tools/tablet/t3-service.sh` on the
tablet as root. `tools/tablet/build-panfork.sh` builds the GPU driver on the tablet.

## Publish

`tools/publish-github.sh NAME` creates a private repository, add `--public` for a public one.
