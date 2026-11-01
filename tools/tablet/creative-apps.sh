#!/bin/bash
# Creative apps for touch and pen. Run as root, you can run it again. No autostart, no service.
# See "Creative apps" in docs/gta4xl.md. The test state of each app is in tools/tablet/apps.json.
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
APT="apt-get -o DPkg::Lock::Timeout=900 install -y -qq --no-install-recommends"

$APT krita krita-l10n qtwayland5 qt6-wayland xournalpp inkscape gimp audacity mypaint drawing shotcut

# ArtCraft Crafting Apps: official linux-aarch64 packages, Apache-2.0 or MIT. Native Rust and egui.
# Check the file with SHA256SUMS.txt of the release before you install it.
ver() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/storytold/$1/releases/latest" | sed 's#.*/v##'; }
for app in photocraft vectorcraft lightcraft pdfcraft; do
    v=$(ver "$app")
    d=$(mktemp -d)
    base="https://github.com/storytold/$app/releases/download/v$v"
    if curl -fsSL -o "$d/$app.deb" "$base/$app-$v-linux-aarch64.deb" &&
        curl -fsSL -o "$d/sums" "$base/SHA256SUMS.txt" &&
        [ "$(sha256sum < "$d/$app.deb" | cut -d' ' -f1)" = \
          "$(grep "$app-$v-linux-aarch64.deb" "$d/sums" | cut -d' ' -f1)" ]; then
        apt-get -o DPkg::Lock::Timeout=900 install -y -qq --no-install-recommends "$d/$app.deb"
    else
        echo "$app: download or checksum failed" >&2
    fi
    rm -rf "$d"
done

# Rnote comes from Flathub. The system wide Flatpak override of more-apps.sh gives it GSK_RENDERER=cairo.
flatpak install -y --noninteractive --system flathub com.github.flxzt.rnote

# Krita starts on X11 by default. On Wayland its canvas runs on Mali with no Xwayland and GLX.
D=/usr/share/applications/org.kde.krita.desktop
[ -f "$D" ] && sed -i -E '/QT_QPA_PLATFORM/! s#^Exec=krita#Exec=env QT_QPA_PLATFORM=wayland krita#' "$D"

# notebookllm: copy the Linux arm64 bundle to /opt/notebookllm first, see docs/gta4xl.md.
if [ -x /opt/notebookllm/notebookllm ]; then
    cat > /usr/share/applications/notebookllm.desktop <<'DESKTOP'
[Desktop Entry]
Name=NotebookLLM
Comment=Notes and PDF drawing
Exec=/opt/notebookllm/notebookllm
Icon=accessories-text-editor
Terminal=false
Type=Application
Categories=Office;Graphics;
StartupWMClass=com.notebookllm.notebookllm
DESKTOP
fi

# ArtCraft egui client: cross build, see docs/gta4xl.md. It needs WebKit for the Midjourney login.
if [ -x /usr/local/bin/artcraft-native ]; then
    $APT libwebkit2gtk-4.1-0
    cat > /usr/share/applications/artcraft-native.desktop <<'DESKTOP'
[Desktop Entry]
Name=ArtCraft
Comment=AI image and video client, needs an account
Exec=/usr/local/bin/artcraft-native
Icon=applications-graphics
Terminal=false
Type=Application
Categories=Graphics;
DESKTOP
fi
