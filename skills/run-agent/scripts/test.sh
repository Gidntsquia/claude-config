#!/usr/bin/env bash
# test.sh: self-test for run-agent.sh. Runs the script with TMUX unset from a temp git repo (printed command +
# exit codes), the --parse suite (every argument string from the 2026-10-22 log review, time strings, typos;
# exact JSON output with a frozen clock and a fake usage API), then inside a private tmux server
# (`tmux -L run-agent-test-$$`, fake `claude` on PATH, RUN_AGENT_HOME in the temp dir) the respawn and the
# scheduling suite (fire into the pane, --jobs, --cancel, until skipping, --handoff, pane-gone, server-gone, --revive).
# Never touches your tmux or ~/.claude/run-agent. Prints "N passed, M failed"; exit 1 on any failure.
set -uo pipefail

S="$(cd "$(dirname "$0")" && pwd)/run-agent.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; }

T=$(mktemp -d); T=$(cd "$T" && pwd -P)
SOCK="run-agent-test-$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null; for s in "$T/split.sock" "$T/group.sock"; do [ -S "$s" ] && tmux -S "$s" kill-server 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT

# Layout: $T/repo (git repo, cwd for the tests) with repo/sub; siblings $T/sibling and "$T/my project".
mkdir -p "$T/repo/sub" "$T/sibling" "$T/my project" "$T/bin"
git -C "$T/repo" init -q
cd "$T/repo/sub"

# check <label> <want-rc> <want-output-line> <args...>: runs S with TMUX unset, compares rc and last line.
check() {
  local label="$1" want_rc="$2" want="$3"; shift 3
  local out rc
  out=$(env -u TMUX -u TMUX_PANE "$S" "$@" 2>&1); rc=$?
  if [ "$rc" != "$want_rc" ]; then bad "$label" "rc $rc, want $want_rc; output: $out"
  elif [ "$(printf '%s\n' "$out" | tail -n 1)" != "$want" ]; then bad "$label" "got:  $(printf '%s\n' "$out" | tail -n 1)
     want: $want"
  else ok "$label"
  fi
}

# (a) existing dir, absolute and relative
check "a: existing absolute dir" 1 \
  "cd '$T/sibling' && claude --agent planner \"x\" --name \"planner: sibling\"" planner x --cwd "$T/sibling"
check "a: existing relative dir with /, -C" 1 \
  "cd '$T/sibling' && claude --agent worker \".\" --name \"worker: sibling\"" worker -C ../../sibling
check "a: dir with a space, --cwd= form, model" 1 \
  "cd '$T/my project' && claude --agent worker \"go\" --model opus --name \"worker: my project (opus)\"" \
  worker go "--cwd=$T/my project" -- --model opus
check "a: ~ expands to \$HOME" 1 \
  "cd '$HOME' && claude --agent worker \".\" --name \"worker: $(basename "$HOME")\"" worker --cwd '~'
# (b) bare name: sibling of the git root, then a name under the cwd wins over the sibling
check "b: bare name = sibling of the git root" 1 \
  "cd '$T/sibling' && claude --agent worker \".\" --name \"worker: sibling\"" worker --cwd sibling
mkdir -p "$T/repo/sub/sibling"
check "b: bare name under the cwd wins" 1 \
  "cd '$T/repo/sub/sibling' && claude --agent worker \".\" --name \"worker: sibling\"" worker --cwd sibling
rmdir "$T/repo/sub/sibling"
check "b: bare name found nowhere" 2 \
  "no such directory: nope-xyz (looked in $T/repo/sub, $T)" worker --cwd nope-xyz
# (c) missing dir / a file
check "c: missing absolute dir -> exit 2" 2 "no such directory: $T/missing" worker --cwd "$T/missing"
check "c: missing ~ dir -> exit 2" 2 "no such directory: $HOME/no-such-run-agent-dir-$$" worker --cwd "~/no-such-run-agent-dir-$$"
touch "$T/afile"
check "c: a file -> not a directory" 2 "not a directory: $T/afile" worker --cwd "$T/afile"
[ ! -e "$T/missing" ] && [ ! -e "$HOME/no-such-run-agent-dir-$$" ] && ok "c: nothing created" || bad "c: nothing created"
# (d) no dir: unchanged behaviour
check "d: no dir, name from git root" 1 "claude --agent worker \".\" --name \"worker: repo\"" worker
check "d: no dir, model" 1 "claude --agent planner \"x\" --model opus --name \"planner: repo (opus)\"" planner x -- --model opus
check "d: planner without a prompt -> no prompt argument" 1 "claude --agent planner --name \"planner: repo\"" planner
check "d: planner without a prompt, with a dir" 1 \
  "cd '$T/sibling' && claude --agent planner --name \"planner: sibling\"" planner --cwd "$T/sibling"
LAST_USAGE="                         bare name found nowhere, or a path that is a file); creates nothing"
check "d: extra word -> usage" 2 "$LAST_USAGE" worker . extra
# (e) --name given
check "e: --name wins over the dir name" 1 \
  "cd '$T/sibling' && claude --agent worker \"x\" --name \"mine\"" worker x --cwd "$T/sibling" -- --name mine
check "two dirs -> usage" 2 "$LAST_USAGE" worker --cwd a -C b
# --resolve
out=$("$S" --resolve "$T/repo/./sub/../sub/" 2>&1)
[ "$out" = "$T/repo/sub	exists" ] && ok "resolve: . and .. collapsed" || bad "resolve: . and .. collapsed" "$out"
out=$("$S" --resolve "~/no-such-run-agent-dir-$$" 2>&1)
[ "$out" = "$HOME/no-such-run-agent-dir-$$	missing" ] && ok "resolve: missing path" || bad "resolve: missing path" "$out"


