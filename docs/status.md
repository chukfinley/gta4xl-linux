# Project status

Date of this state: 2026-11-01, 17:55. Update this file at each milestone.

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

Installed: Brave, YouTube web app, T3 Code, Zed (GPU), Terminal, Thunderbird with calendar, Signal, Jellyfin, 0 A.D., Krita, GIMP, Inkscape, MyPaint, Xournal++, Rnote, Drawing, Audacity, Shotcut, the Craft apps, ArtCraft native client, notebookllm, Akku-Statistik.

Removed: Waydroid, Spotify (optional with `WITH_SPOTIFY=1`), Kdenlive, Dash to Dock, GJS OSK, web apps for Claude, Bitwarden and T3 Chat.

User login steps are open for Signal, Jellyfin, Thunderbird and the Nextcloud calendar.

## Desktop

Tablet Shell (`~/git/tablet-shell`, not published) is the desktop. See `docs/status.md`, `docs/performance.md` and `docs/HANDOVER.md` in that repo.

Open list: live resize on the tablet, app switch time, window controls of Electron apps, 8 items of the iPadOS spec, test of each control, then an independent check.
