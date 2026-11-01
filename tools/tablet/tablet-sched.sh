#!/bin/bash
# Files that the Boost feature of Tablet Shell needs, at each boot: the EMS scheduler group for the
# big cores, and write access to the floor of the GPU clock. The group is a preference, so apps that
# the Shell starts can still run on the little cores. Run once as root.
cat > /usr/local/sbin/tablet-sched <<'SH'
#!/bin/sh
mkdir -p /dev/stune
mountpoint -q /dev/stune || mount -t cgroup -o schedtune none /dev/stune
mkdir -p /dev/stune/top-app
echo 1 > /dev/stune/top-app/schedtune.prefer_perf
echo 1 > /dev/stune/top-app/schedtune.prefer_idle
echo 10 > /dev/stune/top-app/schedtune.boost
chmod 666 /dev/stune/top-app/tasks /dev/stune/top-app/cgroup.procs
chmod 666 /sys/devices/platform/11500000.mali/dvfs_min_lock
SH
chmod 755 /usr/local/sbin/tablet-sched
cat > /etc/systemd/system/tablet-sched.service <<'UNIT'
[Unit]
Description=Scheduler group and GPU floor access for Tablet Shell
DefaultDependencies=no
Before=display-manager.service
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/tablet-sched

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now tablet-sched.service
# Brightness for the session user, written by the Control Center
sed -i '/dvfs_min_lock$/a chmod 666 /sys/class/backlight/panel/brightness' /usr/local/sbin/tablet-sched
/usr/local/sbin/tablet-sched
