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
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SUBAGENT_MODEL   # the last one picks the model the hook sets
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
import hashlib, json, sys
at, tool, cwd, session, aid, event, *fields = sys.argv[1:]
ti = {}
for f in fields:
    k, v = f.split("=", 1)
    ti[k] = True if v == "@true" else v
d = {"hook_event_name": event, "session_id": session, "cwd": cwd, "tool_name": tool, "tool_input": ti, "tool_use_id": "toolu_" + hashlib.sha1(json.dumps(ti, sort_keys=True).encode()).hexdigest()[:16]}
if at != "-": d["agent_type"] = at
if aid: d["agent_id"] = aid
if event not in ("PreToolUse", "PostToolUse"): d.pop("tool_name"); d.pop("tool_input")
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
  if [ "$RC" = 2 ] && [ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && [[ "$OUT" == "blocked by usage-guard: "* ]] && [[ "$OUT" == *"$2"* ]] && [[ "$OUT" != *"guard allow"* ]]; then ok "$1"
  else bad "$1" "expected a block containing '$2', got [$RC] $OUT"; fi; }
is()      { [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected '$3', got '$2'"; }
ends()    { [[ "$2" == *"$3" ]] && ok "$1" || bad "$1" "expected it to end with '$3': $2"; }
note()    { is "$1" "$OUT" "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"additionalContext\": \"$2\"}}"; }   # R8: the count and nothing else
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
note "an allowed launch returns the count (R8)" "usage-guard: 1/30 used today, 29 left"
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
blocks "run.sh -j 4 (R3)" "4 parallel headless claude runs (max 2). Run: bash tests/agent-replay/run.sh -j 2"
ends "a parallel block ends with the same command at -j 2 (R6)" "$OUT" "(max 2). Run: bash tests/agent-replay/run.sh -j 2"
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
has "opus model replaced by sonnet in the input" "$OUT" '"model": "sonnet"'
has "prompt kept in updatedInput" "$OUT" '"prompt": "Transcribe VOD aaa into the CSV"'
has "log names the forced model" "$(tail -1 "$S/log")" "model=opus requested, forced sonnet"
has "log names the rewrite" "$(tail -1 "$S/log")" "subagent_type general-purpose rewritten to helper"
agent "description=Summarize file b" "prompt=Summarize b.txt" "subagent_type=helper" "model=haiku"; allows "second subagent (helper, haiku)"
note "helper + haiku: input untouched, the count returned (R8)" "usage-guard: 2/30 used today, 28 left"
agent "description=Summarize file c" "prompt=Summarize c.txt" "subagent_type=helper"; allows "third subagent"
has "helper without a model gets sonnet on the call" "$OUT" '"model": "sonnet"'
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

# ---- amendment 14 Nov: report-writer stays report-writer, on opus ---------------------------------------------------
A="$T/study"; mkdir -p "$A/.git"; AS="$S/study"
agent "description=Write the report" "prompt=. — which arm is cheaper" "subagent_type=report-writer"
allows "report-writer subagent"; is "report-writer counts 1 in the pool" "$(count_a)" 1
has "report-writer type kept" "$OUT" '"subagent_type": "report-writer"'; has "report-writer model set to opus" "$OUT" '"model": "opus"'
has "log says kept on opus" "$(tail -1 "$S/log")" "| study | ALLOW | 1/30 | Agent[report-writer] Write the report | report-writer kept on opus"
agent "description=Second report" "prompt=p2" "subagent_type=report-writer" "model=opus"; allows "report-writer asked on opus"
note "report-writer + opus: input untouched, the count returned (R8)" "usage-guard: 2/30 used today, 28 left"
agent "description=Third report" "prompt=p3" "subagent_type=report-writer" "model=sonnet"; has "report-writer asked on sonnet still gets opus" "$OUT" '"model": "opus"'
agent "description=Fourth report" "prompt=p4" "subagent_type=report-writer"; blocks "report-writer is held to 3 at once" "3 subagents running"
rm -f "$AS/live/"*
agent "description=Lookalike" "prompt=p5" "subagent_type=report-writer-2" "model=opus"
has "a lookalike type goes to helper" "$OUT" '"subagent_type": "helper"'; has "and to sonnet" "$OUT" '"model": "sonnet"'
agent "description=write the  REPORT" "prompt=again" "subagent_type=report-writer"; blocks "repeat report-writer task" "was already dispatched today"
rm -f "$AS/live/"*; echo 30 > "$AS/$DAY.count"
agent "description=Report past the cap" "prompt=p6" "subagent_type=report-writer"; blocks "report-writer past the daily cap" "30/30 launches used today for study; this adds 1"
before=$(loglines)
for at in evaluator planner -; do
  SESSION="other-$at" AT="$at" agent "description=x" "prompt=y" "subagent_type=report-writer" "model=sonnet"
  [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "agent_type $at: report-writer call untouched" || bad "agent_type $at: report-writer call untouched" "[$RC] $OUT"
done
is "non-worker report-writer calls write no log line" "$(loglines)" "$before"
A="$T/spire"; AS="$S/spire"

# ==== round 2 (plan of 15 Nov) =======================================================================================
FL='CLAUDE_GUARD_FLAGS="--max-budget-usd 0.5 --max-turns 15"'
mapfile -t SC < <(grep -v '^_' "$HERE/fixtures/agent-replay/scenes.txt" | sed 's/\.py$//')
rm -f "${S:?}/assistant-agent/allow"; rm -rf "${S:?}/assistant-agent/confirm"

# ---- R1-R4: the 8 commands of 15 Nov, in full (fixtures/nov15-commands.json) ----------------------------------------
# Each is an edit, a commit or a cat followed by a real run.sh call the 120-character log line hid. The data part
# counts 0 and runs at 30/30; the whole command counts the launches of its run.sh call.
setcount 30; before=$(loglines)
while IFS=$'\t' read -r i when want got0 got; do
  is "nov15 #$i ($when): edit/commit/cat part counts 0" "$got0" 0
  is "nov15 #$i ($when): whole command counts its run.sh launches" "$got" "$want"
done < <(python3 - "$HERE" "$P" "$NSCENES" <<'PY'
import json, sys
here, proj, nscenes = sys.argv[1:]
sys.path.insert(0, here)
import shellscan
for i, c in enumerate(json.load(open(here + "/fixtures/nov15-commands.json"))["commands"], 1):
    want = nscenes if c["launches"] == "suite" else c["launches"]
    print(i, c["time_et"], want, shellscan.analyze(c["data_part"], proj).total, shellscan.analyze(c["command"], proj).total, sep="\t")
PY
)
n=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['commands']))" "$HERE/fixtures/nov15-commands.json")
is "the fixture holds the 7 afternoon commands and the 12:02 AM cat" "$n" 8
for i in $(seq 0 $((n - 1))); do
  part=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['commands'][int(sys.argv[2])]['data_part'])" "$HERE/fixtures/nov15-commands.json" "$i")
  bash_as worker "$part"; allows "nov15 #$((i + 1)): data part runs at 30/30 (R4)"; is "nov15 #$((i + 1)): and says nothing" "$OUT" ""
