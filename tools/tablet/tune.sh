#!/bin/bash
# Userland tuning: compressed swap, GNOME power menu, fewer background services.
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y -qq tlp tlp-rdw >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends power-profiles-daemon systemd-zram-generator >/dev/null 2>&1
cat > /etc/systemd/zram-generator.conf <<'CONF'
[zram0]
zram-size = ram
compression-algorithm = lz4
CONF
systemctl daemon-reload
systemctl enable --now power-profiles-daemon
systemctl start systemd-zram-setup@zram0.service
systemctl disable --now rsyslog e2scrub_reap avahi-daemon cups cups-browsed ModemManager 2>/dev/null
echo 'vm.swappiness=100' > /etc/sysctl.d/90-gta4xl.conf
sysctl -q -p /etc/sysctl.d/90-gta4xl.conf