# ---------------------------------------------------------------- --parse suite
# Frozen clock: 2026-10-22 18:00 ET; fake usage API with the window resetting at 8:20 PM ET.
export RUN_AGENT_TZ=America/New_York
export RUN_AGENT_NOW=$(TZ=America/New_York date -d '2026-10-22 18:00' +%s)
export RUN_AGENT_USAGE_FILE="$T/usage.json"
printf '{"five_hour":{"utilization":29.0,"resets_at":"2026-10-23T00:20:00.251269+00:00"}}' > "$T/usage.json"
export RUN_AGENT_HOME="$T/home"
# pcheck <label> <raw> <json overrides>: exact --parse output = the base object + overrides.
pcheck() {
  local label="$1" raw="$2" over="$3" got diff
  got=$("$S" --parse "$raw" 2>&1)
  diff=$(printf '%s' "$got" | python3 -c '
import json, sys
base = {"agent":"worker","agent_ok":True,"prompt":".","dir":"","dir_state":"","flags":"","force":0,"at":"","at_text":"",
        "at_shown":"","until":"","until_shown":"","reset":"","reset_shown":"","corrections":[],"unsure":[],"dry":0,
        "dir_typed":"","command":"claude --agent worker \".\" --name \"worker: repo\"","run":"S worker ."}
try:
    got = json.load(sys.stdin)
except Exception as e:
    print("not JSON: " + str(e)); sys.exit(0)
want = dict(base); want.update(json.loads(sys.argv[1]))
if got != want:
    for k in sorted(set(got) | set(want)):
        if got.get(k) != want.get(k):
            print("%s: got %r want %r" % (k, got.get(k), want.get(k)))
' "$over")
  if [ -z "$diff" ]; then ok "parse: $label"; else bad "parse: $label" "$diff"; fi
}
FL='"flags":"--model fable --effort medium","command":"claude --agent worker \".\" --model fable --effort medium --name \"worker: repo (fable)\"","run":"S worker . -- --model fable --effort medium"'
FLOW='"flags":"--model fable --effort low","command":"claude --agent worker \".\" --model fable --effort low --name \"worker: repo (fable)\"","run":"S worker . -- --model fable --effort low"'
RESET='"reset":1792714800,"reset_shown":"8:20 PM ET"'
# logged strings (Facts)
pcheck "log: key=value, spaced =, commas, force" 'worker, model=fable effort = medium, force' "{$FL,\"force\":1}"
pcheck "log: effort =medium" 'worker model=fable effort =medium' "{$FL}"
pcheck "log: em dashes" 'worker —model fable —effort low' "{$FLOW}"
pcheck "log: single dashes" 'worker -model fable -effort low' "{$FLOW}"
pcheck "log: bare model + '<effort> effort'" 'worker fable low effort' "{$FLOW}"
pcheck "log: model+effort" 'worker, opus+medium effort' '{"flags":"--model opus --effort medium","command":"claude --agent worker \".\" --model opus --effort medium --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --effort medium"}'
pcheck "log: commas everywhere, force" 'worker, model=fable, effort=medium, force' "{$FL,\"force\":1}"
pcheck "log: force before em-dash flags" 'worker force —model fable —effort medium' "{$FL,\"force\":1}"
pcheck "log: curly quotes, force" 'evaluator “I’m on my phone” force' '{"agent":"evaluator","prompt":"I’m on my phone","force":1,"command":"claude --agent evaluator \"I’m on my phone\" --name \"evaluator: repo\"","run":"S evaluator '"'"'I’m on my phone'"'"'"}'
pcheck "log: claude --agent evaluator \".\"" 'claude --agent evaluator "."' '{"agent":"evaluator","command":"claude --agent evaluator \".\" --name \"evaluator: repo\"","run":"S evaluator ."}'
pcheck "log: newline inside the prompt" 'planner "line one
line two" --model opus' '{"agent":"planner","prompt":"line one\nline two","flags":"--model opus","command":"claude --agent planner \"line one\nline two\" --model opus --name \"planner: repo (opus)\"","run":"S planner '"'"'line one\nline two'"'"' -- --model opus"}'
AT9_FLOW='"at":1792717200,"at_text":"at 9pm","at_shown":"9:00 PM ET (at 9pm, in 3h 0m)","run":"S worker . --at 1792717200 --at-text '"'"'at 9pm'"'"' -- --model fable --effort low"'
# every /run-agent argument string from the session transcripts (~/.claude/projects/*/*.jsonl); the first five
# are the ones Haiku got wrong (usage error, dropped effort, "could not parse")
EVP='"agent":"evaluator","prompt":"I’m on my phone","command":"claude --agent evaluator \"I’m on my phone\" --name \"evaluator: repo\"","run":"S evaluator '"'"'I’m on my phone'"'"'"'
pcheck "sessions: haiku usage error on 'model=fable effort =medium'" 'worker model=fable effort =medium' "{$FL}"
pcheck "sessions: haiku usage error on em-dash flags" 'worker —model fable —effort low' "{$FLOW}"
pcheck "sessions: haiku 'not run' on single-dash flags" 'worker -model fable -effort low' "{$FLOW}"
pcheck "sessions: haiku dropped 'low effort'" 'worker fable low effort' "{$FLOW}"
pcheck "sessions: haiku 'could not parse' bare model + em-dash effort" 'worker fable —effort low' "{$FLOW}"
pcheck "sessions: haiku dry run" 'worker fable low effort at 9pm dry' "{\"flags\":\"--model fable --effort low\",\"command\":\"claude --agent worker \\\".\\\" --model fable --effort low --name \\\"worker: repo (fable)\\\"\",\"dry\":1,$AT9_FLOW,$RESET}"
pcheck "sessions: full claude command with em-dash flags" 'claude --agent worker "." —model fable —effort medium' "{$FL}"
pcheck "sessions: full claude command, capital Force" 'claude --agent evaluator "." Force' '{"agent":"evaluator","force":1,"command":"claude --agent evaluator \".\" --name \"evaluator: repo\"","run":"S evaluator ."}'
pcheck "sessions: full claude command, trailing dot" 'claude --agent evaluator ".".' '{"agent":"evaluator","command":"claude --agent evaluator \".\" --name \"evaluator: repo\"","run":"S evaluator ."}'
pcheck "sessions: straight open quote, curly close" 'claude --agent evaluator "I’m on my phone”' "{$EVP}"
pcheck "sessions: planner prompt, straight open, curly close" 'claude --agent planner "Replan based on plans/EVAL.md”' '{"agent":"planner","prompt":"Replan based on plans/EVAL.md","command":"claude --agent planner \"Replan based on plans/EVAL.md\" --name \"planner: repo\"","run":"S planner '"'"'Replan based on plans/EVAL.md'"'"'"}'
pcheck "sessions: force before the curly prompt" 'evaluator force “I’m on my phone”' "{$EVP,\"force\":1}"
pcheck "sessions: force after the curly prompt" 'evaluator “I’m on my phone” force' "{$EVP,\"force\":1}"
pcheck "sessions: newline inside a curly prompt" 'evaluator “I’m on my
Phone”' '{"agent":"evaluator","prompt":"I’m on my\nPhone","command":"claude --agent evaluator \"I’m on my\nPhone\" --name \"evaluator: repo\"","run":"S evaluator '"'"'I’m on my\nPhone'"'"'"}'
pcheck "sessions: 'model fable, effort medium' words" 'worker, model fable, effort medium, force' "{$FL,\"force\":1}"
pcheck "sessions: model=opus, effort=medium" 'worker model=opus, effort=medium' '{"flags":"--model opus --effort medium","command":"claude --agent worker \".\" --model opus --effort medium --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --effort medium"}'
pcheck "sessions: 'using opus'" 'worker "." using opus' '{"flags":"--model opus","command":"claude --agent worker \".\" --model opus --name \"worker: repo (opus)\"","run":"S worker . -- --model opus"}'
pcheck "sessions: flag before the agent" '--model opus worker "."' '{"flags":"--model opus","command":"claude --agent worker \".\" --model opus --name \"worker: repo (opus)\"","run":"S worker . -- --model opus"}'
pcheck "sessions: stray words -> unsure" 'worker . extra words' '{"unsure":["extra","words"]}'
pcheck "sessions: yolo force" 'worker yolo force' '{"flags":"--dangerously-skip-permissions","force":1,"command":"claude --agent worker \".\" --dangerously-skip-permissions --name \"worker: repo\"","run":"S worker . -- --dangerously-skip-permissions"}'
pcheck "sessions: bare agent 'planner' (no default prompt)" 'planner' '{"agent":"planner","prompt":"","command":"claude --agent planner --name \"planner: repo\"","run":"S planner"}'
# time strings (12+)
AT9='"at":1792717200,"at_text":"at 9pm","at_shown":"9:00 PM ET (at 9pm, in 3h 0m)","run":"S worker . --at 1792717200 --at-text '"'"'at 9pm'"'"'"'
pcheck "time: at 9pm" 'worker at 9pm' "{$AT9,$RESET}"
pcheck "time: --at 9pm" 'worker --at 9pm' "{$AT9,$RESET}"
pcheck "time: at 9:30pm" 'worker at 9:30pm' "{\"at\":1792719000,\"at_text\":\"at 9:30pm\",\"at_shown\":\"9:30 PM ET (at 9:30pm, in 3h 30m)\",\"run\":\"S worker . --at 1792719000 --at-text 'at 9:30pm'\",$RESET}"
pcheck "time: at 21:40" 'worker at 21:40' "{\"at\":1792719600,\"at_text\":\"at 21:40\",\"at_shown\":\"9:40 PM ET (at 21:40, in 3h 40m)\",\"run\":\"S worker . --at 1792719600 --at-text 'at 21:40'\",$RESET}"
pcheck "time: at 2140" 'worker at 2140' "{\"at\":1792719600,\"at_text\":\"at 2140\",\"at_shown\":\"9:40 PM ET (at 2140, in 3h 40m)\",\"run\":\"S worker . --at 1792719600 --at-text 'at 2140'\",$RESET}"
pcheck "time: at 9 (bare hour, next occurrence = 9 PM)" 'worker at 9' "{\"at\":1792717200,\"at_text\":\"at 9\",\"at_shown\":\"9:00 PM ET (at 9, in 3h 0m)\",\"run\":\"S worker . --at 1792717200 --at-text 'at 9'\",$RESET}"
pcheck "time: at 5 (bare hour, 5 PM passed -> 5 AM)" 'worker at 5' "{\"at\":1792746000,\"at_text\":\"at 5\",\"at_shown\":\"5:00 AM ET (at 5, in 11h 0m)\",\"run\":\"S worker . --at 1792746000 --at-text 'at 5'\",$RESET}"
pcheck "time: at 5 pm (passed -> tomorrow)" 'worker at 5 pm' "{\"at\":1792789200,\"at_text\":\"at 5 pm\",\"at_shown\":\"5:00 PM ET (at 5 pm, in 23h 0m)\",\"run\":\"S worker . --at 1792789200 --at-text 'at 5 pm'\",$RESET}"
pcheck "time: in 2h" 'worker in 2h' "{\"at\":1792713600,\"at_text\":\"in 2h\",\"at_shown\":\"8:00 PM ET (in 2h, in 2h 0m)\",\"run\":\"S worker . --at 1792713600 --at-text 'in 2h'\",$RESET}"
pcheck "time: --in 2h" 'worker --in 2h' "{\"at\":1792713600,\"at_text\":\"in 2h\",\"at_shown\":\"8:00 PM ET (in 2h, in 2h 0m)\",\"run\":\"S worker . --at 1792713600 --at-text 'in 2h'\",$RESET}"
pcheck "time: in 90m" 'worker in 90m' "{\"at\":1792711800,\"at_text\":\"in 90m\",\"at_shown\":\"7:30 PM ET (in 90m, in 1h 30m)\",\"run\":\"S worker . --at 1792711800 --at-text 'in 90m'\",$RESET}"
pcheck "time: in 1h30" 'worker in 1h30' "{\"at\":1792711800,\"at_text\":\"in 1h30\",\"at_shown\":\"7:30 PM ET (in 1h30, in 1h 30m)\",\"run\":\"S worker . --at 1792711800 --at-text 'in 1h30'\",$RESET}"
pcheck "time: in 2 hours" 'worker in 2 hours' "{\"at\":1792713600,\"at_text\":\"in 2 hours\",\"at_shown\":\"8:00 PM ET (in 2 hours, in 2h 0m)\",\"run\":\"S worker . --at 1792713600 --at-text 'in 2 hours'\",$RESET}"
pcheck "time: in 45 min" 'worker in 45 min' "{\"at\":1792709100,\"at_text\":\"in 45 min\",\"at_shown\":\"6:45 PM ET (in 45 min, in 45m)\",\"run\":\"S worker . --at 1792709100 --at-text 'in 45 min'\",$RESET}"
WIN='"at":1792714800,"at_shown":"8:20 PM ET (%s, in 2h 20m)","at_text":"%s","run":"S worker . --at 1792714800 --at-text %s --window"'
for phrase in 'after window' 'after the window' 'next window' 'when the window resets' 'after reset'; do
  q="'$phrase'"; [ "$phrase" = window ] && q=window
  pcheck "time: $phrase" "worker $phrase" "{$(printf "$WIN" "$phrase" "$phrase" "$q"),$RESET}"
