#!/usr/bin/env bash
# r15.sh: checks the worker environment run-agent sets. Takes the env prefix from the line run-agent prints for a
# worker ("Without run-agent: CLAUDE_CODE_SUBAGENT_MODEL=sonnet ... claude --agent worker"), starts one Sonnet worker
# under it (at most $0.50 and 8 turns) whose toy plan says: print the env, then start one subagent with model opus.
# Prints the transcript, the subagent's real model and the guard's log lines.
# usage: bash r15.sh [dir]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL="$(command -v claude)" || { echo "claude not on PATH" >&2; exit 1; }
D="${1:-$(mktemp -d "${TMPDIR:-/tmp}/guard-r15.XXXXXX")}"; T="$D/toy-env"
mkdir -p "$T/plans"
line=$("$HOME/.claude/skills/run-agent/scripts/run-agent.sh" --next worker "." | grep '^Without run-agent:')
vars=$(printf '%s\n' "$line" | grep -o 'CLAUDE_CODE_[A-Z_]*=[a-z0-9]*' | tr '\n' ' ')
echo "run-agent's worker line: $line"
cat > "$T/plans/PLAN.md" <<'F'
# Toy env check
Ask: 1. run `env | grep CLAUDE_CODE_ | sort > ENV.txt; cat ENV.txt` with Bash. 2. Start ONE subagent with the Agent
tool, passing `model: "opus"` and `subagent_type: "general-purpose"`, description `Say ok`, prompt
`Reply with the word ok.` 3. When it has answered, write its answer to `ANSWER.txt`.
Acceptance: `ENV.txt` and `ANSWER.txt` exist.
Do nothing else: no commits, no notes file, no report.
F
echo "Toy repo for the guard env check." > "$T/AGENTS.md"
( cd "$T" && git init -q && git add . && git -c user.name=demo -c user.email=demo@example.invalid commit -qm toy )
# shellcheck disable=SC2086
cd "$T" && env $vars "$REAL" -p --agent worker --model sonnet --max-budget-usd 0.50 --max-turns 8 \
  --output-format stream-json --verbose "Build what plans/PLAN.md specifies." > "$D/stream.jsonl" 2> "$D/stderr.txt"
echo "== transcript ($D/stream.jsonl) =="; python3 "$HERE/show.py" "$D/stream.jsonl"
echo "== ENV.txt =="; cat "$T/ENV.txt" 2>/dev/null
echo "== subagent model =="
sid=$(sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' "$D/stream.jsonl" | head -1)
for f in "$HOME"/.claude/projects/*/"$sid"/subagents/agent-*.jsonl; do
  [ -f "$f" ] || continue
  printf '%s  %s\n' "$(grep -o '"model":"[^"]*"' "$f" | sort | uniq -c | sort -rn | head -1 | sed 's/.*"model":"//; s/"//')" "$(cat "${f%.jsonl}.meta.json")"
done
echo "== guard log =="; guard log 12 | grep -F "toy-env"
