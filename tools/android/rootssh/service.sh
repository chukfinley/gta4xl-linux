#!/system/bin/sh
D=/data/adb/ssh
mkdir -p $D/home/.ssh $D/keys
chmod 700 $D/home/.ssh
cp -f /data/adb/modules/rootssh/bin/* $D/bin/ 2>/dev/null || { mkdir -p $D/bin; cp -f /data/adb/modules/rootssh/bin/* $D/bin/; }
chmod 755 $D/bin/*
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
$D/bin/dropbear -R -p 22 -P $D/dropbear.pid -r $D/keys/ed25519 -D $D/home/.ssh > $D/log 2>&1
