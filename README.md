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
| On-screen keyboard | GJS OSK with Esc, Ctrl, Tab and arrows, only with no physical keyboard |
| Edge swipes | bottom overview, top right quick settings, top middle calendar, also in full screen |
| Window handling | iPadOS grabbers: corner arc with outline resize, top bar with snap to half or full |
| Dock | Dash to Dock, always visible, for touch and mouse: window picker, close, left and right half, pinned apps |
| Right click by touch | long press and two finger tap, in all apps |
| Night Light | works in Settings, shader in the extension, the kernel ignores the LUT |
| Power key | panel off and on, touch locked while off, deep sleep after 2 min |
| Battery | percent and time estimate through UPower |
| SD card | works, ext4 on /media/sd |
| Tailscale, Brave, T3 Code, Claude and Codex CLI | work |
| Spotify (Brave web app with Widevine), Thunderbird with calendar, Signal, Jellyfin, 0 A.D. | start and open a window, see docs. Spotify login and playback open |
| WLAN | works |
| Bluetooth (BlueZ, A2DP) | keyboard works, buds drop the link after seconds, see docs |
| Sensor hub, auto rotation | works |
| Pen | detected by libinput, test open |
| Audio | Bluetooth A2DP: CMF Buds drop the link, open. Speaker sink in PipeWire with GNOME volume, jack route. Confirmation by ear open. No microphone |
| Video | mpv and Celluloid, 1080p30 H.264 on Panfork with no dropped frames, large touch controls in mpv |
| GPU (Mali-G72) | Panfork: GNOME Shell, Wayland clients, mpv, Brave, T3 Code and Mattermost on the GPU |
| Suspend | deep sleep works, automatic with the panel off on battery. Power key wake: test open |
| Hardware video decode | not with ffmpeg, the MFC driver has no MMAP buffers and no V4L2 events. Software decode handles 1080p |
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
5. Start normally. The tablet logs in and locks at once. PIN `1234`, it is the password of `user`.

After the first boot, new kernels install from Ubuntu with `tools/deploy-kernel.sh`.
Run `tools/tablet/tune.sh`, `tools/tablet/install-apps.sh`, `tools/tablet/t3-service.sh` and
`tools/tablet/media-setup.sh`, `tools/tablet/osk-setup.sh` and `tools/tablet/dock-setup.sh` on the tablet as root. `tools/tablet/build-panfork.sh` builds the GPU driver on the tablet.

## Publish

`tools/publish-github.sh NAME` creates a private repository, add `--public` for a public one.

## License

The kernel patch is GPL-2.0, as the kernel. The Panfork patch is MIT, as Mesa. The scripts and the
GNOME extension are MIT. Dash to Dock is GPL-2.0, the setup script downloads it, and its patch has the same license. Firmware belongs to Samsung and is not part of this repository.
