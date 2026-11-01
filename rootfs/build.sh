#!/usr/bin/env bash
# Build the Ubuntu 24.04 arm64 GNOME rootfs as a tarball, rootless (mmdebstrap unshare mode).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-/mnt/data/android-linux}"
OUT="$WORK/out/rootfs.tar"
mkdir -p "$WORK/out"

PKGS=(
  # base
  systemd-sysv systemd-timesyncd systemd-resolved dbus-user-session udev kmod sudo locales tzdata
  console-setup keyboard-configuration ca-certificates bash-completion less vim nano htop tmux curl wget
  iproute2 iputils-ping file lsof pciutils usbutils psmisc rsync zstd xz-utils unzip
  language-pack-de language-pack-en
  # networking
  network-manager wpasupplicant iw rfkill wireless-regdb openssh-server avahi-daemon
  # bluetooth + audio
  bluez bluez-tools pipewire pipewire-pulse pipewire-alsa wireplumber libspa-0.2-bluetooth alsa-utils
  # GNOME
  gdm3 gnome-shell gnome-session gnome-shell-extension-prefs gnome-control-center gnome-settings-daemon
  gnome-terminal gnome-console gnome-text-editor nautilus gnome-system-monitor gnome-disk-utility
  gnome-keyring gnome-tweaks gnome-bluetooth-sendto xdg-desktop-portal-gnome xdg-user-dirs-gtk
  yelp-xsl adwaita-icon-theme-full fonts-cantarell fonts-dejavu fonts-noto-color-emoji fonts-ubuntu
  ubuntu-wallpapers-noble policykit-1 polkitd upower power-profiles-daemon iio-sensor-proxy
  # display stacks (Xorg fbdev fallback + Mesa)
  xserver-xorg-core xserver-xorg-video-fbdev xserver-xorg-input-libinput xwayland
  libgl1-mesa-dri libegl1 libgles2 mesa-utils libinput-tools evtest
  # GPU build/runtime deps for panfork
  libdrm2 libwayland-client0 libwayland-server0 libexpat1 libzstd1
)

IFS=,
INCLUDE="${PKGS[*]}"
unset IFS

mmdebstrap \
  --mode=unshare \
  --architectures=arm64 \
  --variant=important \
  --components="main,restricted,universe,multiverse" \
  --include="$INCLUDE" \
  --aptopt='APT::Install-Recommends "false"' \
  --dpkgopt='path-exclude=/usr/share/doc/*' \
  --dpkgopt='path-include=/usr/share/doc/*/copyright' \
  --customize-hook="copy-in $HERE/overlay/. /" \
  --customize-hook="copy-in $WORK/out/blobs/. /" \
  --customize-hook="chroot \"\$1\" /bin/sh /usr/local/sbin/gta4xl-firstsetup || echo 'W: gta4xl-firstsetup failed, fix it on the device'" \
  noble "$OUT" \
  "deb http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse" \
  "deb http://ports.ubuntu.com/ubuntu-ports noble-updates main restricted universe multiverse" \
  "deb http://ports.ubuntu.com/ubuntu-ports noble-security main restricted universe multiverse"

ls -la "$OUT"
