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

# bats test_tags=feature:phone-pictures
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

# bats test_tags=feature:phone-pictures
@test "a phone picture without Firefox installed says it is not installed" {
  export PHONE_FIREFOX_APP="$W/no-Firefox.app"
  evo "$LT/common/phone-shot.sh" "$PH/10-none" html "$W/own k4.html"
  assert_equal "$rc" 1
  assert_equal "$(cat "$W/out" "$W/err")" "phone-shot.sh: no picture: $W/no-Firefox.app is not installed"
}

# bats test_tags=feature:phone-pictures
@test "a picture of a line range numbers the lines as the file does" {
  # the tool beside a picture taker that keeps the page it was handed, as <out>.html
  mkdir "$W/cap"
  cp "$LT/common/phone-shot.sh" "$W/cap/"
  printf 'import shutil, sys\nshutil.copy(sys.argv[2][len("file://"):], sys.argv[1] + ".html")\n' > "$W/cap/phone-bidi.py"
  seq 101 140 > "$W/long.txt"
  evo "$W/cap/phone-shot.sh" "$PH/11-range" text "$W/long.txt" 10-12
  assert_equal "$rc" 0
  run cat "$PH/11-range.html"
  assert_output --partial "  10  110"
  assert_output --partial "  12  112"
  refute_output --partial "   1  110"
}
