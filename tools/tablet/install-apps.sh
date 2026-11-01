#!/bin/bash
# Node 22, T3 Code and the coding CLIs on the tablet.
export DEBIAN_FRONTEND=noninteractive
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
apt-get install -y -qq nodejs >/dev/null
node -v
npm i -g t3@latest @anthropic-ai/claude-code @openai/codex 2>&1 | tail -4
which t3 claude codex
t3 --version
