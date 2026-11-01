#!/bin/bash
# Use Panfork for all apps. With GNOME Shell on Panfork, system Mesa clients cannot open the
# wl_drm device: "failed to get driver name for fd -1".
#   panfork-system.sh enable | disable
# The next session uses the new setting.
set -e
ENVFILE=/etc/environment.d/90-panfork.conf
case "$1" in
enable)
    mkdir -p /etc/environment.d
    echo /opt/panfork/lib > /etc/ld.so.conf.d/00-panfork.conf
    # Full path: apps with /usr/lib in their RPATH (Zed) would else load the Ubuntu libEGL_mesa
    sed -i 's#"library_path" : "libEGL_mesa.so.0"#"library_path" : "/opt/panfork/lib/libEGL_mesa.so.0"#' \
        /opt/panfork/share/glvnd/egl_vendor.d/50_mesa.json
    ldconfig
    cat > "$ENVFILE" <<'CONF'
LIBGL_DRIVERS_PATH=/opt/panfork/lib/dri
GBM_BACKENDS_PATH=/opt/panfork/lib/gbm
__EGL_VENDOR_LIBRARY_DIRS=/opt/panfork/share/glvnd/egl_vendor.d
MESA_LOADER_DRIVER_OVERRIDE=exynos
CONF
    grep -q MESA_LOADER /etc/environment || cat "$ENVFILE" >> /etc/environment
    # The extension removed the variables from the shell so that apps stayed on system Mesa
    rm -rf /usr/share/gnome-shell/extensions/panfork-env@gta4xl
    ;;
disable)
    rm -f /etc/ld.so.conf.d/00-panfork.conf "$ENVFILE"
    sed -i -E '/^(LIBGL_DRIVERS_PATH|GBM_BACKENDS_PATH|__EGL_VENDOR_LIBRARY_DIRS|MESA_LOADER_DRIVER_OVERRIDE)=/d' /etc/environment
    ldconfig
    ;;
*)
    echo "usage: $0 enable|disable" >&2
    exit 1
    ;;
esac
