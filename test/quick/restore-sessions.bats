#!/usr/bin/env bats
# The restore-sessions skill's scripts, offline: its own eval transcripts, made-up ones, and a fake tmux.
# apply.sh is not covered: it needs bash 4 (declare -A), which macOS does not ship.

load ../helpers/common

setup() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) skip "restore-sessions is for WSL and drives tmux, which Git Bash lacks" ;; esac
  temp_home
  export TZ="EST5EDT,M3.2.0,M11.1.0"
  unset RS_PROJECTS RS_SESSIONS RS_TMUX_L RS_SEED
  SKILL="$REPO/skills/restore-sessions"
  S="$SKILL/scripts"
  FX="$REPO/test/fixtures/restore-sessions"
  P="$BATS_TEST_TMPDIR/projects"
  OUT="$BATS_TEST_TMPDIR/out"
  WORK="$TEST_HOME/work"
  T="$(printf '\176')"   # the tilde the scripts print for the home folder
  export FAKE_TMUX_DIR="$BATS_TEST_TMPDIR/tmux" FAKE_PROCS="$BATS_TEST_TMPDIR/procs" FAKE_BOOTS="$BATS_TEST_TMPDIR/boots"
  mkdir -p "$P" "$WORK" "$FAKE_TMUX_DIR/kids" "$FAKE_TMUX_DIR/cap" "$FAKE_TMUX_DIR/cap-shell"
  PATH="$FX/bin:$PATH"
  # GNU date and touch are what the scripts and eval setups are written for; fill in where they are missing.
  if ! command date -d @0 +%s >/dev/null 2>&1; then PATH="$FX/gnu:$PATH"; fi
  export PATH
  STOP="2026-10-15 04:56:11"
  A=aaaaaaaa-0000-4000-8000-000000000001
  B=bbbbbbbb-0000-4000-8000-000000000002
  C=cccccccc-0000-4000-8000-000000000003
  D=dddddddd-0000-4000-8000-000000000004
  E=eeeeeeee-0000-4000-8000-000000000005
  F=ffffffff-0000-4000-8000-000000000006
}

# session <id> <folder name> <hh:mm:ss on the 15th> [key=value ...]
session() {
  local id="$1" name="$2" at="$3"; shift 3
  mkdir -p "$WORK/$name"
  python3 "$FX/mksession.py" "$P" "$id" "$WORK/$name" "2026-10-15 $at" "$@"
}
find_sessions() { bash "$S/find-sessions.sh" "$@"; }
candidates() { find_sessions "$STOP" "$P" > "$BATS_TEST_TMPDIR/cand.tsv"; }
plan() { bash "$S/plan.sh" --candidates "$BATS_TEST_TMPDIR/cand.tsv" --out "$OUT" --projects "$P" "$@"; }
# pane <session> <window> <pane> <id> <command> <pid>
pane() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$FAKE_TMUX_DIR/panes"; }
eval_copy() {
  cp -R "$SKILL/evals/$1" "$BATS_TEST_TMPDIR/eval"
  bash "$BATS_TEST_TMPDIR/eval/setup.sh"
}

# bats test_tags=feature:restore-sessions
@test "find-sessions lists exactly the sessions the shutdown eval expects, oldest first" {
  eval_copy shutdown-2026-10-15
  run find_sessions "$STOP" "$BATS_TEST_TMPDIR/eval"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | cut -f1)" "$(cat "$SKILL/evals/shutdown-2026-10-15/expected.txt")"
  line="$(printf '%s\n' "$output" | grep '^f720125e')"
  assert_equal "$(printf '%s' "$line" | cut -f2,3,5,7,9)" \
    "$(printf '/srv/demo/files/terminal-pet\tworker\tauto\t2026-10-15 04:56:01 EDT\trecent')"
}

# bats test_tags=feature:restore-sessions
@test "find-sessions marks the mid-task eval session as stopped mid-task" {
  eval_copy mid-task-2026-10-15
  run find_sessions '2026-10-15 01:20:00' "$BATS_TEST_TMPDIR/eval"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | cut -f1,6)" "$(cat "$SKILL/evals/mid-task-2026-10-15/expected.txt")"
}