done
pcheck "time: --after window" 'worker --after window' "{$(printf "$WIN" 'after window' 'after window' "'after window'"),$RESET}"
pcheck "time: after window until 11pm" 'worker after window until 11pm' "{$(printf "$WIN" 'after window' 'after window' "'after window'"),$RESET,\"until\":1792724400,\"until_shown\":\"11:00 PM ET\",\"until_text\":\"until 11pm\",\"run\":\"S worker . --at 1792714800 --at-text 'after window' --window --until 1792724400\"}"
pcheck "time: until without a window phrase -> unsure" 'worker at 9pm until 11pm' "{$AT9,$RESET,\"unsure\":[\"until 11pm\"]}"
pcheck "time: unparseable after at -> unsure" 'worker at 25pm' '{"unsure":["at 25pm"]}'
pcheck "time: in <dir> still a directory" 'worker in sibling' "{\"dir\":\"$T/sibling\",\"dir_state\":\"exists\",\"dir_typed\":\"sibling\",\"command\":\"claude --agent worker \\\".\\\" --name \\\"worker: sibling\\\"\",\"run\":\"S worker . --cwd $T/sibling\"}"
pcheck "time: dir + at 9pm" 'worker in ../../sibling at 9pm' "{\"dir\":\"$T/sibling\",\"dir_state\":\"exists\",\"dir_typed\":\"../../sibling\",\"command\":\"claude --agent worker \\\".\\\" --name \\\"worker: sibling\\\"\",\"at\":1792717200,\"at_text\":\"at 9pm\",\"at_shown\":\"9:00 PM ET (at 9pm, in 3h 0m)\",$RESET,\"run\":\"S worker . --cwd $T/sibling --at 1792717200 --at-text 'at 9pm'\"}"
pcheck "time: dry with model, effort, at" 'worker fable low effort at 9pm dry' "{$FLOW,\"dry\":1,\"at\":1792717200,\"at_text\":\"at 9pm\",\"at_shown\":\"9:00 PM ET (at 9pm, in 3h 0m)\",$RESET,\"run\":\"S worker . --at 1792717200 --at-text 'at 9pm' -- --model fable --effort low\"}"
pcheck "time: dry run alone fetches the reset" 'worker dry run' "{\"dry\":1,$RESET}"
pcheck "time: --dry-run" 'worker --dry-run' "{\"dry\":1,$RESET}"
# usage API unreachable
RUN_AGENT_USAGE_FILE="$T/no-such-usage.json" pcheck "time: after window with the API unreachable -> at_error" 'worker after window' \
  '{"at_text":"after window","at_error":"usage API: FileNotFoundError: [Errno 2] No such file or directory: '"'"''"$T"'/no-such-usage.json'"'"'; open any claude session to refresh the token"}'
RUN_AGENT_USAGE_FILE="$T/no-such-usage.json" pcheck "time: at 9pm with the API unreachable -> reset unavailable" 'worker at 9pm' \
  "{$AT9,\"reset_shown\":\"unavailable (FileNotFoundError: [Errno 2] No such file or directory: '$T/no-such-usage.json')\"}"
