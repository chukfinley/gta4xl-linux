# Root SSH on LineageOS (Magisk module)

Dropbear 2025.88, built static for aarch64 with `--disable-zlib --disable-syslog --disable-shadow`
and `make PROGRAMS="dropbear dropbearkey scp" STATIC=1`. The binaries are not in git: build them,
then put them in `bin/` of the module.

- The module adds `/system/etc/passwd`, `group` and `shells`. Without `shells`, dropbear says
  "User 'root' has invalid shell, rejected". Without `passwd`, root has no home.
- Keys only: `/data/adb/ssh/home/.ssh/authorized_keys`. Host key: `/data/adb/ssh/keys/ed25519`.
- `service.sh` starts `dropbear -R -p 22` after boot. Log: `/data/adb/ssh/log`.
- This build has no `-E` and no `-s`: both give the usage text and no server.
- Over USB: `adb forward tcp:2222 tcp:22`, then `ssh -p 2222 root@127.0.0.1`.
- Root for adb: LineageOS is userdebug, so `adb root` works. Magisk then allows adb su with
  `magisk --sqlite "REPLACE INTO settings (key,value) VALUES('root_access',3)"`.
