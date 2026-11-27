#!/usr/bin/env bats
# One whole run of evshow.sh with two things to show: the user says they are ready, answers about the first, and
# the evaluator ends the run. The window tool is a stand-in that records its calls. The run happens once, in
# setup_file; the tests read what it left.

load ../helpers/common
load ../helpers/evaluator-tools

setup_file() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0;; esac
  BATS_TEST_TMPDIR="$BATS_FILE_TMPDIR" evt_setup
  local S="$W/state" TR="$W/state/tr/s.jsonl"
  mkdir -p "$S/tr"; : > "$TR"
  export EVSHOW_STATE="$S" EVSHOW_TRANSCRIPTS="$S/tr" EVSHOW_TOOLS="$T" EVSHOW_WIN="$EVT_FIX/win-stub.sh" EVSHOW_OS=mac
  # step <name> <command...>: its output in $S/<name>.out, its exit status in $S/<name>.rc
  step() { local n="$1"; shift; local r=0; without_bats_fds "$@" >"$S/$n.out" 2>&1 || r=$?; echo "$r" > "$S/$n.rc"; }

  step arm evt "$T/evshow.sh" arm first "item-a x1" "item-b x2"
  step q0 evt_question q0 first "$TR" "$S"
  evt_answer q0 Yes "$TR"
  step fired0 wait_until 30 test -e "$S/done"
  step wait0 evt "$T/evshow.sh" wait 20
  step q1 evt_question q1 next "$TR" "$S"
  evt_answer q1 Works "$TR"
  step fired1 wait_until 30 test -e "$S/done"
  step wait1 evt "$T/evshow.sh" wait 20
  step end evt "$T/evshow.sh" end
  step noflash evt "$T/evshow.sh" noflash
  step path evt "$T/evshow.sh" path shown
  step history evt "$T/evshow.sh" history
  step disarm evt "$T/evshow.sh" disarm
  export EVT_W="$W" EVT_S="$S"
}

teardown_file() {
  W="${EVT_W:-}" evt_cleanup
}

setup() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) skip "the evaluator's readiness watcher needs tools Windows Git Bash lacks";; esac
  temp_home
  S="$EVT_S"
}

# ran <name>: that step of the run exited 0; leaves its output in $out
ran() {
  out=$(cat "$S/$1.out")
  printf '%s -> %s\n%s\n' "$1" "$(cat "$S/$1.rc")" "$out"
  [ "$(cat "$S/$1.rc")" = 0 ]
}
calls() { cat "$S/calls"; }

# bats test_tags=feature:evaluator-tools
@test "arming for the first question names the first item" {
  ran arm
  has "$out" "armed first 'item-a x1'"
}

# bats test_tags=feature:evaluator-tools
@test "after the Yes answer the first item is shown in Firefox mode" {
  ran q0; ran fired0; ran wait0
  has "$out" "shown: 1001 item-a x1 mode=firefox"
}

# bats test_tags=feature:evaluator-tools
@test "the time from question to window is logged" {
  ran wait0
  has "$out" "elapsed "
}

# bats test_tags=feature:evaluator-tools
@test "the first item is opened by the watcher, not by the wait fallback" {
  ran wait0
  has "$out" "fired-by watcher"
}

# bats test_tags=feature:evaluator-tools
@test "showing the first item arms the next one" {
  ran wait0
  has "$out" "item 1 of 2 shown (id 1001); next item 2 armed"
}

# bats test_tags=feature:evaluator-tools
@test "on a Mac no screenshot is named in the log" {
  ran wait0
  lacks "$out" "shown.png"
  lacks "$out" "gate.png"
}

# bats test_tags=feature:evaluator-tools
@test "the window tool is asked to start the first item with no window sizes" {
  ran wait0
  run grep -E '^start item-a x1 0 0 0 0 5 0 0 0 0 ' "$S/calls"
  assert_success
}

# bats test_tags=feature:evaluator-tools
@test "after the first answer the second item is shown and called the last" {
  ran q1; ran fired1; ran wait1
  has "$out" "shown: 1002 item-b x2 mode=firefox"
  has "$out" "LAST item"
}

# bats test_tags=feature:evaluator-tools
@test "the second item replaces the first item's window" {
  ran wait1
  run grep -E '^next 1001 item-b x2 ' "$S/calls"
  assert_success
}

# bats test_tags=feature:evaluator-tools
@test "ending the run closes the last item's window, says nothing on the desktop changed, and disarming succeeds" {
  ran end
  has "$out" "now unchanged"
  run grep -E '^close 1002' "$S/calls"
  assert_success
  ran disarm
}

# bats test_tags=feature:evaluator-tools
@test "on a Mac the run never moves, measures or quits a window" {
  ran end
  has "$(calls)" "start item-a x1"
  run grep -E '^geom|^setwin|^quit|^place|zlog|^gate' "$S/calls"
  assert_failure 1
}

# bats test_tags=feature:evaluator-tools
@test "on a Mac the flash measurement says it is not measured and the picture path says there is no picture" {
  ran noflash
  has "$out" "no-flash: not measured (macOS)"
  ran path
  assert_equal "$out" "no picture (macOS)"
}

# bats test_tags=feature:evaluator-tools
@test "the history keeps both items and the time from answer to next question" {
  ran history
  has "$out" "shown -> question"
  has "$out" "shown: 1001 item-a x1 mode=firefox"
  has "$out" "shown: 1002 item-b x2 mode=firefox"
}

# bats test_tags=feature:evaluator-tools
@test "evshow.sh says it has no window tools on an unsupported system" {
  mkdir "$BATS_TEST_TMPDIR/s"
  EVSHOW_STATE="$BATS_TEST_TMPDIR/s" EVSHOW_OS=other EVSHOW_TOOLS="$EVT_W/tools" EVSHOW_WIN= \
    run evt "$EVT_W/tools/evshow.sh" status
  assert_output --partial "no window tools for this OS"
}
