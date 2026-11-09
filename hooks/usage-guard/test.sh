#!/usr/bin/env bash
# Tests for usage-guard. Offline: a temp HOME, a fake `claude` first on PATH that records any call (none is expected),
# and a temp project holding a copy of assistant-agent's tests/agent-replay scripts (fixtures/agent-replay, the files as
# they were on 2026-11-09). Ends with the replay of the real Nov 5-7 commands when those logs are on this machine.
#   bash hooks/usage-guard/test.sh            all cases
#   bash hooks/usage-guard/test.sh -v         also print each hook reply
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_HOME="$HOME"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1
export HOME="$T/home"; mkdir -p "$HOME/.claude/agents" "$T/bin"
printf '#!/bin/sh\necho "$@" >> "%s/claude-called"\nexit 99\n' "$T" > "$T/bin/claude"; chmod +x "$T/bin/claude"
export PATH="$T/bin:$PATH"
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
HOOK="$HERE/usage_guard.py"; GUARD="$HERE/guard"
S="$HOME/.cache/claude-guard"
P="$T/assistant-agent"; mkdir -p "$P/tests/agent-replay/scenes" "$P/.git"
cp "$HERE/fixtures/agent-replay/"{run.sh,scene.sh,drive.py} "$P/tests/agent-replay/"
while read -r s; do : > "$P/tests/agent-replay/scenes/$s"; done < "$HERE/fixtures/agent-replay/scenes.txt"
NSCENES=$(grep -vc '^_' "$HERE/fixtures/agent-replay/scenes.txt")
DAY=$(TZ=America/New_York date +%F)
pass=0; fail=0
ok()  { pass=$((pass + 1)); [ "$VERBOSE" = 1 ] && echo "ok    $1"; return 0; }
bad() { fail=$((fail + 1)); echo "FAIL  $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

# hook <agent_type|-> <tool> <cwd> <field=value>... [-- extra hook args]: sets RC and OUT (stdout+stderr)
hook() {
  local at="$1" tool="$2" cwd="$3"; shift 3
  local fields=() extra=()
  while [ $# -gt 0 ]; do [ "$1" = "--" ] && { shift; extra=("$@"); break; }; fields+=("$1"); shift; done
  local json
  json=$(python3 - "$at" "$tool" "$cwd" "${SESSION:-s1}" "${AGENT_ID:-}" "${EVENT:-PreToolUse}" "${fields[@]}" <<'PY'
import json, sys
at, tool, cwd, session, aid, event, *fields = sys.argv[1:]
ti = {}
for f in fields:
    k, v = f.split("=", 1)
    ti[k] = True if v == "@true" else v
d = {"hook_event_name": event, "session_id": session, "cwd": cwd, "tool_name": tool, "tool_input": ti, "tool_use_id": "toolu_%d" % abs(hash(json.dumps(ti)))}
if at != "-": d["agent_type"] = at
if aid: d["agent_id"] = aid
if event != "PreToolUse": d.pop("tool_name"); d.pop("tool_input")
print(json.dumps(d))
PY
)
  OUT=$(printf '%s' "$json" | python3 "$HOOK" --live "${LIVE:-0}" "${extra[@]}" 2>&1); RC=$?
  [ "$VERBOSE" = 1 ] && [ -n "$OUT" ] && echo "      [$RC] $OUT"
  return 0
}
bash_as() { local at="$1"; shift; hook "$at" Bash "$P" "command=$1" "${@:2}"; }
count()   { cat "$S/${1:-assistant-agent}/$DAY.count" 2>/dev/null || echo 0; }
setcount(){ mkdir -p "$S/assistant-agent"; echo "$1" > "$S/assistant-agent/$DAY.count"; }
loglines(){ [ -f "$S/log" ] && wc -l < "$S/log" || echo 0; }
allows()  { [ "$RC" = 0 ] && ok "$1" || bad "$1" "expected allow, got [$RC] $OUT"; }
blocks()  { # blocks <name> <text the one-line reason must contain>
  if [ "$RC" = 2 ] && [ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && [[ "$OUT" == "blocked by usage-guard: "* ]] && [[ "$OUT" == *"$2"* ]]; then ok "$1"
  else bad "$1" "expected a block containing '$2', got [$RC] $OUT"; fi; }
is()      { [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected '$3', got '$2'"; }
has()     { [[ "$2" == *"$3"* ]] && ok "$1" || bad "$1" "expected to find '$3' in: $2"; }

# ---- R11: commands that are not launches ---------------------------------------------------------------------------
for c in "grep -rn 'claude -p' ." "git status" "pytest -q" "claude --version" "claude -h" "claude auth status" \
         "claude agents --json" "ls ~/.claude" "cat ~/.claude/settings.json | jq .hooks" "bash tests/run.sh" \
         "git commit -m 'run claude -p with a budget'" "echo 'claude -p hi &' >> notes.md"; do
  bash_as worker "$c"; allows "not a launch: $c"
done
is "count unchanged by non-launches" "$(count)" 0
is "non-launches are not logged" "$(loglines)" 0
bash_as worker "$(printf 'cat > notes.md <<EOF\nrun claude -p "x" here, four times: claude -p a & claude -p b & claude -p c &\nEOF')"
allows "heredoc holding claude -p as data"; is "count unchanged by the heredoc" "$(count)" 0

# ---- R4 / R5 single launches ---------------------------------------------------------------------------------------
bash_as worker 'claude -p "hi" --max-budget-usd 0.5 --max-turns 10'; allows "launch with both flags"; is "count is 1" "$(count)" 1
has "ALLOW logged with the count" "$(tail -1 "$S/log")" "| assistant-agent | ALLOW | 1/30 | claude -p"
has "log time is ET" "$(tail -1 "$S/log")" " ET | "
bash_as worker 'claude -p "hi" --max-budget-usd 0.5'; blocks "no --max-turns (R4)" "lacks --max-turns. Add --max-budget-usd 0.50 --max-turns 15"
bash_as worker 'claude --print "hi" --max-turns 5'; blocks "no --max-budget-usd (R4)" "lacks --max-budget-usd"
bash_as worker '/usr/local/bin/claude --agent evaluator "."'; blocks "--agent by full path (R4)" "lacks --max-budget-usd and --max-turns"
bash_as worker 'C="$(command -v claude)"; "$C" -p hi'; blocks "claude through a variable (R4)" "lacks --max-budget-usd"
bash_as worker 'claude --bg "do it"'; blocks "--bg (R4)" "lacks"
is "blocked launches do not count" "$(count)" 1
has "BLOCK logged" "$(tail -1 "$S/log")" "| BLOCK | 1/30 | claude --bg"

# ---- R3 concurrency -------------------------------------------------------------------------------------------------
bash_as worker 'bash tests/agent-replay/run.sh -j 4'
blocks "run.sh -j 4 (R3)" "4 parallel headless claude runs (max 2). Run -j 2 or one scene; ask the user to run \`guard allow\` for a full suite."
bash_as worker 'bash tests/agent-replay/run.sh'; blocks "run.sh default -j 3 (R3)" "3 parallel headless claude runs (max 2)"
hook worker Bash "$P/tests/agent-replay" "command=./run.sh -j 6 2>&1 | tail -5"; blocks "run.sh from its own directory (R3)" "6 parallel"
bash_as worker 'for s in a b c; do claude -p "$s" --max-budget-usd 0.5 --max-turns 5 & done; wait'; blocks "for-loop with & (R3)" "3 parallel headless claude runs"
bash_as worker 'claude -p a --max-budget-usd 1 --max-turns 5 & claude -p b --max-budget-usd 1 --max-turns 5 & claude -p c --max-budget-usd 1 --max-turns 5 & wait'; blocks "& fan-out (R3)" "3 parallel"
bash_as worker 'ls scenes | xargs -P 4 -I{} claude -p {} --max-budget-usd 1 --max-turns 5'; blocks "xargs -P 4 (R3)" "4 parallel"
bash_as worker 'parallel -j 5 claude -p {} --max-budget-usd 1 --max-turns 5 ::: a b c d e'; blocks "parallel -j 5 (R3)" "5 parallel"
LIVE=2 bash_as worker 'claude -p hi --max-budget-usd 0.5 --max-turns 10'; blocks "one more with 2 already running (R3)" "3 parallel headless claude runs (max 2) (2 already running)"
hook worker Bash "$P" "command=claude -p hi --max-budget-usd 0.5 --max-turns 10" "run_in_background=@true"; allows "one background launch"
is "count is 2" "$(count)" 2
hook worker Monitor "$P" "command=bash tests/agent-replay/run.sh -j 4"; blocks "Monitor tool, same rule (R3)" "4 parallel"

# ---- scripts: flags and the daily cap -------------------------------------------------------------------------------
bash_as worker 'bash tests/agent-replay/run.sh -j 2 a01_first'; blocks "script launch without flags (R4)" "tests/agent-replay/drive.py lacks --max-budget-usd and --max-turns"
has "script reason names CLAUDE_GUARD_FLAGS" "$OUT" 'CLAUDE_GUARD_FLAGS="--max-budget-usd 0.50 --max-turns 15"'
setcount 29
bash_as worker 'bash tests/agent-replay/run.sh -j 2'
blocks "run.sh -j 2 at 29 (R5)" "29/30 headless launches used today for assistant-agent; this adds $NSCENES"
is "count stays 29" "$(count)" 29
# the same scripts once drive.py passes CLAUDE_GUARD_FLAGS through
sed -i 's|^\(\s*\)cmd = \[CLAUDE, "-p", \(.*\)$|\1cmd = [CLAUDE, "-p", *os.environ.get("CLAUDE_GUARD_FLAGS", "").split(), \2|' "$P/tests/agent-replay/drive.py"
grep -q CLAUDE_GUARD_FLAGS "$P/tests/agent-replay/drive.py" || bad "fixture patch" "drive.py not patched"
setcount 0
bash_as worker 'CLAUDE_GUARD_FLAGS="--max-budget-usd 0.5 --max-turns 15" bash tests/agent-replay/run.sh -j 2 a01_first b02_second'
allows "script launch with CLAUDE_GUARD_FLAGS, two scenes"; is "two scenes count 2" "$(count)" 2
bash_as worker 'bash tests/agent-replay/run.sh -j 2 a01_first'; blocks "patched script, variable not set (R4)" "lacks --max-budget-usd"
bash_as worker 'CLAUDE_GUARD_FLAGS="--max-budget-usd 0.5 --max-turns 15" bash tests/agent-replay/run.sh -j 2'
blocks "full suite over the cap (R5)" "2/30 headless launches used today for assistant-agent; this adds $NSCENES"
bash_as worker 'CLAUDE_GUARD_FLAGS="--max-budget-usd 0.5 --max-turns 15" bash tests/agent-replay/run.sh -j 4 a01_first b02_second c03 d04'
blocks "four named scenes at -j 4 (R3)" "4 parallel"

# ---- other agents: silent -------------------------------------------------------------------------------------------
before=$(loglines); c0=$(count)
for at in evaluator planner -; do
  SESSION="other-$at" bash_as "$at" 'bash tests/agent-replay/run.sh -j 4'; allows "agent_type $at: -j 4 allowed"
  is "agent_type $at: no output" "$OUT" ""
  SESSION="other-$at" hook "$at" Agent "$P" "description=x" "prompt=y" "subagent_type=general-purpose"; allows "agent_type $at: Agent allowed"
  is "agent_type $at: Agent input untouched" "$OUT" ""
  SESSION="other-$at" hook "$at" Edit "$P" "file_path=$HOME/.claude/settings.json"; allows "agent_type $at: settings edit allowed"
done
is "other agents write no log line" "$(loglines)" "$before"; is "other agents do not count" "$(count)" "$c0"
SESSION=other-x AGENT_ID=a1 hook general-purpose Bash "$P" "command=bash tests/agent-replay/run.sh -j 4"; allows "subagent of a non-worker session"
AGENT_ID=a1 hook general-purpose Bash "$P" "command=bash tests/agent-replay/run.sh -j 4"; blocks "subagent of the worker session (R3)" "4 parallel"

# ---- R6: guard state is the user's ----------------------------------------------------------------------------------
for c in "guard allow 2h" "cd /tmp && guard  allow until 9pm" "echo 0 > ~/.cache/claude-guard/assistant-agent/$DAY.count" \
         "rm -rf ~/.cache/claude-guard" "cat claude-guard/log" "python3 ~/.claude/hooks/usage-guard/usage_guard.py cli allow 2h" \
         "echo '{}' > ~/.claude/settings.json" "sed -i 's/usage/x/' ~/.claude/settings.json" "jq 'del(.hooks)' ~/.claude/settings.json | tee ~/.claude/settings.local.json" \
         "cp /tmp/w.md ~/.claude/agents/worker.md" "python3 -c 'open(\"x\")' >> $HOME/.claude/agents/worker.md" \
         "mv ~/.claude/settings.json ~/.claude/settings.bak" "rm -rf ~/.claude" "guard revoke"; do
  bash_as worker "$c"; blocks "R6: $c" "guard state is edited by the user only"
done
printf '#!/bin/sh\nguard allow 2h\n' > "$P/unlock.sh"
bash_as worker 'bash unlock.sh'; blocks "R6: a script that runs guard allow" "guard state is edited by the user only"
for f in "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" "$HOME/.claude/agents/worker.md" "$S/assistant-agent/allow" "$HERE/usage_guard.py" "$P/.claude/settings.local.json"; do
  hook worker Write "$P" "file_path=$f" "content=x"; blocks "R6: Write $f" "guard state is edited by the user only"
  hook worker Edit "$P" "file_path=$f"; blocks "R6: Edit $f" "guard state is edited by the user only"
done
hook worker Edit "$P" "file_path=$P/README.md"; allows "Edit of a project file"
bash_as worker 'guard status'; allows "guard status is readable"
bash_as worker 'guard log 5'; allows "guard log is readable"
bash_as worker 'guard usage today'; allows "guard usage is readable"

# ---- R6: the user's unlock -----------------------------------------------------------------------------------------
cd "$P"
out=$("$GUARD" allow 2h 2>&1); is "guard allow 2h exits 0" "$?" 0; has "guard allow prints the ET expiry" "$out" " ET"
exp=$(head -1 "$S/assistant-agent/allow"); now=$(date +%s)
[ $((exp - now)) -ge 7190 ] && [ $((exp - now)) -le 7210 ] && ok "allow file expires in 2 h" || bad "allow file expires in 2 h" "$exp vs $now"
has "allow file line 2 is ET text" "$(sed -n 2p "$S/assistant-agent/allow")" "ET"
has "guard status shows the unlock" "$("$GUARD" status)" "unlock    until"
setcount 29
bash_as worker 'CLAUDE_GUARD_FLAGS="--max-budget-usd 0.5 --max-turns 15" bash tests/agent-replay/run.sh -j 4'
allows "unlocked: -j 4 full suite"; is "unlocked suite counts its scenes" "$(count)" $((29 + NSCENES))
bash_as worker 'bash tests/agent-replay/run.sh -j 4'; blocks "unlocked: flags still required (R4)" "lacks --max-budget-usd"
"$GUARD" allow 45m >/dev/null; e=$(head -1 "$S/assistant-agent/allow"); [ $((e - $(date +%s))) -le 2705 ] && [ $((e - $(date +%s))) -ge 2690 ] && ok "guard allow 45m" || bad "guard allow 45m" "$e"
"$GUARD" allow until 9pm >/dev/null; is "guard allow until 9pm" "$(TZ=America/New_York date -d "@$(head -1 "$S/assistant-agent/allow")" +%H:%M)" "21:00"
"$GUARD" allow soon >/dev/null 2>&1; is "guard allow rejects an unreadable time" "$?" 2
"$GUARD" allow 30h >/dev/null 2>&1; is "guard allow rejects more than 24 h" "$?" 2
out=$(CLAUDECODE=1 HOME="$REAL_HOME" XDG_CACHE_HOME="$T/x" python3 -c "
import sys; sys.path.insert(0, '$HERE'); import usage_guard as ug, guard_cli
ug.G = '$T/realhome-guard'; sys.exit(guard_cli.cmd_allow(['2h'], 'assistant-agent'))" 2>&1); rc=$?
is "guard allow refuses inside a Claude session" "$rc" 1; has "and says who runs it" "$out" "run it in your own terminal"
[ ! -e "$T/realhome-guard/assistant-agent/allow" ] && ok "no allow file written by the refused call" || bad "no allow file written by the refused call"
echo "$(( $(date +%s) - 60 ))" > "$S/assistant-agent/allow"; setcount 0
bash_as worker 'CLAUDE_GUARD_FLAGS="--max-budget-usd 0.5 --max-turns 15" bash tests/agent-replay/run.sh -j 4'; blocks "expired unlock: -j 4 (R3)" "4 parallel"
"$GUARD" allow 2h >/dev/null; out=$("$GUARD" revoke); has "guard revoke" "$out" "unlock ended"
bash_as worker 'CLAUDE_GUARD_FLAGS="--max-budget-usd 0.5 --max-turns 15" bash tests/agent-replay/run.sh -j 4'; blocks "revoked unlock: -j 4 (R3)" "4 parallel"
has "guard log shows BLOCK lines" "$("$GUARD" log 3)" "| BLOCK |"
is "guard log n prints n lines" "$("$GUARD" log 4 | wc -l)" 4

# ---- R16 / R17: the Agent tool -------------------------------------------------------------------------------------
A="$T/spire"; mkdir -p "$A/.git"; AS="$S/spire"
agent() { hook "${AT:-worker}" Agent "$A" "$@"; }
count_a() { cat "$AS/$DAY.count" 2>/dev/null || echo 0; }
agent "description=Transcribe VOD aaa" "prompt=Transcribe VOD aaa into the CSV" "subagent_type=general-purpose" "model=opus"
allows "first subagent"; is "a subagent counts 1" "$(count_a)" 1
has "type rewritten to helper" "$OUT" '"subagent_type": "helper"'; has "decision is allow" "$OUT" '"permissionDecision": "allow"'
[[ "$OUT" != *'"model"'* ]] && ok "opus model dropped from the input" || bad "opus model dropped from the input" "$OUT"
has "prompt kept in updatedInput" "$OUT" '"prompt": "Transcribe VOD aaa into the CSV"'
has "log names the forced model" "$(tail -1 "$S/log")" "model=opus requested, forced sonnet"
has "log names the rewrite" "$(tail -1 "$S/log")" "subagent_type general-purpose rewritten to helper"
agent "description=Summarize file b" "prompt=Summarize b.txt" "subagent_type=helper" "model=haiku"; allows "second subagent (helper, haiku)"
is "helper + haiku passes untouched" "$OUT" ""
agent "description=Summarize file c" "prompt=Summarize c.txt" "subagent_type=helper"; allows "third subagent"
agent "description=Summarize file d" "prompt=Summarize d.txt" "subagent_type=helper"
blocks "fourth subagent while three run (R16)" "3 subagents running (max 3); wait for one to finish"
is "blocked subagent does not count" "$(count_a)" 3
# the three start; one stops; a fourth may go
for id in ag1 ag2 ag3; do EVENT=SubagentStart AGENT_ID=$id hook helper - "$A"; done
is "SubagentStart turns reservations into live files" "$(ls "$AS/live" | sort | tr '\n' ' ')" "ag1 ag2 ag3 "
agent "description=Summarize file d" "prompt=Summarize d.txt" "subagent_type=helper"; blocks "still three live (R16)" "3 subagents running"
EVENT=SubagentStop AGENT_ID=ag2 hook helper - "$A"; is "SubagentStop removes the live file" "$(ls "$AS/live" | tr '\n' ' ')" "ag1 ag3 "
agent "description=Summarize file d" "prompt=Summarize d.txt" "subagent_type=helper"; allows "fourth after one finished"
EVENT=SubagentStop AGENT_ID=ag1 hook helper - "$A"; EVENT=SubagentStop AGENT_ID=ag3 hook helper - "$A"
agent "description=  transcribe   vod AAA " "prompt=something else entirely" "subagent_type=helper"
blocks "duplicate description, case and spaces ignored (R16)" "\"Transcribe VOD aaa\" was already dispatched today at "
[[ "$OUT" =~ at\ [0-9]{1,2}:[0-9]{2}\ [AP]M\;\ reuse\ its\ output$ ]] && ok "duplicate reason gives the time and the route" || bad "duplicate reason gives the time and the route" "$OUT"
agent "description=Another name" "prompt=SUMMARIZE   b.txt" "subagent_type=helper"; blocks "duplicate prompt start (R16)" "was already dispatched today"
rm -f "$AS/live/"*; old="$AS/live/stale1"; echo s1 > "$old"; touch -d '3 hours ago' "$old"
echo s1 > "$AS/live/x1"; echo s1 > "$AS/live/x2"
agent "description=Fresh task e" "prompt=Summarize e.txt" "subagent_type=helper"; allows "a live file older than 2 h is not counted"
rm -f "$AS/live/"*; echo other > "$AS/live/o1"; echo other > "$AS/live/o2"; echo other > "$AS/live/o3"
agent "description=Fresh task f" "prompt=Summarize f.txt" "subagent_type=helper"; allows "another session's subagents are not counted"
rm -f "$AS/live/"*; echo 30 > "$AS/$DAY.count"
agent "description=Fresh task g" "prompt=Summarize g.txt" "subagent_type=helper"; blocks "31st launch of the day (R16)" "30/30 launches used today for spire; this adds 1"
(cd "$A" && "$GUARD" allow 1h >/dev/null)
for i in 1 2 3 4; do agent "description=Unlocked $i" "prompt=Unlocked task $i" "subagent_type=helper"; done; allows "unlocked: fourth concurrent and over the cap"
agent "description=Transcribe VOD aaa" "prompt=again" "subagent_type=helper"; allows "unlocked: duplicate passes"
(cd "$A" && "$GUARD" revoke >/dev/null)

# ---- R8 / R18: status line ------------------------------------------------------------------------------------------
SL="$HERE/../../statusline.sh"
if [ -f "$SL" ] && command -v jq >/dev/null; then
  mkdir -p "$HOME/.claude/hooks"; ln -sfn "$HERE" "$HOME/.claude/hooks/usage-guard"
  sl() { printf '{"workspace":{"current_dir":"%s","project_dir":"%s"},"model":{"display_name":"Sonnet"}}' "$1" "$1" | bash "$SL" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'; }
  Q="$T/quiet"; mkdir -p "$Q/.git"
  [[ "$(sl "$Q")" != *guard* ]] && ok "status line silent at count 0" || bad "status line silent at count 0" "$(sl "$Q")"
  rm -f "$S/assistant-agent/allow" "$S/assistant-agent/$DAY.fe"; setcount 7
  has "status line shows the count" "$(sl "$P")" "guard 7/30"
  [[ "$(sl "$P")" != *unlocked* ]] && ok "no unlock text without an allow file" || bad "no unlock text without an allow file"
  echo 12.4 > "$S/assistant-agent/$DAY.fe"
  has "status line shows FE after the count" "$(sl "$P")" "guard 7/30 12.4M FE"
  (cd "$P" && "$GUARD" allow until 9pm >/dev/null)
  has "status line shows the unlock" "$(sl "$P")" "unlocked→21:00"
  (cd "$P" && "$GUARD" revoke >/dev/null)
else
  echo "skip  status line cases (statusline.sh or jq missing)"
fi

# ---- R1 / R10 / R13 -------------------------------------------------------------------------------------------------
[ ! -e "$T/claude-called" ] && ok "the fake claude was never run" || bad "the fake claude was never run" "$(cat "$T/claude-called")"
grep -nE '^\s*(import|from)\s+(urllib|http|socket|requests|ssl)\b' "$HERE/usage_guard.py" "$HERE/shellscan.py" >/dev/null && bad "hook imports no network module" || ok "hook imports no network module"
t0=$(date +%s%N); for i in 1 2 3 4 5 6 7 8 9 10; do bash_as worker 'bash tests/agent-replay/run.sh -j 4'; done; t1=$(date +%s%N)
ms=$(( (t1 - t0) / 10000000 ))   # includes building the JSON with a second python3
[ "$ms" -lt 200 ] && ok "hook call under 200 ms" || bad "hook call under 200 ms" "${ms} ms"
echo "hook time: ${ms} ms per call on the run.sh chain (test harness included)"

echo "$pass passed, $fail failed"
# ---- replay of the real commands ------------------------------------------------------------------------------------
AA=$(ls -d "$REAL_HOME"/.claude/projects/*-files-assistant-agent 2>/dev/null | head -1)
if [ -n "$AA" ] && [ -d "$AA" ]; then
  [ -f "$HERE/replay_bash.py" ] && python3 "$HERE/replay_bash.py" "$AA" || fail=$((fail + 1))
else
  echo "skip  replay of the Nov 5-7 commands (no logs on this machine)"
fi
[ "$fail" = 0 ]