done
bash_as worker "$(printf 'git add a.md && git commit -q -m "run claude -p a & claude -p b & claude -p c\n\nCo-Authored-By: x"')"
allows "a commit at 30/30 is allowed (R4)"
bash_as worker "$(printf 'git commit -m "$(cat <<'"'"'E'"'"'\nreplay: bash tests/agent-replay/run.sh -j 4, then claude -p a & claude -p b & claude -p c &\nE\n)"')"
allows "commit message from \$(cat <<E) at 30/30 (R2)"
bash_as worker "$(printf 'python3 - <<'"'"'E'"'"'\ns = """bash tests/agent-replay/run.sh -j 4"""\nt = "claude -p hi"\nopen("n.md", "w").write(s + t)\nE')"
allows "string literals in a python heredoc at 30/30 (R1)"
bash_as worker "$(printf 'cat > later.sh <<'"'"'E'"'"'\nclaude -p hi\nE\nls later.sh')"
allows "heredoc written to a file that is not run, at 30/30 (R1)"
for c in "echo 'bash tests/agent-replay/run.sh -j 4'" "printf '%s\n' 'claude -p a & claude -p b & claude -p c &'" \
         "grep -rn 'claude -p' tests/agent-replay/run.sh" "cat tests/agent-replay/run.sh"; do
  bash_as worker "$c"; allows "data command at 30/30 (R1): $c"
done
is "count stays 30 after the data commands" "$(count)" 30; is "data commands write no log line" "$(loglines)" "$before"
bash_as worker "$FL bash tests/agent-replay/run.sh -j 1 ${SC[0]}"
blocks "a real launch at 30/30 (R5 cap)" "30/30 headless launches used today for assistant-agent; this adds 1. 0 left today: use checks that start no claude"
ends "at 0 left the block ends: use checks that start no claude (R6)" "$OUT" "use checks that start no claude"
setcount 0
bash_as worker "$FL; export CLAUDE_GUARD_FLAGS; echo \"\$(bash tests/agent-replay/run.sh -j 1 ${SC[0]})\""
allows "a \$( ) that runs a launch script (R2)"; is "and it counts that launch" "$(count)" 1
bash_as worker "$(printf 'git commit -q -m "replay: a long commit message that fills the first hundred and twenty characters of the log line, as the ones of 15 Nov did" && %s bash tests/agent-replay/run.sh -j 1 %s' "$FL" "${SC[1]}")"
allows "commit && run.sh one scene"; is "counts the scene, not the commit" "$(count)" 2
has "the log line shows the part that launches" "$(tail -1 "$S/log")" " … CLAUDE_GUARD_FLAGS=\"--max-budget-usd 0.5 --max-turns 15\" bash tests/agent-replay/run.sh -j 1 ${SC[1]} | 1 launch"

# ---- R5 / R15 / env $vars -------------------------------------------------------------------------------------------
setcount 0
bash_as worker 'bash -c "claude -p hi --max-budget-usd 0.5 --max-turns 5"'; allows "bash -c \"claude -p hi\" with flags (R5)"; is "bash -c counts 1" "$(count)" 1
bash_as worker "$(printf 'cat > d.sh <<'"'"'E'"'"'\nclaude -p hi --max-budget-usd 0.5 --max-turns 5\nE\nbash d.sh')"
allows "heredoc written and run at once (R15)"; is "script written and run counts 1 (R15)" "$(count)" 2
bash_as worker "$(printf 'cat > d.sh <<'"'"'E'"'"'\nclaude -p hi\nE\nbash d.sh')"; blocks "written-and-run script without flags (R15, R4)" "lacks --max-budget-usd and --max-turns"
bash_as worker "$(printf 'cat > d.sh <<'"'"'E'"'"'\nfor s in a b c d; do claude -p $s --max-budget-usd 1 --max-turns 5 & done; wait\nE\nchmod +x d.sh; ./d.sh')"
blocks "written-and-run fan-out (R15, R3)" "parallel headless claude runs (max 2)"
bash_as worker 'REAL="$(command -v claude)"; vars="A=1 B=2"; env $vars "$REAL" -p --max-budget-usd 1 --max-turns 5 hi'
allows "env \$vars \"\$REAL\" -p with flags"; is "env \$vars \"\$REAL\" -p counts 1" "$(count)" 3
bash_as worker 'REAL="$(command -v claude)"; env $vars "$REAL" -p hi'; blocks "env \$vars \"\$REAL\" -p without flags (R4)" "lacks --max-budget-usd"

# ---- R6: a block ends with a smaller command ------------------------------------------------------------------------
setcount 27
bash_as worker "$FL bash tests/agent-replay/run.sh -j 2"
blocks "full suite with 3 left (R5 cap)" "27/30 headless launches used today for assistant-agent; this adds $NSCENES. 3 left today: Run: "
ends "a daily-cap block ends with the same script, -j 1, first 3 scenes (R6)" "$OUT" "Run: $FL bash tests/agent-replay/run.sh -j 1 ${SC[0]} ${SC[1]} ${SC[2]}"
bash_as worker "$FL bash tests/agent-replay/run.sh -j 2 ${SC[3]} ${SC[4]} ${SC[5]} ${SC[6]}"
ends "named scenes over the cap: the first 3 of those named (R6)" "$OUT" "Run: $FL bash tests/agent-replay/run.sh -j 1 ${SC[3]} ${SC[4]} ${SC[5]}"
setcount 0
bash_as worker "git commit -q -m x && $FL bash tests/agent-replay/run.sh -j 5 ${SC[0]} ${SC[1]} ${SC[2]} | tail -3"
ends "parallel block keeps flags and scenes, drops the rest of the line (R6)" "$OUT" "Run: $FL bash tests/agent-replay/run.sh -j 2 ${SC[0]} ${SC[1]} ${SC[2]}"
LIVE=1 bash_as worker "$FL bash tests/agent-replay/run.sh -j 2 ${SC[0]} ${SC[1]}"
ends "one already running: the same command at -j 1 (R6)" "$OUT" "(1 already running). Run: $FL bash tests/agent-replay/run.sh -j 1 ${SC[0]} ${SC[1]}"
LIVE=2 bash_as worker "$FL bash tests/agent-replay/run.sh -j 2 ${SC[0]} ${SC[1]}"
ends "two already running: wait, then -j 1 (R6)" "$OUT" "Wait for one to finish, then run: $FL bash tests/agent-replay/run.sh -j 1 ${SC[0]} ${SC[1]}"
is "blocks counted nothing" "$(count)" 0

# ---- R7: no `guard allow` anywhere the worker reads -----------------------------------------------------------------
WMD="$HERE/../../agents/worker.md"
grep -q "guard allow" "$WMD" && bad "worker.md does not mention guard allow (R7)" "$(grep -n 'guard allow' "$WMD")" || ok "worker.md does not mention guard allow (R7)"
grep -qi "fewer launches" "$WMD" && ok "worker.md says to redesign for fewer launches (R7)" || bad "worker.md says to redesign for fewer launches (R7)"
grep -q "what the cap stopped" "$WMD" && ok "worker.md says to note what the cap stopped (R7)" || bad "worker.md says to note what the cap stopped (R7)"
n=$(python3 - "$HERE/usage_guard.py" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
doc = ast.get_docstring(tree, clean=False)
print(sum("guard allow" in n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str) and n.value != doc))
PY
)
is "no message string in usage_guard.py says guard allow (R7)" "$n" 0
grep -q "| BLOCK |.*guard allow.*| blocked by usage-guard: [^|]*guard allow" "$S/log" && bad "no logged block reason says guard allow (R7)" || ok "no logged block reason says guard allow (R7)"

# ---- R8 / R9: the count on every allowed launch, the marks at 20 and 25 ---------------------------------------------
one="$FL bash tests/agent-replay/run.sh -j 1"
setcount 18
bash_as worker "$one ${SC[0]}"; note "19th launch: the plain count (R8)" "usage-guard: 19/30 used today, 11 left"
bash_as worker "$one ${SC[1]}"; note "the launch reaching 20 (R9)" "usage-guard: 20/30 used, 10 left today: plan the remaining checks to fit"
bash_as worker "$one ${SC[2]}"; note "21st: the plain count again, the mark is said once (R9)" "usage-guard: 21/30 used today, 9 left"
setcount 23
bash_as worker "$one ${SC[0]} ${SC[1]}"; note "a 2-launch command crossing 25 (R9)" "usage-guard: 25/30 used, 5 left today: plan the remaining checks to fit"
bash_as worker "$one ${SC[2]}"; note "26th: plain" "usage-guard: 26/30 used today, 4 left"
A="$T/marks"; mkdir -p "$A/.git"; AS="$S/marks"; mkdir -p "$AS"; echo 19 > "$AS/$DAY.count"
agent "description=Mark task" "prompt=mark p" "subagent_type=helper" "model=haiku"; note "Agent launch reaching 20 (R9)" "usage-guard: 20/30 used, 10 left today: plan the remaining checks to fit"
agent "description=Mark task 2" "prompt=mark p2" "subagent_type=general-purpose"
has "a rewritten Agent call carries the count too (R8)" "$OUT" '"additionalContext": "usage-guard: 21/30 used today, 9 left"'
has "and still its updatedInput" "$OUT" '"subagent_type": "helper"'
rm -f "${AS:?}/live/"*; A="$T/spire"; AS="$S/spire"
SESSION=other-n bash_as evaluator "$one ${SC[0]}"; is "a non-worker launch gets no count note" "$OUT" ""

# ---- R10: the line at session start ---------------------------------------------------------------------------------
setcount 19
EVENT=SessionStart hook worker - "$P"
is "SessionStart, worker (R10)" "$OUT" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "usage-guard: 19/30 launches already used today for assistant-agent, 11 left"}}'
Z="$T/zero"; mkdir -p "$Z/.git"
EVENT=SessionStart hook worker - "$Z"; has "SessionStart at 0 too (R10)" "$OUT" "usage-guard: 0/30 launches already used today for zero, 30 left"
for at in evaluator planner -; do
  SESSION="start-$at" EVENT=SessionStart hook "$at" - "$P"; [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "SessionStart, agent_type $at: silent (R10)" || bad "SessionStart, agent_type $at: silent (R10)" "[$RC] $OUT"
done

# ---- R11: a big bite of what is left is turned back once -----------------------------------------------------------
setcount 12; N0=$(date +%s)
big="$FL bash tests/agent-replay/run.sh -j 2 ${SC[*]:0:11}"
bash_as worker "$big" -- --now "$N0"
blocks "11 of 18 left: turned back (R11)" "this takes 11 of your 18 left today. Pick fewer scenes, or send the same command again to confirm."
is "the refusal counts nothing (R11)" "$(count)" 12
bash_as worker "$big" -- --now $((N0 + 660)); blocks "resent after 11 minutes: asked again (R11)" "this takes 11 of your 18 left today"
bash_as worker "$big" -- --now $((N0 + 1200)); allows "resent within 10 minutes: runs (R11)"; is "and counts its 11" "$(count)" 23
note "the confirmed run returns the count" "usage-guard: 23/30 used, 7 left today: plan the remaining checks to fit"
setcount 12
bash_as worker "$big" -- --now "$N0"
bash_as worker "$FL bash tests/agent-replay/run.sh -j 2 ${SC[*]:1:11}" -- --now $((N0 + 5)); blocks "a different big command is asked on its own (R11)" "this takes 11 of your 18 left"
setcount 12
bash_as worker "$FL bash tests/agent-replay/run.sh -j 2 ${SC[*]:0:9}"; allows "9 of 18 left is exactly half: runs (R11)"
setcount 26
bash_as worker "$FL bash tests/agent-replay/run.sh -j 2 ${SC[0]} ${SC[1]}"; allows "2 launches with 4 left: under 3, runs (R11)"
setcount 25
bash_as worker "$FL bash tests/agent-replay/run.sh -j 2 ${SC[0]} ${SC[1]} ${SC[2]}"; blocks "3 of 5 left: turned back (R11)" "this takes 3 of your 5 left today"
setcount 0
bash_as worker "$FL bash tests/agent-replay/run.sh -j 2 ${SC[*]:0:15}"; allows "15 of 30 left: runs (R11)"

# ---- "Suite counted too low": PostToolUse raises the count to the sessions the command started ----------------------
setcount 0; PJ="$HOME/.claude/projects/$(printf '%s' "$P" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$PJ"
low='claude -p "run the suite" --max-budget-usd 0.5 --max-turns 10'
bash_as worker "$low"; allows "a launch counted as 1"; is "counted 1 before it ran" "$(count)" 1
ts=$(date -u -d '+2 seconds' +%Y-%m-%dT%H:%M:%S.000Z)
for k in 1 2 3; do printf '{"type":"user","entrypoint":"sdk-cli","timestamp":"%s"}\n' "$ts" > "$PJ/sess$k.jsonl"; done
printf '{"type":"user","entrypoint":"cli","timestamp":"%s"}\n' "$ts" > "$PJ/interactive.jsonl"
printf '{"type":"user","entrypoint":"sdk-cli","timestamp":"2026-01-01T00:00:00.000Z"}\n' > "$PJ/old.jsonl"
EVENT=PostToolUse bash_as worker "$low"
is "PostToolUse raises the count to the 3 headless sessions it started" "$(count)" 3
has "and tells the worker" "$OUT" "usage-guard: that command started 3 headless sessions, 2 more than counted. 3/30 used today, 27 left"
has "RECOUNT logged" "$(tail -1 "$S/log")" "| RECOUNT | 3/30 | claude -p"
EVENT=PostToolUse bash_as worker "$low"; is "a second PostToolUse for the same call adds nothing" "$(count)$OUT" "3"
EVENT=PostToolUse bash_as worker "git status"; is "PostToolUse of a non-launch is silent" "$RC$OUT" "0"
rm -f "${PJ:?}"/*.jsonl
bash_as worker "$low"; EVENT=PostToolUse bash_as worker "$low"; is "one session started, one counted: no recount" "$(count)$OUT" "4"

# ---- guard recount (the user's) -------------------------------------------------------------------------------------
: > "$S/log"; setcount 0
bash_as worker "$one ${SC[0]} ${SC[1]}"; bash_as worker "$low"
for k in 1 2; do printf '{"type":"user","entrypoint":"sdk-cli","timestamp":"%s"}\n' "$(date -u -d '+2 seconds' +%Y-%m-%dT%H:%M:%S.000Z)" > "$PJ/r$k.jsonl"; done
EVENT=PostToolUse bash_as worker "$low"; rm -f "${PJ:?}"/*.jsonl
is "count before the recount" "$(count)" 4
setcount 17
out=$(cd "$P" && "$GUARD" recount); has "guard recount rebuilds today's count from the log" "$out" "assistant-agent: 4/30 launches today (was 17, from the log)"
is "count file after guard recount" "$(count)" 4
out=$(cd "$P" && "$GUARD" recount 9); has "guard recount 9 sets it by hand" "$out" "9/30 launches today (was 4, set by hand)"
(cd "$P" && "$GUARD" recount x >/dev/null 2>&1); is "guard recount rejects a non-number" "$?" 2
bash_as worker 'guard recount 0'; blocks "the worker may not run guard recount" "guard state is edited by the user only"
out=$(cd "$P" && CLAUDECODE=1 HOME="$REAL_HOME" XDG_CACHE_HOME="$T/x" python3 -c "
import sys; sys.path.insert(0, '$HERE'); import usage_guard as ug, guard_cli
ug.G = '$T/realhome-guard'; sys.exit(guard_cli.cmd_recount(['0'], 'assistant-agent'))" 2>&1); rc=$?
is "guard recount refuses inside a Claude session" "$rc" 1; has "and says who runs it (recount)" "$out" "run it in your own terminal"

# ---- R14: a past day's usage is saved and read back ----------------------------------------------------------------
U="$T/usageproj"; mkdir -p "$U/.git"; UJ="$HOME/.claude/projects/$(printf '%s' "$U" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$UJ"
printf '{"type":"assistant","timestamp":"2026-10-01T15:00:00.000Z","sessionId":"u1","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' > "$UJ/u1.jsonl"
first=$(cd "$U" && "$GUARD" usage 2026-10-01 2>&1); rc=$?
is "guard usage of a past day exits 0" "$rc" 0
[ -f "$S/usageproj/2026-10-01.usage.json" ] && ok "a past day is saved as <project>/<date>.usage.json (R14)" || bad "a past day is saved as <project>/<date>.usage.json (R14)" "$first"
: > "$UJ/u1.jsonl"
second=$(cd "$U" && "$GUARD" usage 2026-10-01 2>&1)
is "the second call answers from the save, logs emptied (R14)" "$second" "$first"
(cd "$U" && "$GUARD" usage today >/dev/null 2>&1); [ ! -f "$S/usageproj/today.usage.json" ] && [ ! -f "$S/usageproj/$DAY.usage.json" ] && ok "today is never saved (R14)" || bad "today is never saved (R14)"

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
