#!/usr/bin/python3
"""Check the akku-statistik report with a made up log."""
import importlib.machinery
import importlib.util
import pathlib

path = pathlib.Path(__file__).parent.parent / "rootfs/overlay/usr/local/bin/akku-statistik"
loader = importlib.machinery.SourceFileLoader("akku", str(path))
spec = importlib.util.spec_from_loader("akku", loader)
akku = importlib.util.module_from_spec(spec)
loader.exec_module(akku)


def row(t, s, on, p, c, st="Discharging", b="a"):
    return {"t": float(t), "s": float(s), "b": b, "on": on, "p": p, "c": c, "st": st}


T = 1_000_000.0
rows = [
    row(T, 0, 1, 1, 20, "Charging"),
    row(T + 3600, 0, 1, 1, 100, "Full"),      # 1 h real charge
    row(T + 7200, 0, 1, 0, 100),              # unplugged 1 h after full
    row(T + 7500, 0, 1, 0, 95),               # 300 s on
    row(T + 7800, 0, 0, 0, 90),               # 300 s on
    row(T + 18000, 10000, 0, 0, 88),          # 10000 s sleep, 200 s off
    row(T + 18300, 10000, 1, 0, 87),          # 300 s off
    row(T + 18600, 10000, 1, 0, 86),          # 300 s on
]
s = akku.sessions(rows)
assert len(s) == 1 and s[0]["full"] - s[0]["start"] == 3600, s
t = akku.totals(rows, s[0]["end"], rows[-1]["t"])
assert t == {"on": 900.0, "off": 500.0, "sleep": 10000.0}, t

# A span over a reboot does not count.
g = [row(T, 0, 1, 0, 50), row(T + 9000, 0, 1, 0, 40, b="b"), row(T + 9100, 0, 1, 0, 40, b="b")]
assert akku.totals(g, T, T + 9100)["on"] == 100.0

# Open charge: estimate of the time to full.
c = [row(T, 0, 1, 0, 60), row(T + 60, 0, 1, 1, 50, "Charging"), row(T + 3660, 0, 1, 1, 80, "Charging")]
out = dict(akku.report(c))["Lädt gerade"]
assert ("Voll in etwa", "40 min") in out and ("Tempo", "30 % pro Stunde") in out, out
print("ok")
