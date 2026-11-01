#!/bin/bash
# Switch GNOME Shell between Panfork (GPU) and system Mesa (llvmpipe). Run as root on the tablet.
# The next login or reboot uses the new setting. This script does not stop the running session.
#   panfork-session.sh enable | disable | status
#
# Only gnome-shell uses Panfork. Apps stay on system Mesa: the extension below removes the
# Panfork variables from the shell after start, otherwise each app inherits them.
set -e
DROPIN=/etc/systemd/user/org.gnome.Shell@wayland.service.d
EXT=/usr/share/gnome-shell/extensions/panfork-env@gta4xl
UUID=panfork-env@gta4xl
USERNAME=user

as_user() {
    runuser -u "$USERNAME" -- env XDG_RUNTIME_DIR=/run/user/1000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "$@"
}

case "$1" in
enable)
    mkdir -p "$DROPIN" "$EXT"
    cat > "$DROPIN/panfork.conf" <<'CONF'
[Service]
Environment=LD_LIBRARY_PATH=/opt/panfork/lib
Environment=LIBGL_DRIVERS_PATH=/opt/panfork/lib/dri
Environment=GBM_BACKENDS_PATH=/opt/panfork/lib/gbm
Environment=__EGL_VENDOR_LIBRARY_DIRS=/opt/panfork/share/glvnd/egl_vendor.d
Environment=MESA_LOADER_DRIVER_OVERRIDE=exynos
CONF
    cat > "$EXT/metadata.json" <<'CONF'
{"uuid": "panfork-env@gta4xl", "name": "Panfork environment", "description": "Keep apps on system Mesa", "shell-version": ["46"]}
CONF
    cat > "$EXT/extension.js" <<'CONF'
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const VARS = ['LD_LIBRARY_PATH', 'LIBGL_DRIVERS_PATH', 'GBM_BACKENDS_PATH',
    '__EGL_VENDOR_LIBRARY_DIRS', 'MESA_LOADER_DRIVER_OVERRIDE'];

export default class PanforkEnv extends Extension {
    enable() {
        VARS.forEach(v => GLib.unsetenv(v));
    }

    disable() {
    }
}
CONF
    as_user gnome-extensions enable "$UUID" 2>/dev/null ||
        as_user python3 - <<'CONF'
import ast, subprocess
key = ['org.gnome.shell', 'enabled-extensions']
now = ast.literal_eval(subprocess.check_output(['gsettings', 'get', *key], text=True).replace('@as ', ''))
if 'panfork-env@gta4xl' not in now:
    subprocess.check_call(['gsettings', 'set', *key, str(now + ['panfork-env@gta4xl'])])
CONF
    as_user systemctl --user daemon-reload
    echo "enabled, active after the next login"
    ;;
disable)
    rm -f "$DROPIN/panfork.conf"
    rmdir "$DROPIN" 2>/dev/null || true
    as_user gnome-extensions disable "$UUID" 2>/dev/null || true
    rm -rf "$EXT"
    as_user systemctl --user daemon-reload
    echo "disabled, active after the next login"
    ;;
status)
    [ -f "$DROPIN/panfork.conf" ] && echo "drop-in: present" || echo "drop-in: absent"
    P=$(pgrep -u "$USERNAME" -x gnome-shell | head -1)
    grep -q /dev/mali0 "/proc/$P/maps" 2>/dev/null && echo "gnome-shell $P: GPU" || echo "gnome-shell $P: software"
    ;;
*)
    echo "usage: $0 enable|disable|status" >&2
    exit 1
    ;;
esac
