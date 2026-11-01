#!/usr/bin/env bash
# Run flash-linux.sh after the current (stuck) download session is gone and a new one appears.
cd "$(dirname "$0")/.."
while lsusb | grep -q 04e8:685d; do sleep 1; done
echo "old session gone"
exec bash tools/flash-linux.sh
