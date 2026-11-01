#!/bin/bash
# Start one app in the desktop session and report how it renders. Run as root on the tablet.
#   gpu-probe.sh ID [SECONDS] -- COMMAND...      start, measure, stop
#   gpu-probe.sh --attach PATTERN [SECONDS]      measure a running app, exact process name
# Output: one JSON line. renderer is "gpu" only if a process has /dev/mali0 open and has the
# Panfork driver mapped. A GL client on llvmpipe has the driver mapped and no /dev/mali0.
UIDN=1000
export XDG_RUNTIME_DIR=/run/user/$UIDN DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UIDN/bus

faults() { dmesg | grep -cE 'mali.*(fault|FAULT|Unhandled)'; }

pids_of_unit() { cat "/sys/fs/cgroup/user.slice/user-$UIDN.slice/user@$UIDN.service/app.slice/$1.service/cgroup.procs" 2>/dev/null; }

measure() { # pids in $PIDS
    local t0 t1 c0=0 c1=0 p
    for p in $PIDS; do c0=$((c0 + $(awk '{print $14+$15}' "/proc/$p/stat" 2>/dev/null || echo 0))); done
    t0=$(date +%s%N)
    sleep "$1"
    for p in $PIDS; do c1=$((c1 + $(awk '{print $14+$15}' "/proc/$p/stat" 2>/dev/null || echo 0))); done
    t1=$(date +%s%N)
    CPU=$(( (c1 - c0) * 1000000000 / (t1 - t0) ))  # percent of one core, 100 ticks per second
}

report() {
    local p mali=0 dri=0 sw=0 wl=0 x11=0 pss=0 names=""
    for p in $PIDS; do
        [ -r "/proc/$p/maps" ] || continue
        names="$names $(cat "/proc/$p/comm")"
        ls -l "/proc/$p/fd" 2>/dev/null | grep -q '/dev/mali0' && mali=$((mali + 1))
        grep -q '/opt/panfork/lib/dri/' "/proc/$p/maps" && dri=$((dri + 1))
        grep -qE 'libgallium|swrast_dri|/usr/lib/.*/dri/' "/proc/$p/maps" && sw=$((sw + 1))
        grep -q 'libwayland-client' "/proc/$p/maps" && wl=$((wl + 1))
        grep -q 'libxcb.so' "/proc/$p/maps" && x11=$((x11 + 1))
        pss=$((pss + $(awk '/^Pss:/{print $2}' "/proc/$p/smaps_rollup" 2>/dev/null || echo 0)))
    done
    if [ "$mali" -gt 0 ]; then r=gpu; elif [ "$dri" -gt 0 ] || [ "$sw" -gt 0 ]; then r=llvmpipe; else r=software; fi
    printf '{"id":"%s","renderer":"%s","mali_procs":%d,"panfork_procs":%d,"system_mesa_procs":%d,"wayland_procs":%d,"xcb_procs":%d,"pss_mb":%d,"cpu_pct":%d,"new_gpu_faults":%d,"xwayland":%s,"procs":"%s"}\n' \
        "$ID" "$r" "$mali" "$dri" "$sw" "$wl" "$x11" "$((pss / 1024))" "$CPU" "$(($(faults) - F0))" \
        "$(ps -C Xwayland -o pid= >/dev/null && echo true || echo false)" "$(echo $names | tr ' ' '\n' | sort -u | tr '\n' ' ')"
}

F0=$(faults)
if [ "$1" = --attach ]; then
    ID=$2; SECS=${3:-5}
    PIDS=$(ps -C "$2" -o pid= | tr -d ' ')
    [ -n "$PIDS" ] || { echo "{\"id\":\"$ID\",\"error\":\"not running\"}"; exit 1; }
    measure "$SECS"
    report
    exit 0
fi

ID=$1; SECS=$2; shift 2; [ "$1" = -- ] && shift
UNIT=probe-$ID
runuser -u user -- systemctl --user reset-failed "$UNIT" 2>/dev/null
# User manager environment: the same variables as a start from the app grid.
runuser -u user -- env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS \
    systemd-run --user --quiet --unit="$UNIT" --collect --property=MemoryMax=2800M "$@"
sleep "$SECS"
PIDS=$(pids_of_unit "$UNIT")
if [ -z "$PIDS" ]; then
    echo "{\"id\":\"$ID\",\"error\":\"exited\",\"new_gpu_faults\":$(($(faults) - F0))}"
    journalctl --user-unit "$UNIT" -M user@ --no-pager -n 8 2>/dev/null | tail -8 >&2
    exit 1
fi
measure 5
report
