# Project status

Date of this state: 2026-11-01, 22:50. Update this file at each milestone.

## Device

| Area | State |
|---|---|
| Kernel | #23 runs. Boot, Deep Sleep and GPU clocks work |
| GPU | Panfork on Mali-G72. GNOME, Brave, Zed, Krita and Settings use the GPU |
| Display | Rotation and Night Light work. No USB-C video: lanes not checked (`gyx`) |
| WLAN | Works on the test hotspot. SSH through Tailscale only |
| Bluetooth | Keyboard works. CMF Buds disconnect after 1.6 to 10 s (`tf8`) |
| Audio | Speaker path works. Microphone has an EIO fault (`6nw`). Speaker test by ear is open |
| Pen | Position and 4096 pressure levels reach libinput. App test is open (`fbv`) |
| Battery | About 3.3 W under load, about 8 h from full. Akku-Statistik logs since 2026-11-01 |
| Sleep | No automatic lock or sleep. With the panel off on battery, sleep starts after 120 s. Then only the power key wakes the tablet, and SSH is off |
| Stability | Open: `user@1000` SIGKILL at 15:17 with no known cause (`d48`), shell crash when a client dies with an open menu (`8iv`) |

## Apps

Installed on the device (user choice, 2026-11-02): Brave, Alacritty, 0 A.D., T3 Code, Zed (GPU), Signal, Files (Nautilus), Einstellungen, Akku-Statistik. Calculator, PDF viewer, image viewer, archive tool and text editor stay installed for file types, but are hidden in the launcher.

Removed: Krita, GIMP, Inkscape, MyPaint, Xournal++, Rnote, Drawing, Audacity, Shotcut, the Craft apps, notebookllm, Thunderbird and its calendar, Jellyfin, Mattermost, RustDesk, Celluloid, mpv, GNOME Maps, Weather, Clocks, Sound Recorder, Characters, Fonts, Logs, Disk Usage, Disks, btop, htop, YouTube web app, Recommended Apps, Waydroid, Spotify, Kdenlive. The scripts in tools/tablet can still install them.

The device is used mainly as a remote machine for T3 Code, with a keyboard.

## Desktop

Own desktop on Wayfire 0.9 with an own plugin and Qt Quick clients: repo `~/git/tablet-desktop`, local, not published. GNOME Shell, gdm and GNOME Settings are removed. Nautilus stays as Files. Tablet Shell (`~/git/tablet-shell`) is stopped.

State files in that repo: `docs/status.md`, `docs/feature-list.md`, `docs/gestures.md`, `docs/gnome-design.md`, `docs/audit.md`, `docs/design-review.md`.

The look follows upstream GNOME (gnome-shell 51.1, libadwaita 1.10), with touch sizes. The audit of 2026-11-01 found 28 bugs, and all are closed. Several fixes are not tested with a real finger. Open: RAM in use with apps open (about 1.6 GB, 989 MB after boot), hidden window pill, recent apps in the Dock, pen.
