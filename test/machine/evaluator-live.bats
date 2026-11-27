#!/usr/bin/env bats
# One real run of the evaluator on this Mac: it opens real Firefox windows, one per item, and closes them again.
# Opt in with EVSHOW_LIVE=1; it never runs otherwise. The run happens once, in setup_file, which saves what it saw
# after each step; the tests read that. Your own Firefox and the Firefox and iTerm2 window places are compared
# before and after, so do not move windows while it runs.

load ../helpers/common
load ../helpers/evaluator-tools

# why this file cannot run here; nothing when it can
live_reason() {
  if [ "${EVSHOW_LIVE:-}" != 1 ]; then echo "opens real windows: set EVSHOW_LIVE=1 to run it"
  elif [ -n "${CI:-}" ]; then echo "opens real windows: never in CI"
  elif [ "$(uname -s)" != Darwin ]; then echo "macOS only"
  elif [ ! -x /Applications/Firefox.app/Contents/MacOS/firefox ]; then echo "Firefox is not installed in /Applications"
  elif ! command -v tmux >/dev/null 2>&1; then echo "tmux is not installed"
  fi
}

# every Firefox and iTerm2 window: owner pid, name, bounds, on screen (needs no permission, reads no window content)
wins() { osascript -l JavaScript -e 'ObjC.import("CoreGraphics"); var l=ObjC.castRefToObject($.CGWindowListCopyWindowInfo(0,0)); var o=[]; for (var i=0;i<l.count;i++){ var w=l.objectAtIndex(i); var n=ObjC.unwrap(w.objectForKey("kCGWindowOwnerName")); if(n=="Firefox"||n=="iTerm2"){ var b=ObjC.deepUnwrap(w.objectForKey("kCGWindowBounds")); o.push(ObjC.unwrap(w.objectForKey("kCGWindowOwnerPID"))+" "+n+" "+b.X+","+b.Y+" "+b.Width+"x"+b.Height+" "+(ObjC.unwrap(w.objectForKey("kCGWindowIsOnscreen"))?"on":"off")); } } o.sort().join("\n")' 2>/dev/null; }
# the Firefox main processes this run started
ours() { local p n=0; for p in $(pgrep -f -- "-profile $(evt_re "$S/ffprof/")"); do case "$(ps -o comm= -p "$p" 2>/dev/null)" in */firefox) n=$((n + 1));; esac; done; echo "$n"; }
bigwin() { wins | awk -v p="$1" '$1 == p && $NF == "on" { split($4, a, "x"); if (a[1] >= 400 && a[2] >= 300) n++ } END { print n + 0 }'; }
your_firefox() { pgrep -x firefox | sort | tr '\n' ' '; }
one_window() { [ "$(ours)" = 1 ] && [ "$(bigwin "$1")" = 1 ]; }
none_ours() { [ "$(ours)" = 0 ] && [ ! -d "$S/ffprof" ]; }
your_firefox_same() { [ "$(your_firefox)" = "$(cat "$L/ff.before")" ]; }
windows_same() { [ "$(wins)" = "$(cat "$L/wins.before")" ]; }

# step <name> <command...>: its output in $L/<name>.out, its exit status in $L/<name>.rc
step() { local n="$1"; shift; local r=0; without_bats_fds "$@" >"$L/$n.out" 2>&1 || r=$?; echo "$r" > "$L/$n.rc"; }

