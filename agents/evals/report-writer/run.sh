#!/usr/bin/env bash
# Report-writer eval entry points. All work runs through the harness in ~/files/agent-eval-experiment/report-writer/.
#   run.sh build <fixture> [--no-checker]   build fixtures/<f> (or cases/<f>) → builds/<f>-on|off/
#   run.sh planted <fixture>                plant three errors into builds/<f>-on and run the checker alone; prints caught/missed
#   run.sh check <fixture>                  rerun check.py --prose on builds/<f>-on|off
#   run.sh phone <fixture> [on|off]         open the build's report.html in Firefox at phone width
#   run.sh golden                           check.py --prose on golden/r5/B (must PASS) and golden/r4/A (must FAIL ai_tells)
set -euo pipefail
EVAL="$HOME/files/agent-eval-experiment/report-writer"
HERE="$(cd "$(dirname "$0")" && pwd)"
GPU="$EVAL/cases/gpu"
mode="${1:-}"; shift || true
case "$mode" in
  build)   python3 "$EVAL/report_eval.py" report-writer --fixture "$@" ;;
  planted) python3 "$EVAL/report_eval.py" --planted "$1" ;;
  check)   python3 "$EVAL/report_eval.py" --check "$1" ;;
  phone)   f="$1"; s="${2:-on}"; "/mnt/c/Program Files/Mozilla Firefox/firefox.exe" -new-window "$(wslpath -w "$EVAL/builds/$f-$s/report.html")" & ;;
  golden)
    python3 -I "$HERE/check.py" "$HERE/golden/r5/B" --data "$GPU/data" --traps "$GPU/TRAPS.md" --expected "$GPU/expected.json" --mode phone --prose | tail -3
    python3 -I "$HERE/check.py" "$HERE/golden/r4/A" --data "$GPU/data" --traps "$GPU/TRAPS.md" --mode phone --prose | grep -E "ai_tells|check.py:" || true ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