# bats test_tags=feature:restore-sessions
@test "find-sessions takes the hour before the stop and five seconds after, nothing outside" {
  session "$A" early 03:56:10
  session "$B" first 03:56:11
  session "$C" last 04:56:16
  session "$D" late 04:56:17
  mkdir -p "$P/memory" "$P/proj/$E/subagents"
  cp "$P"/*-first/"$B.jsonl" "$P/memory/$E.jsonl"
  cp "$P"/*-first/"$B.jsonl" "$P/proj/$E/subagents/agent-1.jsonl"
  touch -d '2026-10-15T04:00:00-04:00' "$P/memory/$E.jsonl" "$P/proj/$E/subagents/agent-1.jsonl"
  run find_sessions "$STOP" "$P"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | cut -f1)" "$(printf '%s\n%s' "$B" "$C")"
}

# bats test_tags=feature:restore-sessions
@test "find-sessions leaves out a session closed with /exit but keeps one resumed after it" {
  session "$A" closed 04:50:00 end=exit
  session "$B" again 04:51:00 end=resumed
  run find_sessions "$STOP" "$P"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | cut -f1)" "$B"
}

# bats test_tags=feature:restore-sessions
@test "find-sessions says mid-task for an unfinished tool call, tool result, thinking or API error only" {
  session "$A" a 04:50:01 end=tool_use
  session "$B" b 04:50:02 end=tool_result
  session "$C" c 04:50:03 end=thinking
  session "$D" d 04:50:04 end=api_error
  session "$E" e 04:50:05 end=text
  run find_sessions "$STOP" "$P"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | cut -f6 | tr '\n' ' ')" "yes yes yes yes no "
}

# bats test_tags=feature:restore-sessions
@test "find-sessions adds an idle session whose process file survived the stop" {
  session "$A" idle 01:00:00
  session "$B" before 01:00:00
  mkdir -p "$BATS_TEST_TMPDIR/sessions"
  printf '{"pid":999999001,"sessionId":"%s","kind":"interactive","procStart":"1"}' "$A" > "$BATS_TEST_TMPDIR/sessions/1.json"
  printf '{"pid":999999002,"sessionId":"%s","kind":"interactive","procStart":"1"}' "$B" > "$BATS_TEST_TMPDIR/sessions/2.json"
  touch -d '2026-10-15T01:00:00-04:00' "$BATS_TEST_TMPDIR/sessions/1.json"
  touch -d '2026-10-13T01:00:00-04:00' "$BATS_TEST_TMPDIR/sessions/2.json"
  RS_SESSIONS="$BATS_TEST_TMPDIR/sessions" run find_sessions "$STOP" "$P"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | cut -f1,9)" "$(printf '%s\topen at stop' "$A")"
}

# bats test_tags=feature:restore-sessions
@test "find-sessions leaves out a headless session's surviving process file" {
  session "$A" idle 01:00:00
  session "$B" robot 01:00:00
  mkdir -p "$BATS_TEST_TMPDIR/sessions"
  printf '{"pid":999999001,"sessionId":"%s","kind":"interactive","procStart":"1"}' "$A" > "$BATS_TEST_TMPDIR/sessions/1.json"
  printf '{"pid":999999002,"sessionId":"%s","kind":"headless","procStart":"1"}' "$B" > "$BATS_TEST_TMPDIR/sessions/2.json"
  touch -d '2026-10-15T01:00:00-04:00' "$BATS_TEST_TMPDIR/sessions/1.json" "$BATS_TEST_TMPDIR/sessions/2.json"
  RS_SESSIONS="$BATS_TEST_TMPDIR/sessions" run find_sessions "$STOP" "$P"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | cut -f1)" "$A"
}

# bats test_tags=feature:restore-sessions
@test "find-sessions leaves out a process file whose process is still alive" {
  [ -r /proc/self/stat ] || skip "this system has no /proc, which is how a live process is recognised"
  session "$A" idle 01:00:00
  session "$B" open 01:00:00
  mkdir -p "$BATS_TEST_TMPDIR/sessions"
  started="$(python3 -c 'import sys; print(open("/proc/%s/stat" % sys.argv[1]).read().rsplit(")", 1)[1].split()[19])' "$$")"
  printf '{"pid":999999001,"sessionId":"%s","kind":"interactive","procStart":"1"}' "$A" > "$BATS_TEST_TMPDIR/sessions/1.json"
  printf '{"pid":%s,"sessionId":"%s","kind":"interactive","procStart":"%s"}' "$$" "$B" "$started" > "$BATS_TEST_TMPDIR/sessions/2.json"
  touch -d '2026-10-15T01:00:00-04:00' "$BATS_TEST_TMPDIR/sessions/1.json" "$BATS_TEST_TMPDIR/sessions/2.json"
  RS_SESSIONS="$BATS_TEST_TMPDIR/sessions" run find_sessions "$STOP" "$P"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | cut -f1)" "$A"
}

# bats test_tags=feature:restore-sessions
@test "find-sessions explains a missing time, an unreadable time and a missing folder" {
  run find_sessions
  assert_failure 2
  assert_output --partial "usage: find-sessions.sh <stop-time>"
  run find_sessions "not a time" "$P"
  assert_failure 2
  assert_output --partial "find-sessions: cannot read stop time: not a time"
  run find_sessions "$STOP" "$BATS_TEST_TMPDIR/nowhere"
  assert_failure 2
  assert_output --partial "find-sessions: no such projects dir"
}

# bats test_tags=feature:restore-sessions
@test "stop-time formats a time the user gives and refuses one it cannot read" {
  run bash "$S/stop-time.sh" "2026-10-15 04:56:11"
  assert_success
  assert_output "$(printf 'stop\tThu 2026-10-15 04:56:11 EDT')"
  run bash "$S/stop-time.sh" "whenever"
  assert_failure 1
  assert_output --partial "no stop time: cannot read 'whenever'"
}

# bats test_tags=feature:restore-sessions
@test "stop-time reads the stop, this boot and the previous boot from the journal" {
  {
    echo "IDX BOOT ID FIRST ENTRY LAST ENTRY"
    echo " -1 1111 Wed 2026-10-14 09:00:00 EDT Thu 2026-10-15 04:56:11 EDT"
    echo "  0 2222 Thu 2026-10-15 08:30:00 EDT Thu 2026-10-15 09:00:00 EDT"
  } > "$FAKE_BOOTS"
  run bash "$S/stop-time.sh"
  assert_success
  assert_output "$(printf 'stop\tThu 2026-10-15 04:56:11 EDT\nboot\tThu 2026-10-15 08:30:00 EDT\nprev\tWed 2026-10-14 09:00:00 EDT')"
}

# bats test_tags=feature:restore-sessions
@test "stop-time says why when the journal fails or holds no previous boot" {
  run bash "$S/stop-time.sh"
  assert_failure 1
  assert_output --partial "no stop time: journalctl --list-boots failed"
  echo "  0 2222 Thu 2026-10-15 08:30:00 EDT Thu 2026-10-15 09:00:00 EDT" > "$FAKE_BOOTS"
  run bash "$S/stop-time.sh"
  assert_failure 1
  assert_output --partial "no stop time: no previous boot (-1)"
}

# bats test_tags=feature:restore-sessions
@test "plan with no tmux server opens new session 0 with a pet top-left and the sessions beside it" {
  session "$A" alpha 04:50:00 end=tool_use
  session "$B" beta 04:51:00 agent=planner mode=plan
  candidates
  RS_SEED=1 run plan --stop "$STOP"
  assert_success
  assert_output --partial "| 0:1.2 | $A | ${T}/work/alpha | worker | sonnet-5-5 | auto | yes |"
  assert_output --partial "| 0:1.3 | $B | ${T}/work/beta | planner | sonnet-5-5 | plan | no |"
  assert_output --regexp "\| 0:1\.1 \| pet: (squid|dog|cat) \(new pane\)"
  assert_output --partial "New tmux sessions (each gets a new Windows Terminal window): 0"
  assert_equal "$(cat "$OUT/before.txt")" "(no tmux server running)"
  assert_equal "$(cut -f1 "$OUT/ops.tsv" | tr '\n' ' ')" \
    "new-session first-pane split split layout pet resume resume wt show "
  assert_equal "$(grep '^resume' "$OUT/ops.tsv" | cut -f4,5,6 | head -1)" \
    "$(printf '%s\t%s\tclaude-sonnet-5-5' "$WORK/alpha" "$A")"
}

# bats test_tags=feature:restore-sessions
@test "plan reuses an idle shell, leaves a busy pane alone and never changes tmux" {
  pane 0 1 1 %1 terminal-pet 999999001
  pane 0 1 2 %2 vim 999999002
  pane 0 1 3 %3 bash 999999003
  session "$A" alpha 04:50:00
  candidates
  run plan
  assert_success
  assert_output --partial "| 0:1.1 | pet: squid (existing pet)"
  assert_output --partial "| 0:1.3 | $A |"
  assert_output --partial "Idle shell panes reused (nothing running in them now): 0:1.3"
  assert_equal "$(grep '^resume' "$OUT/ops.tsv" | cut -f3)" "%3"
  run grep -Ev '^(list-panes|show) ' "$FAKE_TMUX_DIR/calls.log"
  assert_output ""
}

# bats test_tags=feature:restore-sessions
@test "plan does not reuse a shell pane that has a program running under it" {
  pane 0 1 1 %1 terminal-pet 999999001
  pane 0 1 2 %2 bash 999999002
  pane 0 1 3 %3 bash 999999003
  echo "python3 long-job.py" > "$FAKE_TMUX_DIR/kids/999999002"
  session "$A" alpha 04:50:00
  candidates
  run plan
  assert_success
  assert_output --partial "| 0:1.3 | $A |"
  assert_output --partial "Idle shell panes reused (nothing running in them now): 0:1.3"
  assert_equal "$(grep '^resume' "$OUT/ops.tsv" | cut -f3)" "%3"
}

# bats test_tags=feature:restore-sessions
@test "plan opens a second window once the first holds a pet and three sessions" {
  session "$A" a 04:50:01
  session "$B" b 04:50:02
  session "$C" c 04:50:03
  session "$D" d 04:50:04
  pane 0 1 1 %1 terminal-pet 999999001
  pane 1 1 1 %5 terminal-pet 999999005
  pane 1 1 2 %6 vim 999999006
  pane 1 1 3 %7 vim 999999007
  pane 1 1 4 %8 vim 999999008
  candidates
  run plan
  assert_success
  assert_output --partial "| 0:1.4 | $C |"
  assert_output --partial "| 1:2.2 | $D |"
  assert_output --partial "New tmux windows: 1:2"
}

# bats test_tags=feature:restore-sessions
@test "plan leaves out headless, empty, temporary, older, vanished and already running sessions and says why" {
  session "$A" app 04:50:01
  session "$B" app 04:50:02
  session "$C" robot 04:50:03 entry=sdk-cli
  session "$D" blank 04:50:04 replies=0
  session "$E" evals/one 04:50:05
  session "$F" redo 04:50:06 first=/restore-sessions
  session 11111111-0000-4000-8000-000000000007 gone 04:50:07
  session 22222222-0000-4000-8000-000000000008 busy 04:50:08
  session 33333333-0000-4000-8000-000000000009 old 01:00:00
  rm -r "$WORK/gone"
  echo "4242 claude --resume 22222222-0000-4000-8000-000000000008" > "$FAKE_PROCS"
  candidates
  run plan --stop "$STOP" --prev "2026-10-14 09:00:00"
  assert_success
  assert_output --partial "- aaaaaaaa ${T}/work/app: older session in ${T}/work/app (newest there: bbbbbbbb)"
  assert_output --partial "- cccccccc ${T}/work/robot: headless run (claude -p, entrypoint sdk-cli)"
  assert_output --partial "- dddddddd ${T}/work/blank: empty: no Claude reply in it"
  assert_output --partial "- eeeeeeee ${T}/work/evals/one: test/temporary folder (evals/ in its path)"
  assert_output --partial "- ffffffff ${T}/work/redo: a /restore-sessions run"
  assert_output --partial "- 11111111 ${T}/work/gone: cwd no longer exists"
  assert_output --partial "- 22222222 ${T}/work/busy: already running: claude --resume 22222222"
  assert_output --partial "- 33333333 ${T}/work/old: ended earlier: last write 2026-10-15 01:00:00 EDT"
  assert_equal "$(grep '^resume' "$OUT/ops.tsv" | cut -f5)" "$B"
}

# bats test_tags=feature:restore-sessions
@test "plan treats a transcript written after this boot as already running" {
  session "$A" alpha 04:50:00
  candidates
  run plan --boot "2026-10-15 04:00:00"
  assert_success
  assert_output --partial "already running: transcript written at 2026-10-15 04:50:00 EDT, after this boot started"
  assert_output --partial "| (nothing to open) |"
}

# bats test_tags=feature:restore-sessions
@test "plan applies the user's corrections: drop, keep and move" {
  session "$A" alpha 04:50:01
  session "$B" beta 04:50:02
  session "$C" robot 04:50:03 entry=sdk-cli
  pane 1 1 1 %1 terminal-pet 999999001
  pane 1 1 2 %2 bash 999999002
  pane 1 1 3 %3 bash 999999003
  candidates
  run plan --fix "drop aaaaaaaa" --fix "keep cccccccc" --fix "bbbbbbbb -> 1:1.3"
  assert_success
  assert_output --partial "| 1:1.3 | $B |"
  assert_output --partial "| 0:1.2 | $C |"
  assert_output --partial "- aaaaaaaa ${T}/work/alpha: dropped by user"
  refute_output --partial "| $A |"
  refute_output --partial "headless run"
}

# bats test_tags=feature:restore-sessions
@test "plan refuses a correction it cannot apply and exits 3" {
  pane 0 1 1 %1 terminal-pet 999999001
  pane 0 1 2 %2 vim 999999002
  session "$A" alpha 04:50:01
  candidates
  run plan --fix "aaaaaaaa -> 0:1.2" --fix "drop 99999999" --fix "do something"
  assert_failure 3
  assert_output --partial "CORRECTION NOT APPLIED: 0:1.2 is busy (vim)"
  assert_output --partial "CORRECTION NOT APPLIED: 99999999: no such session in the plan"
  assert_output --partial "CORRECTION NOT APPLIED: cannot read correction: 'do something'"
}

# bats test_tags=feature:restore-sessions
@test "plan and apply say which input is missing" {
  run bash "$S/plan.sh" --out "$OUT"
  assert_failure 2
  assert_output --partial "plan.sh: --candidates FILE is required"
  run bash "$S/plan.sh" --candidates "$FX/mksession.py"
  assert_failure 2
  assert_output --partial "plan.sh: --out DIR is required"
  run bash "$S/plan.sh" --bogus
  assert_failure 2
  assert_output --partial "plan.sh: unknown argument: --bogus"
  run bash "$S/apply.sh" "$BATS_TEST_TMPDIR"
  assert_failure 2
  assert_output --partial "ops.tsv (run plan.sh first)"
}

# a finished apply.sh run, as verify.sh reads it: one pet pane and one resumed pane showing agent $1
applied() {
  mkdir -p "$OUT"
  export RS_TMUX_L=fake LC_ALL=en_US.UTF-8
  pane 0 1 1 %1 terminal-pet 999999001
  pane 0 1 2 %2 claude 999999002
  {
    printf '0:1.1\tpet\tnew pane\tnew:1\t\t\t\t\t\t\tdog\t\n'
    printf '0:1.2\tclaude\tnew pane\tnew:2\t%s\t%s\tworker\tclaude-sonnet-5-5\tauto\tyes\t\t\n' "$A" "$WORK/alpha"
  } > "$OUT/plan.tsv"
  printf 'new:1\t%%1\t0:1.1\t0:1.1\nnew:2\t%%2\t0:1.2\t0:1.2\n' > "$OUT/panes-final.tsv"
  echo "pet" > "$FAKE_TMUX_DIR/cap/%1"
  printf '──────── %s ──\n❯ \n  auto mode on   Sonnet 5.5\n' "$1" > "$FAKE_TMUX_DIR/cap/%2"
  echo "\$ cd '$WORK/alpha' && claude --resume $A --model claude-sonnet-5-5" > "$FAKE_TMUX_DIR/cap-shell/%2"
}

# bats test_tags=feature:restore-sessions
@test "verify passes a resumed pane with the right prompt, agent, mode and model" {
  applied worker
  run bash "$S/verify.sh" "$OUT" --no-wait --no-screenshot
  assert_success
  assert_output --partial "PASS 0:1.1 pet dog: pane runs terminal-pet"
  assert_output --partial "PASS 0:1.2 claude aaaaaaaa: prompt shown; agent worker; mode auto; model Sonnet 5.5"
  refute_output --partial "FAIL"
  assert_equal "$(grep -c 'PASS ' "$OUT/report.md" | tr -d ' ')" "2"
}

# bats test_tags=feature:restore-sessions
@test "verify fails a pane that came back with a different agent" {
  applied planner
  run bash "$S/verify.sh" "$OUT" --no-wait --no-screenshot
  assert_output --partial "FAIL 0:1.2 claude aaaaaaaa: agent: expected worker, shows planner"
  assert_output --partial "PASS 0:1.1 pet dog"
}

# verify_says <pane> <what is wrong>: verify.sh reports that failure for that pane
verify_says() {
  run bash "$S/verify.sh" "$OUT" --no-wait --no-screenshot
  assert_a_line_matches "^- FAIL $1 .*$2"
}
screen() { printf '──────── worker ──\n%s\n  %s\n' "$1" "$2" > "$FAKE_TMUX_DIR/cap/%2"; }

# bats test_tags=feature:restore-sessions
@test "verify fails a pane with no Claude prompt, typed input, or a trust question" {
  applied worker
  printf 'still loading\n' > "$FAKE_TMUX_DIR/cap/%2"
  verify_says 0:1.2 "no Claude prompt"
  screen '❯ half a message' 'auto mode on   Sonnet 5.5'
  verify_says 0:1.2 "input box is not empty"
  screen '❯ ' 'auto mode on   Sonnet 5.5'
  printf 'Do you trust this folder?\n' >> "$FAKE_TMUX_DIR/cap/%2"
  verify_says 0:1.2 "Claude is asking whether to trust"
}

# bats test_tags=feature:restore-sessions
@test "verify fails a pane that came back in another mode or model" {
  applied worker
  screen '❯ ' 'plan mode on   Sonnet 5.5'
  verify_says 0:1.2 "mode: expected auto, shows plan"
  screen '❯ ' 'auto mode on   Opus 5.5'
  verify_says 0:1.2 "model: expected Sonnet 5.5, shows Opus 5.5"
}

# bats test_tags=feature:restore-sessions
@test "verify fails a pane whose resume line is missing or was typed over, or whose session was not found" {
  applied worker
  echo '$ ls' > "$FAKE_TMUX_DIR/cap-shell/%2"
  verify_says 0:1.2 "resume line not found on the shell screen"
  applied_line="\$ cd '$WORK/alpha' && claude --resume $A --model claude-sonnet-5-5"
  printf '%s\n$ echo typed-later\n' "$applied_line" > "$FAKE_TMUX_DIR/cap-shell/%2"
  verify_says 0:1.2 "more input after the resume line"
  printf '%s\n' "$applied_line" > "$FAKE_TMUX_DIR/cap-shell/%2"
  screen 'No conversation found with session ID' 'auto mode on'
  verify_says 0:1.2 "claude says the session was not found"
}

# bats test_tags=feature:restore-sessions
@test "verify fails a pet pane that is not running the pet" {
  applied worker
  sed 's/terminal-pet/bash/' "$FAKE_TMUX_DIR/panes" > "$FAKE_TMUX_DIR/panes.new"
  mv "$FAKE_TMUX_DIR/panes.new" "$FAKE_TMUX_DIR/panes"
  verify_says 0:1.1 "pane runs bash"
}

# apply.sh uses associative arrays; prints the first bash found that has them
newer_bash() {
  local b
  for b in "$(command -v bash)" /opt/homebrew/bin/bash /usr/local/bin/bash /bin/bash; do
    [ -x "$b" ] && "$b" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' && { echo "$b"; return 0; }
  done
  return 1
}

# bats test_tags=feature:restore-sessions
@test "apply resumes each session with the model it was using" {
  local b
  b="$(newer_bash)" || skip "apply.sh needs bash 4 or newer and this system has only an older one"
  mkdir -p "$OUT" "$WORK/alpha"
  pane 0 0 0 %0 bash 100
  echo '$ ' > "$FAKE_TMUX_DIR/cap/%0"
  printf 'resume\t0:0\t%%0\t%s\t%s\tclaude-sonnet-5-5\n' "$WORK/alpha" "$A" > "$OUT/ops.tsv"
  : > "$OUT/plan.tsv"
  RS_NO_WT=1 run "$b" "$S/apply.sh" "$OUT"
  assert_success
  run grep -F "claude --resume $A" "$FAKE_TMUX_DIR/calls.log"
  assert_output --partial "cd '$WORK/alpha' && claude --resume $A --model claude-sonnet-5-5"
}