setup_file() {
  [ -z "$(live_reason)" ] || return 0
  BATS_TEST_TMPDIR="$BATS_FILE_TMPDIR" evt_setup
  export L="$W/live" S="$W/state" EVT_W="$W"
  mkdir -p "$L" "$W/tr"
  local TR="$W/tr/live.jsonl" pg t1 TT p n
  : > "$TR"
  # the installed tools run with your real HOME
  TEST_HOME="$REAL_HOME"
  unset TMUX TMUX_PANE
  TMUX_DIR=$(mktemp -d /tmp/evt.XXXXXX)
  export TMUX_DIR TMUX_TMPDIR="$TMUX_DIR" EVSHOW_STATE="$S" EVSHOW_TRANSCRIPTS="$W/tr"
  EVT_PATH="$(dirname "$(command -v tmux)"):$REAL_HOME/.local/bin"

  your_firefox > "$L/ff.before"; wins > "$L/wins.before"
  step me evt "$T/win.sh" me
  pg=$(evt "$T/file-page.sh" "$REPO/README.md"); pg=${pg#page: }; t1=${pg#*|}
  echo "$t1" > "$L/t1"
  step hidden evt "$T/win-app.sh" --hidden --title "$t1" firefox -new-window "${pg%%|*}"
  TT="evlive-$RANDOM"; echo "$TT" > "$L/tt"
  step term evt "$T/term-open.sh" "$TT" "$REPO" "printf '\\033[31mred line of the live test\\033[0m\\n'; ls -G"
  printf '<!doctype html><title>web item evlive</title><h1>The web item of the live test</h1>' > "$W/web.html"
  step web evt "$T/win-app.sh" --hidden --title "web item evlive" firefox -new-window "$W/web.html"
  ours > "$L/ours.registered"; wins > "$L/wins.registered"

  step arm evt "$T/evshow.sh" arm first "$t1" "$TT" "web item evlive"
  for n in 1 2 3; do
    p=next; [ "$n" != 1 ] || p=first
    step "q$n" evt_question "q$n" "$p" "$TR" "$S"
    if [ "$n" = 1 ]; then evt_answer "q$n" Yes "$TR"; else evt_answer "q$n" Works "$TR"; fi
    step "wait$n" evt "$T/evshow.sh" wait 30
    p=$(cat "$S/item/100$n.pid" 2>/dev/null); echo "$p" > "$L/pid$n"
    step "window$n" wait_until 20 one_window "$p"
    echo "ours=$(ours) windows=$(bigwin "$p")" > "$L/count$n"
    if [ "$n" -gt 1 ]; then
      step "oldgone$n" wait_until 10 gone "$(cat "$L/pid$((n - 1))")"
      [ ! -d "$S/ffprof/100$((n - 1))" ]; echo "$?" > "$L/oldprof$n"
    fi
    [ "$n" != 2 ] || cp "$S/pages/term-1002.html" "$L/term.html"
  done
  step q4 evt_question q4 last "$TR" "$S"
  evt_answer q4 Works "$TR"
  step end evt "$T/evshow.sh" end
  step noneleft wait_until 10 none_ours
  step yourff wait_until 10 your_firefox_same
  step windows wait_until 10 windows_same
  step history evt "$T/evshow.sh" history
  step noflash evt "$T/evshow.sh" noflash
  step path evt "$T/evshow.sh" path shown
}

teardown_file() {
  [ -n "${EVT_W:-}" ] || return 0
  EVSHOW_STATE="$EVT_W/state" bash "$EVT_W/tools/evshow.sh" end >/dev/null 2>&1
  if [ -n "${TMUX_DIR:-}" ]; then
    TMUX_TMPDIR="$TMUX_DIR" tmux kill-server >/dev/null 2>&1
    rm -rf "$TMUX_DIR"
  fi
  W="$EVT_W" evt_cleanup
}

setup() {
  local why; why=$(live_reason)
  [ -z "$why" ] || skip "$why"
  W="$EVT_W"
}

ran() {
  out=$(cat "$L/$1.out")
  printf '%s -> %s\n%s\n' "$1" "$(cat "$L/$1.rc")" "$out"
  [ "$(cat "$L/$1.rc")" = 0 ]
}
shown_alone() { # <n>: item n has the run's only Firefox, with one window on screen
  cat "$L/count$1"
  ran "window$1"
}

# bats test_tags=feature:evaluator-tools
@test "live: win.sh me answers" {
  ran me
  has "$out" "me: "
}

# bats test_tags=feature:evaluator-tools
@test "live: registering the items opens nothing before the answer" {
  ran hidden; has "$out" "(deferred)"
  ran term; has "$out" "opened $(cat "$L/tt") id="
  ran web
  assert_equal "$(cat "$L/ours.registered")" 0
  assert_equal "$(cat "$L/wins.registered")" "$(cat "$L/wins.before")"
}

# bats test_tags=feature:evaluator-tools
@test "live: the file item opens in a separate Firefox after the answer, with one window on screen" {
  ran arm; ran q1; ran wait1
  has "$out" "shown: 1001 $(cat "$L/t1") mode=firefox"
  has "$out" "elapsed "
  shown_alone 1
}

# bats test_tags=feature:evaluator-tools
@test "live: the terminal item is shown as a page and the first item's Firefox and profile are gone" {
  ran q2; ran wait2
  has "$out" "shown: 1002 $(cat "$L/tt") mode=firefox"
  ran oldgone2
  assert_equal "$(cat "$L/oldprof2")" 0
  shown_alone 2
}

# bats test_tags=feature:evaluator-tools
@test "live: the terminal page holds the session's text with its colours kept" {
  grep -q 'red line of the live test</span>' "$L/term.html"
  grep -q '<span style="color:#c33">' "$L/term.html"
}

# bats test_tags=feature:evaluator-tools
@test "live: the web item is shown as itself and the terminal page's Firefox is gone" {
  ran q3; ran wait3
  has "$out" "shown: 1003 web item evlive mode=firefox"
  ran oldgone3
  shown_alone 3
}

# bats test_tags=feature:evaluator-tools
@test "live: ending the run leaves no Firefox or profile of its own" {
  ran q4; ran end
  has "$out" "now unchanged"
  ran noneleft
}

# bats test_tags=feature:evaluator-tools
@test "live: your own Firefox is as it was" {
  ran end; ran yourff
}

# bats test_tags=feature:evaluator-tools
@test "live: every Firefox and iTerm2 window is where it was" {
  ran end; ran windows
}

# bats test_tags=feature:evaluator-tools
@test "live: the history, flash measurement and picture path answer as on a Mac" {
  ran history
  ran noflash; has "$out" "no-flash: not measured (macOS)"
  ran path; assert_equal "$out" "no picture (macOS)"
}
