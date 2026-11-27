#!/usr/bin/env bats
# The Mac phone picture tool when it gets no picture: Firefox missing, or a Firefox that never opens its port.
# Real pictures are in test/machine/evaluator-phone.bats.

load ../helpers/common
load ../helpers/evaluator-tools

setup() {
  [ "$(uname -s)" = Darwin ] || skip "macOS only: elsewhere phone-shot.sh takes its picture with Node, not Firefox"
  evt_setup
  cp -R "$EVT_FIX/Firefox.app" "$W/Firefox.app"
  PH="$W/ph"; mkdir "$PH"
  printf '<title>own k4</title>' > "$W/own k4.html"
  export TMPDIR="$W/tmp" FF_LOG="$W/phone.ff" PHONE_PORT_WAIT=3
  unset FF_DIE FF_SLOW
}

teardown() { evt_cleanup; }

none_running() { ! pgrep -f -- "$(evt_re "$W/tmp/phone-ff-")" >/dev/null; }

# bats test_tags=feature:evaluator-tools
@test "a Firefox that never opens its port means no picture, no file and no process left" {
  export PHONE_FIREFOX_APP="$W/Firefox.app"
  evo "$LT/common/phone-shot.sh" "$PH/09-stand" html "$W/own k4.html"
  assert_equal "$rc" 1
  case "$out$(cat "$W/err")" in
    "phone-shot.sh: no picture: port "*" did not answer in 3 s"*) ;;
    *) return 1;;
  esac
  run ls "$PH"
  assert_output ""
  # it was started, headless, on a scratch profile and a port of its own
  run grep -e '--headless --remote-debugging-port=[0-9]* -new-instance -profile ' "$FF_LOG"
  assert_success
  wait_until 5 none_running
}

# bats test_tags=feature:evaluator-tools
@test "a phone picture without Firefox installed says it is not installed" {
  export PHONE_FIREFOX_APP="$W/no-Firefox.app"
  evo "$LT/common/phone-shot.sh" "$PH/10-none" html "$W/own k4.html"
  assert_equal "$rc" 1
  assert_equal "$(cat "$W/out" "$W/err")" "phone-shot.sh: no picture: $W/no-Firefox.app is not installed"
}
