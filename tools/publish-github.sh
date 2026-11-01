#!/usr/bin/env bash
# Create the GitHub repository and push: publish-github.sh NAME [--public]. Default is private.
# The repository contains no Samsung firmware, the build takes it from the owner's device.
set -euo pipefail
NAME="${1:?usage: publish-github.sh NAME [--public]}"
VIS=--private
[ "${2:-}" = "--public" ] && VIS=--public
if git ls-files | grep -qE '\.(img|bin|hcf|fw)$'; then
  echo "binary firmware or image files are tracked, stop" >&2
  exit 1
fi
gh repo create "$NAME" "$VIS" --source=. --remote=origin --push
