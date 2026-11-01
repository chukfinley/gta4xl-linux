#!/bin/bash
# Thunderbird, Signal, Jellyfin and 0 A.D., and with WITH_SPOTIFY=1 the Spotify web app. Run as root. You can run it again.
# No autostart, no background service. See "More apps" in docs/gta4xl.md.
export DEBIAN_FRONTEND=noninteractive LC_ALL=C

# Thunderbird: the Ubuntu package is a snap stub. The Mozilla Team PPA has a real arm64 deb.
# The pin keeps the stub out. Do not install snapd.
cat > /etc/apt/sources.list.d/mozillateam-ppa.list <<'LIST'
deb [arch=arm64 signed-by=/usr/share/keyrings/mozillateam-ppa.gpg] https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu noble main
LIST
if [ ! -s /usr/share/keyrings/mozillateam-ppa.gpg ]; then
    curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0AB215679C571D1C8325275B9BDB3D89CE49EC21' |
        gpg --dearmor > /usr/share/keyrings/mozillateam-ppa.gpg
fi
cat > /etc/apt/preferences.d/mozillateam-thunderbird <<'PIN'
Package: thunderbird*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001

Package: snapd
Pin: release *
Pin-Priority: -1
PIN
apt-get update -qq
apt-get install -y -qq --no-install-recommends thunderbird thunderbird-locale-de 0ad

# bwrap: proc_mount of this kernel calls sget() with the caller namespace, so a proc mount in a
# new user and PID namespace gives EBUSY and each flatpak run fails. A setuid bwrap does not make
# a user namespace. The override stays after a package update.
dpkg-statoverride --list /usr/bin/bwrap >/dev/null ||
    dpkg-statoverride --update --add root root 4755 /usr/bin/bwrap

# Flatpak apps. Spot (dev.alextren.Spot) is end-of-life on Flathub, so it is not used.
flatpak uninstall -y --noninteractive --system dev.alextren.Spot com.github.KRTirtho.Spotube io.github.hrkfdn.ncspot 2>/dev/null
for app in org.signal.Signal org.jellyfin.JellyfinDesktop; do
    flatpak install -y --noninteractive --system flathub "$app"
done
flatpak uninstall -y --noninteractive --system --unused

# The runtime has no Panfork, and system Mesa cannot open wl_drm on this compositor. The session
# variables point at /opt/panfork, which is not in the sandbox. So all Flatpak apps render on the
# CPU, on Wayland only. This rule also stops Xwayland with ANGLE.
flatpak override --system \
    --unset-env=LIBGL_DRIVERS_PATH --unset-env=GBM_BACKENDS_PATH \
    --unset-env=__EGL_VENDOR_LIBRARY_DIRS --unset-env=MESA_LOADER_DRIVER_OVERRIDE \
    --env=LIBGL_ALWAYS_SOFTWARE=1 --env=GSK_RENDERER=cairo --env=QT_QUICK_BACKEND=software \
    --env=QTWEBENGINE_CHROMIUM_FLAGS=--disable-gpu \
    --nodevice=dri --nosocket=x11 --nosocket=fallback-x11
flatpak override --system --nodevice=all --env=SIGNAL_DISABLE_GPU=1 org.signal.Signal
# QtWebEngine stops with a setuid bwrap, so its inner sandbox is off. The Flatpak sandbox stays.
# mpv in Jellyfin needs a GL context, so Qt Quick stays on GL (llvmpipe here).
flatpak override --system --env=QTWEBENGINE_DISABLE_SANDBOX=1 --unset-env=QT_QUICK_BACKEND org.jellyfin.JellyfinDesktop
# Signal asks about its plain password store at first start. There is no keyring here.
sudo -u user mkdir -p /home/user/.var/app/org.signal.Signal/config/Signal
[ -e /home/user/.var/app/org.signal.Signal/config/Signal/config.json ] ||
    sudo -u user sh -c 'echo "{}" > /home/user/.var/app/org.signal.Signal/config/Signal/config.json'

# 0 A.D. on Wayland and Panfork. SDL would go to Xwayland by default.
sed -i -E '/SDL_VIDEODRIVER/! s#^Exec=(.*)$#Exec=env SDL_VIDEODRIVER=wayland \1#' /usr/share/applications/0ad.desktop