# typos (4+)
pcheck "typo: fabel -> fable" 'worker fabel low' "{$FLOW,\"corrections\":[\"fabel -> fable\"]}"
pcheck "typo: efort lo -> effort low" 'worker efort lo' '{"flags":"--effort low","corrections":["efort -> effort","lo -> low"],"command":"claude --agent worker \".\" --effort low --name \"worker: repo\"","run":"S worker . -- --effort low"}'
pcheck "typo: wroker -> worker" 'wroker fable' '{"flags":"--model fable","corrections":["wroker -> worker"],"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}'
pcheck "typo: zzqx -> unsure" 'worker zzqx' '{"unsure":["zzqx"]}'
pcheck "typo: lwo (tie low/two-ish) -> unsure" 'worker fable lwo' '{"flags":"--model fable","unsure":["lwo"],"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}'
# existing word mappings
pcheck "words: with opus yolo resume" 'worker with opus yolo resume' '{"flags":"--model opus --dangerously-skip-permissions --continue","command":"claude --agent worker \".\" --model opus --dangerously-skip-permissions --continue --name \"worker: repo (opus)\"","run":"S worker . -- --model opus --dangerously-skip-permissions --continue"}'
pcheck "words: just do it = force" 'worker just do it' '{"force":1}'
pcheck "words: force word inside the prompt is prompt" 'worker "go now"' '{"prompt":"go now","command":"claude --agent worker \"go now\" --name \"worker: repo\"","run":"S worker '"'"'go now'"'"'"}'
pcheck "words: worker! = force" 'worker! fable' '{"flags":"--model fable","force":1,"command":"claude --agent worker \".\" --model fable --name \"worker: repo (fable)\"","run":"S worker . -- --model fable"}'
pcheck "words: trailing ! = force" 'worker "." !' '{"force":1}'
pcheck "words: ~ path token" 'worker ~/files' "{\"dir\":\"$HOME/files\",\"dir_state\":\"$([ -d "$HOME/files" ] && echo exists || echo missing)\",\"dir_typed\":\"~/files\",\"command\":\"claude --agent worker \\\".\\\" --name \\\"worker: files\\\"\",\"run\":\"S worker . --cwd $HOME/files\"}"
pcheck "words: --name given" 'worker --name mine' '{"flags":"--name mine","command":"claude --agent worker \".\" --name \"mine\"","run":"S worker . -- --name mine"}'
pcheck "words: two directories -> error" 'worker ~/a ~/b' "{\"dir_typed\":\"~/a\",\"error\":\"usage: two directories: ~/a, ~/b\"}"
pcheck "words: planner has no default prompt" 'planner opus' '{"agent":"planner","prompt":"","flags":"--model opus","command":"claude --agent planner --model opus --name \"planner: repo (opus)\"","run":"S planner -- --model opus"}'
unset RUN_AGENT_NOW

