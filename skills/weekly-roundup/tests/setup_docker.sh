#!/usr/bin/env bash
# Install Docker Engine (docker.io) via apt if missing, start it, add the user to the docker group.
set -euo pipefail
# root helper: passwordless sudo if available, else WSL's `wsl.exe -u root` (no password on this box)
if [ "$(id -u)" = 0 ]; then R() { "$@"; }
elif sudo -n true 2>/dev/null; then R() { sudo "$@"; }
else R() { wsl.exe -u root -- "$@"; }; fi
if ! command -v docker >/dev/null 2>&1; then
  R apt-get update
  R apt-get install -y docker.io
fi
if ! docker info >/dev/null 2>&1 && ! R docker info >/dev/null 2>&1; then
  R service docker start || R systemctl start docker
  for _ in $(seq 1 20); do R docker info >/dev/null 2>&1 && break; sleep 1; done
fi
id -nG "$USER" | tr ' ' '\n' | grep -qx docker || R usermod -aG docker "$USER"
D="docker"; docker info >/dev/null 2>&1 || D="R docker"   # group not active in this shell yet
$D run --rm hello-world | grep -q "Hello from Docker" && echo "docker OK ($D)"