# Widevine for the Spotify web player. Google has no Linux arm64 build, so widevine-installer of
# Asahi Linux takes the library from a ChromeOS image and fixes the ELF format. Brave loads it from
# its install directory. A Brave update keeps the link.
if [ ! -e /var/lib/widevine/libwidevinecdm.so ]; then
    apt-get install -y -qq --no-install-recommends squashfs-tools
    W=$(mktemp -d /var/tmp/widevine.XXXXXX)
    for f in widevine-installer widevine_fixup.py; do
        curl -fsSL -o "$W/$f" "https://raw.githubusercontent.com/AsahiLinux/widevine-installer/main/$f"
    done
    yes '' | COPY_CONFIGS=0 TMPDIR=/var/tmp sh "$W/widevine-installer"
    rm -rf "$W"
fi
ln -sfn /var/lib/widevine/WidevineCdm /opt/brave.com/brave/WidevineCdm

# Spotify web app with its own Brave profile, app id and icon. Optional: WITH_SPOTIFY=1.
if [ "${WITH_SPOTIFY:-0}" = 1 ]; then
install -m 755 /dev/stdin /usr/local/bin/spotify-web <<'SH'
#!/bin/sh
# Spotify web player. It uses an own profile, so it runs apart from the main browser.
D="$HOME/.local/share/spotify-web"
if [ ! -e "$D/Local State" ]; then
    mkdir -p "$D"
    # Widevine on, Brave telemetry off
    echo '{"brave":{"widevine_opted_in":true,"p3a":{"enabled":false,"notice_acknowledged":true},"stats":{"reporting_enabled":false}},"user_experience_metrics":{"reporting_enabled":false}}' > "$D/Local State"
fi
# Chromium looks for the CDM through this file. Brave ignores a CDM in its install directory.
mkdir -p "$D/WidevineCdm"
echo '{"Path":"/var/lib/widevine/WidevineCdm"}' > "$D/WidevineCdm/latest-component-updated-widevine-cdm"
exec /usr/bin/brave-browser-stable --user-data-dir="$D" \
    --app=https://open.spotify.com --no-first-run --no-default-browser-check \
    --ozone-platform=wayland --enable-wayland-ime --password-store=basic \
    --ignore-gpu-blocklist --disable-gpu-sandbox --use-gl=angle --use-angle=gles \
    --disable-features=Vulkan,AIChat,BraveRewards,BraveWalletConnect,BraveNews,Playlist,Speedreader,BraveVPN,Translate,OptimizationHints \
    --disable-background-networking --disable-sync --disable-extensions --disable-default-apps \
    --disable-component-extensions-with-background-pages --disable-breakpad \
    --renderer-process-limit=2 --disk-cache-size=52428800 "$@"
SH
rm -f /usr/share/applications/web-spotify.desktop
install -d /usr/share/icons/hicolor/scalable/apps
cat > /usr/share/icons/hicolor/scalable/apps/spotify-web.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><circle cx="64" cy="64" r="58" fill="#1ed760"/><g fill="none" stroke="#111" stroke-linecap="round"><path d="M32 46c22-7 46-5 66 6" stroke-width="10"/><path d="M36 65c19-5 39-4 56 5" stroke-width="8"/><path d="M40 82c15-4 31-3 45 4" stroke-width="7"/></g></svg>
SVG
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null
cat > /usr/share/applications/spotify-web.desktop <<'DESKTOP'
[Desktop Entry]
Name=Spotify
Comment=Spotify web player
Exec=/usr/local/bin/spotify-web
Icon=spotify-web
Terminal=false
Type=Application
Categories=Audio;AudioVideo;Player;
StartupWMClass=brave-open.spotify.com__-Default
DESKTOP

fi

# Calendar: gnome-calendar needs evolution-data-server and goa-daemon, this system has neither.
# It starts, but it cannot show or add a calendar. Thunderbird has CalDAV and its own password
# store, so it needs no keyring.
apt-get purge -y -qq gnome-calendar
cat > /usr/share/applications/thunderbird-calendar.desktop <<'DESKTOP'
[Desktop Entry]
Name=Calendar
Name[de]=Kalender
Comment=Calendar in Thunderbird
Exec=thunderbird -calendar
Icon=thunderbird
Terminal=false
Type=Application
Categories=Office;Calendar;
StartupWMClass=thunderbird
DESKTOP
