#!/bin/bash
# Build Panfork (Mesa panfrost on kbase) natively on the tablet, installed to /opt/panfork.
export DEBIAN_FRONTEND=noninteractive

apt-get install -y -qq --no-install-recommends meson ninja-build python3-mako python3-setuptools bison flex \
  glslang-tools libglvnd-dev libdrm-dev libwayland-dev libwayland-egl-backend-dev wayland-protocols libexpat1-dev zlib1g-dev \
  libzstd-dev libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev libxcb-dri2-0-dev libxcb-dri3-dev libxcb-glx0-dev \
  libxcb-present-dev libxcb-randr0-dev libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev libxshmfence-dev \
  libxxf86vm-dev libxrandr-dev pkg-config cmake gcc g++ >/dev/null 2>&1
rm -rf /opt/src/panfork; mkdir -p /opt/src/panfork && tar xzf /root/panfork.tgz -C /opt/src/panfork
cd /opt/src/panfork
patch -p1 < /root/panfork-jm.patch
meson setup build --prefix=/opt/panfork --libdir=lib --buildtype=release \
  -Dgallium-drivers=panfrost,kmsro,swrast -Dvulkan-drivers= -Dplatforms=wayland,x11 \
  -Dglx=dri -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled -Dglvnd=true \
  -Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dzstd=enabled -Dgallium-vdpau=disabled \
  -Dgallium-va=disabled -Dgallium-xa=disabled -Dgallium-omx=disabled -Dgallium-nine=false \
  -Dshared-glapi=enabled -Dbuild-tests=false 2>&1 | tail -5
nice -n 10 ninja -C build -j6 2>&1 | tail -8
echo BUILD-RC=$?