# Inside tmux (private server): the respawned pane and claude start in the target dir.
if command -v tmux >/dev/null; then
  cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
{ echo "pwd=$PWD"; printf 'arg=%s\n' "$@"; } > "$RA_OUT"
EOF
  chmod +x "$T/bin/claude"
  # The shell left in a respawned pane is $SHELL; a no-rc one keeps the fake claude first on PATH.
  printf '#!/usr/bin/env bash\nexec bash --norc --noprofile "$@"\n' > "$T/bin/sh-norc"; chmod +x "$T/bin/sh-norc"
  export RA_OUT="$T/claude.out"
  # The server itself carries the fake PATH/RA_OUT so panes respawned by the detached runner see them too.
  PANE_ENV="env PATH='$T/bin:$PATH' RA_OUT='$RA_OUT' RUN_AGENT_HOME='$RUN_AGENT_HOME' RUN_AGENT_USAGE_FILE='$RUN_AGENT_USAGE_FILE' RUN_AGENT_TZ=America/New_York SHELL='$T/bin/sh-norc'"
  env PATH="$T/bin:$PATH" RA_OUT="$RA_OUT" SHELL="$T/bin/sh-norc" TMUX= tmux -L "$SOCK" -f /dev/null new-session -d -s t -c "$T/repo/sub" \
    "$PANE_ENV bash --norc --noprofile"
  sleep 0.5
  tmux -L "$SOCK" send-keys -t t "'$S' planner 'curl it' --cwd '$T/my project'" Enter
  for _ in $(seq 1 40); do [ -s "$RA_OUT" ] && break; sleep 0.25; done
  sleep 0.5
  if [ -s "$RA_OUT" ] && grep -qxF "pwd=$T/my project" "$RA_OUT"; then ok "tmux: claude started in the dir"
  else bad "tmux: claude started in the dir" "$(cat "$RA_OUT" 2>/dev/null)"; fi
  grep -qxF "arg=planner: my project" "$RA_OUT" 2>/dev/null && ok "tmux: --name \"planner: my project\" is one argument" \
    || bad "tmux: --name argument" "$(cat "$RA_OUT" 2>/dev/null)"
  p=$(tmux -L "$SOCK" display -p -t t '#{pane_current_path}')
  [ "$p" = "$T/my project" ] && ok "tmux: pane_current_path is the dir" || bad "tmux: pane_current_path" "$p"
  dead=$(tmux -L "$SOCK" display -p -t t '#{pane_dead}')
  [ "$dead" = 0 ] && ok "tmux: shell left in the pane" || bad "tmux: shell left in the pane" "pane_dead=$dead"

  # ---------------------------------------------------------------- scheduling suite
  TM() { tmux -L "$SOCK" "$@"; }
  keys() { TM send-keys -t "${TARGET:-t}" "$1" Enter; }
  wait_for() {  # wait_for <seconds> <command...>: poll until the command succeeds
    local n=$(( $1 * 4 )); shift
    while [ $n -gt 0 ]; do "$@" 2>/dev/null && return 0; sleep 0.25; n=$((n-1)); done; return 1
  }
  usage_at() { python3 -c "import json,datetime,sys; print(json.dumps({'five_hour':{'utilization':1.0,'resets_at':datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).isoformat()}}))" "$1" > "$RUN_AGENT_USAGE_FILE"; }
  LOG="$RUN_AGENT_HOME/jobs.log"
  keys "cd '$T/repo/sub'"; sleep 0.5

  # (1) window run 3 s ahead: job file, --jobs before, fired into the pane, log line, --jobs after.
  R=$(( $(date +%s) + 3 )); usage_at "$R"
  : > "$RA_OUT"
  keys "'$S' worker '.' --at $R --at-text 'after window' --window -- --model fable > '$T/sched.out' 2>&1; '$S' --jobs > '$T/jobs1.out'"
  wait_for 5 test -s "$T/jobs1.out"
  SHOWN='claude --agent worker "." --model fable --name "worker: repo (fable)"'
  grep -q "^scheduled #1: $SHOWN at .* ET (after window, in 0m)$" "$T/sched.out" && ok "sched: scheduled line" || bad "sched: scheduled line" "$(cat "$T/sched.out")"
  [ -f "$RUN_AGENT_HOME/jobs/1.json" ] && ok "sched: job file written" || bad "sched: job file written" "$(ls "$RUN_AGENT_HOME/jobs" 2>&1)"
  python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j['run_at']==int(sys.argv[2]) and j['at_text']=='after window' and j['window']==1 and j['pane'].startswith('%') and j['session']=='t' and j['argv'][:3]==['claude','--agent','worker'] and j['cwd']=='$T/repo/sub', j" "$RUN_AGENT_HOME/jobs/1.json" "$R" \
    && ok "sched: job fields" || bad "sched: job fields" "$(cat "$RUN_AGENT_HOME/jobs/1.json")"
  grep -q "^#1  $SHOWN  at .* ET (after window, in 0m)$" "$T/jobs1.out" && ok "sched: --jobs lists it" || bad "sched: --jobs lists it" "$(cat "$T/jobs1.out")"
  wait_for 10 grep -q "arg=worker: repo (fable)" "$RA_OUT" && ok "sched: fired into the pane (claude ran)" || bad "sched: fired into the pane" "$(cat "$RA_OUT")"
  sleep 0.5
  TM capture-pane -p -J -t t -S - | grep -q "^scheduled run #1 fired at .* ET: $SHOWN" && ok "sched: first pane line" || bad "sched: first pane line" "$(TM capture-pane -p -t t -S - | grep -v '^$' | tail -5)"
  grep -q "  #1  fired  $SHOWN" "$LOG" 2>/dev/null && ok "sched: jobs.log fired" || bad "sched: jobs.log fired" "$(cat "$LOG" 2>/dev/null)"
  [ -f "$RUN_AGENT_HOME/done/1.json" ] && [ ! -f "$RUN_AGENT_HOME/jobs/1.json" ] && ok "sched: job moved to done/" || bad "sched: job moved to done/"
  wait_for 3 TM display -p -t t '#{pane_dead}' >/dev/null
  [ "$("$S" --jobs)" = "no scheduled runs" ] && ok "sched: --jobs after = no scheduled runs" || bad "sched: --jobs after" "$("$S" --jobs)"

  # (2) cancel: schedule 10 min ahead, then --cancel (one pending, no id)
  R=$(( $(date +%s) + 600 ))
  out=$("$S" worker '.' --at "$R" --at-text 'in 10m' 2>&1)
  wait_for 3 test -f "$RUN_AGENT_HOME/jobs/2.json"
  wait_for 3 bash -c "[ \"\$(python3 '$(dirname "$S")/jobs.py' get 2 pid)\" != 0 ]"
  pid=$(python3 "$(dirname "$S")/jobs.py" get 2 pid)
  out=$("$S" --cancel 2>&1)
  grep -q "  #2  cancelled  " <<<"$out" && ok "sched: --cancel one pending" || bad "sched: --cancel" "$out"
  wait_for 3 bash -c "! kill -0 $pid 2>/dev/null" && ok "sched: runner killed" || bad "sched: runner killed" "pid $pid alive"
  [ ! -f "$RUN_AGENT_HOME/jobs/2.json" ] && grep -q "  #2  cancelled  " "$LOG" && ok "sched: cancelled logged" || bad "sched: cancelled logged" "$(cat "$LOG")"
  [ "$("$S" --cancel 2>&1)" = "no scheduled runs" ] && ok "sched: --cancel with nothing pending" || bad "sched: --cancel with nothing pending" "$("$S" --cancel 2>&1)"
  R2=$(( R + 60 ))
  "$S" worker '.' --at "$R" --at-text 'in 10m' >/dev/null; "$S" worker '.' --at "$R2" --at-text 'in 11m' >/dev/null
  out=$("$S" --cancel 2>&1); grep -q "several scheduled runs" <<<"$out" && ok "sched: --cancel with two pending asks for an id" || bad "sched: --cancel two pending" "$out"
  "$S" --cancel 3 >/dev/null; "$S" --cancel '#4' >/dev/null
  [ "$("$S" --jobs)" = "no scheduled runs" ] && ok "sched: --cancel <id> twice" || bad "sched: --cancel <id>" "$("$S" --jobs)"

  # (3) until earlier than the reset: skipped, nothing scheduled
  R=$(( $(date +%s) + 7200 )); usage_at "$R"
  out=$("$S" worker '.' --at "$R" --at-text 'after window' --window --until $(( R - 3600 )) 2>&1)
  grep -q "^skipped: reset .* ET is after until .* ET$" <<<"$out" && ok "sched: until earlier than reset -> skipped" || bad "sched: until skipped" "$out"
  grep -q "skipped: reset" "$LOG" && ok "sched: skipped logged" || bad "sched: skipped logged" "$(cat "$LOG")"
  [ -z "$(ls "$RUN_AGENT_HOME/jobs")" ] && ok "sched: nothing scheduled after skip" || bad "sched: nothing scheduled after skip" "$(ls "$RUN_AGENT_HOME/jobs")"
  # until at fire time: scheduled with until ok, the API then moves the reset past until -> runner skips
  R=$(( $(date +%s) + 3 )); usage_at "$R"
  "$S" worker '.' --at "$R" --at-text 'after window' --window --until $(( R + 60 )) >/dev/null
  usage_at $(( R + 120 ))
  wait_for 10 grep -q "  #5  skipped  " "$LOG" && ok "sched: runner re-fetches at fire time and skips past until" || bad "sched: runner skip at fire time" "$(cat "$LOG")"

  # (4) usage API unreachable: exit 2, nothing scheduled
  out=$(RUN_AGENT_USAGE_FILE="$T/none.json" "$S" worker '.' --at 0 --at-text 'after window' --window 2>&1); rc=$?
  [ "$rc" = 2 ] && grep -q "^at_error: usage API: " <<<"$out" && ok "sched: API unreachable -> exit 2" || bad "sched: API unreachable" "rc=$rc $out"

  # (4b) --need-tmux outside tmux: exit 1, nothing scheduled
  out=$(TMUX= "$S" worker '.' --at 0 --at-text 'after window' --window --need-tmux 2>&1); rc=$?
  [ "$rc" = 1 ] && [ "$(head -1 <<<"$out")" = "not scheduled — not in tmux" ] && ok "sched: --need-tmux outside tmux -> exit 1" || bad "sched: --need-tmux" "rc=$rc $out"
  [ "$(tail -1 <<<"$out")" = "Relaunch: not scheduled — not in tmux; run /run-agent worker after window to schedule it by hand" ] && ok "sched: --need-tmux Relaunch line (no tmux)" || bad "sched: --need-tmux Relaunch line (no tmux)" "$out"
  # (4c) --need-tmux with no reset time: exit 2, Relaunch line with the hint
  out=$(RUN_AGENT_USAGE_FILE="$T/none.json" "$S" worker '.' --at 0 --at-text 'after window' --window --need-tmux 2>&1); rc=$?
  [ "$rc" = 2 ] && grep -q "^Relaunch: not scheduled — no reset time (.*); run /run-agent worker after window to schedule it by hand$" <<<"$out" && ok "sched: --need-tmux Relaunch line (no reset)" || bad "sched: --need-tmux Relaunch line (no reset)" "rc=$rc $out"
  # (4d) --need-tmux success: last line is Relaunch: <time> ET (job #N)
  R=$(( $(date +%s) + 600 )); usage_at "$R"
  out=$("$S" worker '.' --at "$R" --at-text 'after window' --window --need-tmux 2>&1); rc=$?
  [ "$rc" = 0 ] && grep -q "^Relaunch: .* ET (job #[0-9]*)$" <<<"$(tail -1 <<<"$out")" && ok "sched: --need-tmux Relaunch line (scheduled)" || bad "sched: --need-tmux Relaunch line (scheduled)" "rc=$rc $out"
  "$S" --cancel >/dev/null 2>&1

  # (4e) --handoff: schedule + note + WIP commit in one call, from a scratch repo (in tmux, reset 2 min ahead)
  H="$T/handoff"; mkdir -p "$H"; git -C "$H" init -q; git -C "$H" commit -q --allow-empty -m init
  printf 'plans/\n' > "$H/.gitignore"; echo a > "$H/a.txt"
  R=$(( $(date +%s) + 120 )); usage_at "$R"
  out=$(cd "$H" && printf 'Done: x\nIn progress: y\nNext: z\n' | "$S" --handoff worker "." -- --model haiku 2>&1); rc=$?
  [ "$rc" = 0 ] && [ "$(sed -n 1p <<<"$out")" = "Note: plans/WORKER_NOTES.md" ] && grep -q "^Commit: [0-9a-f]* WIP: stopped at usage limit — y$" <<<"$(sed -n 2p <<<"$out")" \
    && grep -q "^Relaunch: .* ET (job #[0-9]*)$" <<<"$(sed -n 3p <<<"$out")" && ok "handoff: prints Note / Commit / Relaunch" || bad "handoff: output" "rc=$rc $out"
  n=$(tail -n 6 "$H/plans/WORKER_NOTES.md")
  grep -q "^## Stopped at usage limit — 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9]*:[0-9][0-9] [AP]M ET$" <<<"$(sed -n 1p <<<"$n")" \
    && [ "$(sed -n 2,4p <<<"$n")" = "$(printf 'Done: x\nIn progress: y\nNext: z')" ] \
    && [ "$(sed -n 5p <<<"$n")" = "Uncommitted/dirty: .gitignore, a.txt" ] && grep -q "^Relaunch: .* ET (job #[0-9]*)$" <<<"$(sed -n 6p <<<"$n")" \
    && ok "handoff: note section (heading with time, stdin, Uncommitted, Relaunch)" || bad "handoff: note section" "$n"
  [ "$(git -C "$H" log -1 --format=%s)" = "WIP: stopped at usage limit — y" ] && [ -z "$(git -C "$H" status --porcelain)" ] \
    && git -C "$H" log -1 --format=%b | grep -q "^Co-Authored-By: Claude <noreply@anthropic.com>$" && ok "handoff: WIP commit, tree clean, plans/ not committed" || bad "handoff: WIP commit" "$(git -C "$H" log -1; git -C "$H" status --porcelain)"
  grep -q '^#[0-9]*  claude --agent worker "." --model haiku --name "worker: handoff (haiku)"  at .* ET (after window, in 2m)$' <<<"$("$S" --jobs)" && ok "handoff: --jobs lists the relaunch" || bad "handoff: --jobs" "$("$S" --jobs)"
  "$S" --cancel >/dev/null 2>&1
  # outside tmux: note and commit still written, Relaunch says not scheduled
  echo b > "$H/b.txt"
  out=$(cd "$H" && printf 'Done: x\nIn progress:\n- half of b\nNext: z\n' | TMUX= "$S" --handoff worker 2>&1); rc=$?
  [ "$rc" = 0 ] && [ "$(sed -n 3p <<<"$out")" = "Relaunch: not scheduled — not in tmux; run /run-agent worker after window to schedule it by hand" ] \
    && [ "$(git -C "$H" log -1 --format=%s)" = "WIP: stopped at usage limit — half of b" ] && [ "$(tail -n1 "$H/plans/WORKER_NOTES.md")" = "$(sed -n 3p <<<"$out")" ] \
    && ok "handoff: outside tmux -> exit 0, note + commit, not-scheduled Relaunch" || bad "handoff: outside tmux" "rc=$rc $out"
  # no reset time ({}): same fallback shape, exit 0
  echo '{}' > "$T/empty.json"; echo c > "$H/c.txt"
  out=$(cd "$H" && printf 'In progress: c\n' | RUN_AGENT_USAGE_FILE="$T/empty.json" "$S" --handoff worker 2>&1); rc=$?
  [ "$rc" = 0 ] && grep -q "^Relaunch: not scheduled — no reset time (.*); run /run-agent worker after window to schedule it by hand$" <<<"$(sed -n 3p <<<"$out")" \
    && [ "$(git -C "$H" log -1 --format=%s)" = "WIP: stopped at usage limit — c" ] && ok "handoff: no reset time -> exit 0, note + commit" || bad "handoff: no reset time" "rc=$rc $out"
  [ "$("$S" --jobs)" = "no scheduled runs" ] && ok "handoff: fallbacks scheduled nothing" || bad "handoff: fallbacks scheduled nothing" "$("$S" --jobs)"
  # empty stdin, clean tree: heading + Uncommitted + Relaunch only, Commit: nothing to commit
  usage_at "$R"
  out=$(cd "$H" && : | "$S" --handoff worker 2>&1); rc=$?
  n=$(tail -n 3 "$H/plans/WORKER_NOTES.md")
  [ "$rc" = 0 ] && [ "$(sed -n 2p <<<"$out")" = "Commit: nothing to commit" ] && grep -q "^## Stopped at usage limit — .* ET$" <<<"$(sed -n 1p <<<"$n")" \
    && [ "$(sed -n 2p <<<"$n")" = "Uncommitted/dirty: none" ] && grep -q "^Relaunch: .* ET (job #[0-9]*)$" <<<"$(sed -n 3p <<<"$n")" \
    && ok "handoff: empty stdin -> heading + Uncommitted + Relaunch only" || bad "handoff: empty stdin" "rc=$rc $out / $n"
  "$S" --cancel >/dev/null 2>&1
  # non-git directory: Commit: no git, note still written
  mkdir -p "$T/nogit"
  out=$(cd "$T/nogit" && printf 'Next: z\n' | "$S" --handoff worker 2>&1); rc=$?
  [ "$rc" = 0 ] && [ "$(sed -n 2p <<<"$out")" = "Commit: no git" ] && grep -q "^Next: z$" "$T/nogit/plans/WORKER_NOTES.md" \
    && ok "handoff: non-git dir -> Commit: no git" || bad "handoff: non-git dir" "rc=$rc $out"
  "$S" --cancel >/dev/null 2>&1

  # (5) dry run: prints, schedules nothing
  R=$(( $(date +%s) + 3600 )); usage_at "$R"
  out=$("$S" --dry-run worker '.' --at "$R" --at-text 'in 1h' -- --model fable 2>&1)
  grep -q "^command: $SHOWN$" <<<"$out" && grep -q "^dir: $T/repo/sub$" <<<"$out" && grep -q "^run at: .* ET (in 1h, in 1h 0m)$" <<<"$out" \
    && grep -q "^usage reset: .* ET$" <<<"$out" && ok "sched: --dry-run prints command, dir, time, reset" || bad "sched: --dry-run" "$out"
  [ "$("$S" --jobs)" = "no scheduled runs" ] && ok "sched: --dry-run scheduled nothing" || bad "sched: --dry-run scheduled nothing" "$("$S" --jobs)"

  # (6) pane gone: schedule from a second window, kill that pane -> new window in the session
  TM new-window -t t -n second -c "$T/repo/sub" "$PANE_ENV bash --norc --noprofile"
  sleep 0.5
  R=$(( $(date +%s) + 3 )); : > "$RA_OUT"
  TARGET=t:second keys "'$S' worker '.' --at $R --at-text 'in 3s' > '$T/sched6.out' 2>&1"
  wait_for 3 test -s "$T/sched6.out"
  TM kill-window -t t:second
  wait_for 10 grep -q "  #10  fired in new window  " "$LOG" && ok "sched: pane gone -> fired in new window" || bad "sched: pane gone" "$(cat "$LOG")"
  wait_for 3 bash -c "tmux -L '$SOCK' list-windows -t t -F '#{window_name}' | grep -qx 'worker: repo'" && ok "sched: new window named 'worker: repo'" || bad "sched: new window name" "$(TM list-windows -t t)"
  wait_for 5 grep -q "arg=worker: repo" "$RA_OUT" && ok "sched: claude ran in the new window" || bad "sched: claude in new window" "$(cat "$RA_OUT")"

  # (7) server gone: schedule, kill the server -> a new detached session
  R=$(( $(date +%s) + 3 )); : > "$RA_OUT"
  keys "'$S' worker '.' --at $R --at-text 'in 3s' > '$T/sched7.out' 2>&1"
  wait_for 3 test -s "$T/sched7.out"
  TM kill-server
  wait_for 10 grep -q "  #11  fired in new session  " "$LOG" && ok "sched: server gone -> fired in new session" || bad "sched: server gone" "$(cat "$LOG")"
  wait_for 3 bash -c "tmux -L '$SOCK' list-sessions -F '#{session_name}' | grep -qx 'worker repo'" && ok "sched: new session 'worker repo'" || bad "sched: new session" "$(TM list-sessions 2>&1)"
  wait_for 5 grep -q "arg=worker: repo" "$RA_OUT" && ok "sched: claude ran in the new session" || bad "sched: claude in new session" "$(cat "$RA_OUT")"

  # (8) revive: the runner dies (reboot, WSL restart) -> --revive starts a new one, silently; overdue runs are skipped
  J="$(dirname "$S")/jobs.py"
  TM new-session -d -s r -c "$T/repo/sub" "$PANE_ENV bash --norc --noprofile"; sleep 0.5
  sched_r() {  # sched_r <out file>: schedule 10 min ahead from pane r, kill its runner, print the id
    TARGET=r keys "'$S' worker '.' --at $(( $(date +%s) + 600 )) --at-text 'in 10m' > '$1' 2>&1"
    wait_for 5 grep -q "^scheduled #" "$1"; local id; id=$(sed -n 's/^scheduled #\([0-9]*\):.*/\1/p' "$1")
    wait_for 3 bash -c "[ \"\$(python3 '$J' get $id pid)\" != 0 ]"
    kill -9 "$(python3 "$J" get "$id" pid)"; wait_for 3 bash -c "! kill -0 $(python3 "$J" get "$id" pid)"
    echo "$id"
  }
  id=$(sched_r "$T/sched8.out")
  grep -q "^#$id  .*\[runner not running\]$" <<<"$("$S" --jobs)" && ok "revive: --jobs flags the dead runner" || bad "revive: --jobs dead runner" "$("$S" --jobs)"
  pane=$(python3 "$J" get "$id" pane)
  out=$("$S" --revive 2>&1); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ] && ok "revive: silent, exit 0" || bad "revive: silent" "rc=$rc $out"
  pid=$(python3 "$J" get "$id" pid); kill -0 "$pid" 2>/dev/null && ok "revive: future run gets a new runner, pid recorded" || bad "revive: runner alive" "pid=$pid"
  [ "$(python3 "$J" get "$id" pane)" = "$pane" ] && ok "revive: same tmux server keeps the pane" || bad "revive: pane kept" "$(python3 "$J" get "$id" pane)"
  "$S" --revive; [ "$(python3 "$J" get "$id" pid)" = "$pid" ] && ok "revive: live runner left alone" || bad "revive: live runner left alone"
  python3 "$J" set "$id" server_pid 1; kill -9 "$pid"; wait_for 3 bash -c "! kill -0 $pid"
  "$S" --revive
  [ -z "$(python3 "$J" get "$id" pane)" ] && ok "revive: new tmux server clears the stale pane id" || bad "revive: pane cleared" "$(python3 "$J" get "$id" pane)"
  "$S" --cancel "$id" >/dev/null
  # overdue: skipped and logged, never run
  id=$(sched_r "$T/sched9.out"); : > "$RA_OUT"
  python3 -c "import json,sys,time; p=sys.argv[1]; j=json.load(open(p)); j['run_at']=int(time.time())-60; json.dump(j,open(p,'w'))" "$RUN_AGENT_HOME/jobs/$id.json"
  out=$("$S" --revive 2>&1)
  [ -z "$out" ] && [ ! -f "$RUN_AGENT_HOME/jobs/$id.json" ] && grep -q "  #$id  skipped  .*(was due .* ET; its runner stopped)$" "$LOG" \
    && ok "revive: overdue run skipped and logged" || bad "revive: overdue skipped" "$out / $(tail -2 "$LOG")"
  sleep 1; [ ! -s "$RA_OUT" ] && ok "revive: overdue run did not start claude" || bad "revive: overdue started claude" "$(cat "$RA_OUT")"
