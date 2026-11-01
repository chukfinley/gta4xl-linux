#!/usr/bin/env python3
"""Copy a file to the tablet over the USB serial console: tty-push.py LOCAL REMOTE [MODE]."""
import base64
import os
import subprocess
import sys

CHUNK = 3000  # the tty line buffer holds 4095 bytes
RUN = [sys.executable, os.path.join(os.path.dirname(__file__), "tty-run.py")]


def main() -> int:
    local, remote = sys.argv[1:3]
    mode = sys.argv[3] if len(sys.argv) > 3 else "644"
    data = base64.b64encode(open(local, "rb").read()).decode()
    lines = [f"echo {data[i:i + CHUNK]} >> /run/push.b64" for i in range(0, len(data), CHUNK)]
    script = ["rm -f /run/push.b64"] + lines
    script.append(
        f"mkdir -p $(dirname {remote}) && base64 -d /run/push.b64 > {remote} && chmod {mode} {remote}"
        f" && rm /run/push.b64 && sha256sum {remote}"
    )
    env = dict(os.environ, GTA4XL_TIMEOUT=str(30 + len(lines) // 10))
    for start in range(0, len(script), 200):
        out = subprocess.run(RUN + ["\n".join(script[start:start + 200])], env=env,
                             capture_output=True, text=True)
    print(out.stdout.strip().splitlines()[-2:] if out.stdout else out.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
