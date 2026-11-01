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
| WLAN | works |
| Bluetooth (BlueZ) | hci0 works, audio test open |
| Sensor hub, rotation bridge | hub and data work, GNOME test open |
| Pen | open |
| Audio | open |
| GPU (Mali-G72) | open, software rendering |
| Suspend | does not resume, disabled |
| USB network | open, the USB serial console works |

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