else
  echo "SKIP tmux checks (tmux not installed)"
fi

# ---- launch targets, shell command, next-step line
out=$("$S" --parse 'planner "Plan A" in /tmp split')
python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['target']=='split' and '--target split' in d['run'] and d['dir']=='/tmp' and not d['unsure'], d" "$out" && ok "target: split parsed" || bad "target: split" "$out"
out=$("$S" --parse 'worker new window')
python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['target']=='window', d" "$out" && ok "target: new window parsed" || bad "target: window" "$out"
out=$("$S" --parse 'worker after window')
python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'target' not in d and d['at_text']=='after window', d" "$out" && ok "target: 'after window' stays a time" || bad "target: after window" "$out"
out=$("$(dirname "$S")/../../../bin/run-agent" worker "." in "$T" dry </dev/null 2>&1)
grep -q "^command: claude --agent worker" <<<"$out" && grep -q "^dir: " <<<"$out" && grep -q "^run at: now" <<<"$out" && ok "bin/run-agent: dry prints command, dir, time" || bad "bin/run-agent dry" "$out"
out=$("$S" --next planner "Replan based on plans/EVAL.md")
mapfile -t nl <<<"$out"
[ "${#nl[@]}" = 3 ] && [[ "${nl[0]}" == Next,*replan* ]] && [[ "${nl[0]}" == *: ]] && [ "${#nl[0]}" -le 60 ] \
  && [[ "${nl[1]}" == '/run-agent planner "Replan based on plans/EVAL.md"'* ]] && [[ "${nl[1]}" != *claude* ]] \
  && [[ "${nl[2]}" == 'Without run-agent: claude --agent planner "Replan based on plans/EVAL.md"'* ]] \
  && ok "next: short sentence, /run-agent line, labelled claude line, three lines" || bad "next: lines" "$out"
