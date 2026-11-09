#!/usr/bin/env bash
# demo2.sh: live demo of the subagent limits, cheap. A toy plan tells the worker to start 6 Opus subagents at once,
# one per text file, then to start the first one again. The worker runs on Sonnet (at most $1 and 12 turns) with the
# environment run-agent gives every worker, except that subagents are forced to Haiku for this demo.
# Prints a short transcript, each subagent's model, the guard's log lines and `guard usage today`.
# usage: bash demo2.sh [dir]     (dir defaults to a new temp dir; it is left in place so you can read it)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL="$(command -v claude)" || { echo "claude not on PATH" >&2; exit 1; }
D="${1:-$(mktemp -d "${TMPDIR:-/tmp}/guard-demo2.XXXXXX")}"; T="$D/toy-fanout"
mkdir -p "$T/plans" "$T/texts"
i=0; for w in apple birch cedar delta ember frost; do i=$((i + 1)); echo "$w is the first word of file $i." > "$T/texts/f$i.txt"; done
cat > "$T/plans/PLAN.md" <<'F'
# Toy fan-out
Ask: in ONE message start 6 subagents with the Agent tool (subagent_type `general-purpose`, model `opus`), one per
file `texts/f1.txt` … `texts/f6.txt`. Description: `First word of fN.txt`. Prompt: `Read texts/fN.txt and reply with
its first word only.` If some are refused, wait for the running ones and start the refused ones afterwards. When all
six words are known, start the f1 subagent once more with the same description and prompt as a double-check, then
write the six words on one line to `WORDS.txt`.
Acceptance: `WORDS.txt` holds `apple birch cedar delta ember frost`.
Do nothing else: no commits, no notes file, no report, and do not read the files yourself.
F
echo "Toy repo for the guard demo: six one-line files in texts/." > "$T/AGENTS.md"
( cd "$T" && git init -q && git add . && git -c user.name=demo -c user.email=demo@example.invalid commit -qm toy )
cd "$T" && env CLAUDE_CODE_SUBAGENT_MODEL=haiku CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3 \
  CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 "$REAL" -p --agent worker --model sonnet --max-budget-usd 1 --max-turns 12 \
  --output-format stream-json --verbose "Build what plans/PLAN.md specifies." > "$D/stream.jsonl" 2> "$D/stderr.txt"
echo "== transcript ($D/stream.jsonl) =="; python3 "$HERE/show.py" "$D/stream.jsonl"
echo "== WORDS.txt =="; cat "$T/WORDS.txt" 2>/dev/null
echo "== subagent models =="
sid=$(sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' "$D/stream.jsonl" | head -1)
for f in "$HOME"/.claude/projects/*/"$sid"/subagents/agent-*.jsonl; do
  [ -f "$f" ] || continue
  printf '%s  %s\n' "$(grep -o '"model":"[^"]*"' "$f" | sort | uniq -c | sort -rn | head -1 | sed 's/.*"model":"//; s/"//')" \
    "$(sed -n 's/.*"description":"\([^"]*\)".*/\1/p' "${f%.jsonl}.meta.json")"
done
echo "== guard log =="; guard log 20 | grep -F "toy-fanout"
echo "== guard usage today =="; ( cd "$T" && guard usage today )
