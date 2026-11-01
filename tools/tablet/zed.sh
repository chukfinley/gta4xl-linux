#!/bin/bash
# Zed editor on the GPU. Panfork has no Vulkan, so Zed uses the wgpu GL backend.
# PANFORK_EGL_WL_PBUFFER: wgpu looks for a config with the pbuffer bit.
# PANFORK_VS_SSBO: Zed reads storage buffers in the vertex shader.
# Needs panfork-system.sh, and both patches in gpu/panfork-jm.patch.
# Run as root. You can run it again.
set -e
T=$(mktemp -d /var/tmp/zed.XXXXXX)
curl -fsSL -o "$T/zed.tar.gz" https://zed.dev/api/releases/stable/latest/zed-linux-aarch64.tar.gz
tar xzf "$T/zed.tar.gz" -C "$T"
rm -rf /opt/zed.app
mv "$T/zed.app" /opt/zed.app
rm -rf "$T"
install -m 755 /dev/stdin /usr/local/bin/zed <<'SH'
#!/bin/sh
export PANFORK_EGL_WL_PBUFFER=1 PANFORK_VS_SSBO=1
exec /opt/zed.app/bin/zed "$@"
SH
sed -e 's#^Exec=zed#Exec=/usr/local/bin/zed#' -e 's#^TryExec=.*##' \
    -e 's#^Icon=.*#Icon=/opt/zed.app/share/icons/hicolor/512x512/apps/zed.png#' \
    /opt/zed.app/share/applications/dev.zed.Zed.desktop > /usr/share/applications/dev.zed.Zed.desktop
update-desktop-database /usr/share/applications
sync