out=$("$S" --next evaluator phone); grep -q '^Next, .*evaluator on your phone:$' <<<"$out" && ok "next: evaluator phone sentence" || bad "next: phone" "$out"
out=$( (exec -a claude bash -c "'$S' --next worker .; true" _ --agent evaluator --model opus --effort high) )
[ "$(wc -l <<<"$out")" = 3 ] && grep -q '^Next, after reading this eval, rerun the worker' <<<"$out" && grep -qx '/run-agent worker "."' <<<"$out" \
  && grep -qx 'Without run-agent: claude --agent worker "."' <<<"$out" && ok "next worker: no model/effort even from an opus high session" || bad "next: worker flags" "$out"
out=$( (exec -a claude bash -c "'$S' --next evaluator .; true" _ --agent worker --model opus --effort high) )
grep -qx '/run-agent evaluator "."' <<<"$out" && grep -qx 'Without run-agent: claude --agent evaluator "."' <<<"$out" \
  && ok "next evaluator: no model/effort even from an opus high session" || bad "next: evaluator flags" "$out"
out=$( (exec -a claude bash -c "'$S' --next planner 'Replan based on plans/EVAL.md'; true" _ --agent evaluator --model opus --effort high) )
grep -qx '/run-agent planner "Replan based on plans/EVAL.md" opus high' <<<"$out" && ok "next planner: keeps the session's model/effort" || bad "next: planner flags" "$out"
# several runs joined by +
out=$("$S" --relaunch "planner \"Plan A\" in $T + planner \"Plan B\" in $T dry")
[ "$(grep -c '^run [12]:' <<<"$out")" = 2 ] && grep -q '^opens in: one new tmux window, 2 panes tiled' <<<"$out" && ok "group: dry lists each run and the one window" || bad "group: dry" "$out"
out=$("$S" --relaunch "planner \"Plan A\" in $T + planner \"Plan B\" in $T at 9pm"); rc=$?
[ "$rc" = 2 ] && grep -q 'start now; schedule each run on its own' <<<"$out" && ok "group: scheduled group refused" || bad "group: at" "$rc $out"
out=$("$S" --relaunch 'planner "Plan A + B" in /tmp dry')
grep -q '^command: claude --agent planner "Plan A + B"' <<<"$out" && ok "group: + inside quotes is not a separator" || bad "group: quoted +" "$out"
if command -v tmux >/dev/null 2>&1; then
  TS="$T/split.sock"; mkdir -p "$T/fakebin" "$T/ga" "$T/gb" "$T/gc" "$T/gd"
  printf '#!/bin/bash\nsleep 30\n' > "$T/fakebin/claude"; chmod +x "$T/fakebin/claude"
  tmux -S "$TS" -f /dev/null new-session -d -x 200 -y 60 -s sp "bash --norc --noprofile"
  caller=$(tmux -S "$TS" list-panes -t sp:0 -F '#{pane_id}')
  for p in A B C D; do
    tmux -S "$TS" send-keys -t "$caller" "PATH=$T/fakebin:\$PATH '$S' --relaunch 'planner \"Plan $p\" in $T split' >> '$T/split.out' 2>&1" Enter
    wait_for 8 bash -c "[ \$(grep -c '^opened' '$T/split.out') -ge \$1 ]" _ $(( $(printf 'ABCD' | sed "s/$p.*//" | wc -c) + 1 ))
  done
  wins=$(tmux -S "$TS" list-windows -t sp -F '#{window_panes}' | paste -sd' ')
  [ "$(tmux -S "$TS" list-panes -t sp:0 -F '#{pane_id}')" = "$caller" ] && [ "$wins" = "1 1 1 1 1" ] \
    && [ "$(grep -c '^opened new window' "$T/split.out")" = 4 ] \
    && ok "split: four launches give four new one-pane windows, caller window unchanged" || bad "split: new windows" "windows=$wins $(cat "$T/split.out")"
  tmux -S "$TS" kill-server 2>/dev/null
  # own socket: a new server on split.sock right after its kill-server can hit "server exited unexpectedly"
  TG="$T/group.sock"
  # one call, four planners: a new window split 2x2, each pane in its own folder, caller window unchanged
  tmux -S "$TG" -f /dev/null new-session -d -x 200 -y 60 -s gp "bash --norc --noprofile"
  caller=$(tmux -S "$TG" list-panes -t gp:0 -F '#{pane_id}')
  raw="planner \\\"Plan A\\\" in $T/ga + planner \\\"Plan B\\\" in $T/gb + planner \\\"Plan C\\\" in $T/gc + planner \\\"Plan D\\\" in $T/gd"
  tmux -S "$TG" send-keys -t "$caller" "PATH=$T/fakebin:\$PATH '$S' --group \"$raw\" > '$T/group.out' 2>&1" Enter
  wait_for 10 bash -c "[ \$(tmux -S '$TG' list-panes -t gp:1 2>/dev/null | wc -l) = 4 ] && [ \$(grep -c '^opened' '$T/group.out') = 4 ]"
  panes=$(tmux -S "$TG" list-panes -t gp:1 -F '#{pane_left},#{pane_top} #{pane_current_path}' 2>/dev/null)
  lefts=$(cut -d, -f1 <<<"$panes" | sort -u | wc -l); tops=$(cut -d' ' -f1 <<<"$panes" | cut -d, -f2 | sort -u | wc -l)
  dirs=$(awk '{print $2}' <<<"$panes" | xargs -n1 basename 2>/dev/null | sort | paste -sd' ')
  [ "$(tmux -S "$TG" list-panes -t gp:0 -F '#{pane_id}')" = "$caller" ] && [ "$(wc -l <<<"$panes")" = 4 ] \
    && [ "$lefts" = 2 ] && [ "$tops" = 2 ] && [ "$dirs" = "ga gb gc gd" ] \
    && [ "$(tmux -S "$TG" list-windows -t gp | wc -l)" = 2 ] \
    && ok "group: one call gives a new 2x2 window, one planner per folder, caller window unchanged" \
    || bad "group: 2x2" "panes=[$panes] lefts=$lefts tops=$tops dirs=$dirs $(cat "$T/group.out")"
  # the confirm path: --relaunch opens a new window holding only the confirm; Yes there (--group --here) fills it
  tmux -S "$TG" send-keys -t "$caller" "PATH=$T/fakebin:\$PATH '$S' --relaunch \"$raw\" > '$T/group2.out' 2>&1" Enter
  wait_for 8 grep -q '^opened new window' "$T/group2.out"
  cp=$(grep -o '(%[0-9]*)' "$T/group2.out" | tr -d '()')
  w=$(tmux -S "$TG" display -p -t "$cp" '#{window_id}')
  [ "$(tmux -S "$TG" list-panes -t gp:0 -F '#{pane_id}')" = "$caller" ] && [ "$(tmux -S "$TG" list-panes -t "$w" | wc -l)" = 1 ] \
    && [ "$(tmux -S "$TG" list-windows -t gp | wc -l)" = 3 ] \
    && ok "group: confirm opens alone in a new window" || bad "group: confirm window" "$w $(cat "$T/group2.out")"
  tmux -S "$TG" respawn-pane -k -t "$cp" "bash --norc --noprofile"; sleep 0.5
  tmux -S "$TG" send-keys -t "$cp" "PATH=$T/fakebin:\$PATH '$S' --group --here \"$raw\"" Enter
  wait_for 10 bash -c "[ \$(tmux -S '$TG' list-panes -t '$w' | wc -l) = 4 ]"
  [ "$(tmux -S "$TG" list-panes -t "$w" | wc -l)" = 4 ] && [ "$(tmux -S "$TG" list-panes -t gp:0 -F '#{pane_id}')" = "$caller" ] \
    && ok "group: Yes fills the confirm's own window with four panes" || bad "group: --here" "$(tmux -S "$TG" list-panes -t "$w")"
  tmux -S "$TG" kill-server 2>/dev/null
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
