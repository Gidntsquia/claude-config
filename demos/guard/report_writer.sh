#!/usr/bin/env bash
# report_writer.sh: live check of the 14 Nov amendment. A Sonnet worker under run-agent's worker env starts two
# subagents: `report-writer` (must stay report-writer and run on Opus) and `general-purpose` with model opus (must
# become helper on Sonnet). The toy repo carries its own tiny `report-writer` (model: opus, answers one word), so the
# check costs cents and not a real report. Prints the transcript, each subagent's type and real model, the guard log.
# usage: bash report_writer.sh [dir]     (dir defaults to a new temp dir; it is left in place so you can read it)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL="$(command -v claude)" || { echo "claude not on PATH" >&2; exit 1; }
D="${1:-$(mktemp -d "${TMPDIR:-/tmp}/guard-rw.XXXXXX")}"; T="$D/toy-report"
mkdir -p "$T/plans" "$T/.claude/agents"
line=$("$HOME/.claude/skills/run-agent/scripts/run-agent.sh" --next worker "." | grep '^Without run-agent:')
vars=$(printf '%s\n' "$line" | grep -o 'CLAUDE_CODE_[A-Z_]*=[a-z0-9]*' | tr '\n' ' ')
echo "run-agent's worker line: $line"
cat > "$T/plans/PLAN.md" <<'F'
# Toy report-writer check
Ask: 1. Start ONE subagent with the Agent tool: `subagent_type: "report-writer"`, description `Write one word`,
prompt `Reply with the word ok.` 2. When it has answered, start ONE more: `subagent_type: "general-purpose"`,
`model: "opus"`, description `Say yes`, prompt `Reply with the word yes.` 3. Write both answers to `ANSWER.txt`.
Acceptance: `ANSWER.txt` exists.
Do nothing else: no commits, no notes file, no report, no skills.
F
printf -- '---\nname: report-writer\ndescription: Toy stand-in for the report-writer, for the guard check.\nmodel: opus\neffort: low\ntools: Read\n---\nAnswer in one word, exactly as asked. Use no tools.\n' > "$T/.claude/agents/report-writer.md"
echo "Toy repo for the guard report-writer check." > "$T/AGENTS.md"
( cd "$T" && git init -q && git add . && git -c user.name=demo -c user.email=demo@example.invalid commit -qm toy )
# shellcheck disable=SC2086
cd "$T" && env $vars "$REAL" -p --agent worker --model sonnet --max-budget-usd 0.60 --max-turns 8 \
  --output-format stream-json --verbose "Build what plans/PLAN.md specifies." > "$D/stream.jsonl" 2> "$D/stderr.txt"
echo "== transcript ($D/stream.jsonl) =="; python3 "$HERE/show.py" "$D/stream.jsonl"
echo "== subagents: model that answered, meta =="
sid=$(sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' "$D/stream.jsonl" | head -1)
for f in "$HOME"/.claude/projects/*/"$sid"/subagents/agent-*.jsonl; do
  [ -f "$f" ] || continue
  python3 -c '
import json, sys
print(sorted({(json.loads(l).get("message") or {}).get("model") for l in open(sys.argv[1]) if l.strip()} - {None}))' "$f"
  cat "${f%.jsonl}.meta.json"; echo
done
echo "== cost =="; grep -o '"total_cost_usd":[0-9.]*' "$D/stream.jsonl" | tail -1
echo "== guard log =="; guard log 12 | grep -F "toy-report"
