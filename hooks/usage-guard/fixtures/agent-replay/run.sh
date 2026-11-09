#!/usr/bin/env bash
# tests/agent-replay/run.sh [-j N] [scene ...]: replays the audited misreads (plans/research/C-transcript-audit.md items
# 1–14) and the R4/R6/R7/R9/R11/R12/R14/R16 scenes against the live agent (`claude -p --agent assistant`, real Opus
# tokens) on the private fake tmux from tests/fake-env.sh. One scene = one tests/agent-replay/scenes/<name>.py (setup,
# TURNS, check). Each scene gets its own fake tmux server and scratch dir (tests/agent-replay/scene.sh), so scenes run
# -j N at a time (default 3). Replies, tool calls and the tmux state land in tests/agent-replay/out/<scene>/. Prints
# PASS <scene> or FAIL <scene>: <first reason> per scene and a total; exit 1 on any FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
J=3
if [ "${1:-}" = -j ]; then J="$2"; shift 2; fi
if [ $# -gt 0 ]; then scenes=("$@"); else
  mapfile -t scenes < <(ls "$HERE/scenes"/*.py | xargs -n1 basename | sed 's/\.py$//' | grep -v '^_')
fi
mkdir -p "$HERE/out"
printf '%s\n' "${scenes[@]}" | xargs -P "$J" -I{} bash "$HERE/scene.sh" {} > "$HERE/out/results.txt"
sort "$HERE/out/results.txt"
pass=$(grep -c '^PASS' "$HERE/out/results.txt"); total=${#scenes[@]}
echo "$pass/$total passed"
[ "$pass" = "$total" ]
