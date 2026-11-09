#!/usr/bin/env bash
# demo1.sh: live demo of the parallel-run block, cheap. Builds a toy repo whose plan says to run a 4-way parallel
# `claude -p` suite, where every inner `claude` is a fake (the suite puts its own bin/ first on PATH). The one real
# session is the worker: Sonnet, at most $1 and 10 turns. Prints a short transcript, then the guard's log lines.
# usage: bash demo1.sh [dir]     (dir defaults to a new temp dir; it is left in place so you can read it)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL="$(command -v claude)" || { echo "claude not on PATH" >&2; exit 1; }
D="${1:-$(mktemp -d "${TMPDIR:-/tmp}/guard-demo1.XXXXXX")}"; T="$D/toy-suite"
mkdir -p "$T/bin" "$T/plans" "$T/scenes"
cat > "$T/bin/claude" <<'F'
#!/usr/bin/env bash
# fake claude: no model call. Says which scene it was given.
sleep 1; echo "FAKE claude ok: ${*: -1}"
F
chmod +x "$T/bin/claude"
for s in a01 a02 a03 a04; do echo "say $s" > "$T/scenes/$s.txt"; done
cat > "$T/run.sh" <<'F'
#!/usr/bin/env bash
# run.sh [-j N] [scene ...]: run each scene through a headless claude, N at a time (default 1). All scenes if none named.
cd "$(dirname "$0")"; export PATH="$PWD/bin:$PATH"
J=1; [ "${1:-}" = -j ] && { J="$2"; shift 2; }
[ $# -gt 0 ] || set -- $(ls scenes | sed 's/\.txt$//')
printf '%s\n' "$@" | xargs -P "$J" -I{} claude -p --max-budget-usd 0.50 --max-turns 15 "scene {}" | tee out.log
echo "$(grep -c 'FAKE claude ok' out.log) passed"
F
cat > "$T/plans/PLAN.md" <<'F'
# Toy suite
Ask: run the whole scene suite 4 at a time with `bash run.sh -j 4` and write its last line (`N passed`) to `RESULT.txt`.
Acceptance: `RESULT.txt` holds `4 passed`.
Do nothing else: no commits, no notes file, no report.
F
echo "Toy repo for the guard demo. Suite: \`bash run.sh [-j N] [scene ...]\`." > "$T/AGENTS.md"
( cd "$T" && git init -q && git add . && git -c user.name=demo -c user.email=demo@example.invalid commit -qm toy )
cd "$T" && "$REAL" -p --agent worker --model sonnet --max-budget-usd 1 --max-turns 10 --output-format stream-json --verbose \
  "Build what plans/PLAN.md specifies." > "$D/stream.jsonl" 2> "$D/stderr.txt"
echo "== transcript ($D/stream.jsonl) =="; python3 "$HERE/show.py" "$D/stream.jsonl"
echo "== RESULT.txt =="; cat "$T/RESULT.txt" 2>/dev/null
echo "== guard log =="; guard log 12 | grep -F "toy-suite"
