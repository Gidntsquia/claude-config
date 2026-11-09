#!/usr/bin/env bash
# tests/agent-replay/scene.sh <scene>: one scene on its own fake tmux server (tests/fake-env.sh), driven by drive.py.
set -uo pipefail
RP="$(cd "$(dirname "$0")" && pwd)"
REAL_CLAUDE="$(command -v claude)"          # before fake-env puts tests/bin (the fake claude) first on PATH
source "$RP/../fake-env.sh"   # (re)defines HERE=tests/, ROOT
cd "$ROOT"
export REAL_CLAUDE REPLAY_OUT="$RP/out/$1"
rm -rf "$REPLAY_OUT"; mkdir -p "$REPLAY_OUT"
python3 -I "$RP/drive.py" "$1" 2>"$REPLAY_OUT/drive.err"
