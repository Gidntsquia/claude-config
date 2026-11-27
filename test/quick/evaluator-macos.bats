#!/usr/bin/env bats
# The macOS window tools (local-tools/macos) with stand-ins for Firefox, tmux and `open`: what is opened for each
# kind of item, what is closed, what happens when Firefox is missing or dies, and what ending a run leaves.

load ../helpers/common
load ../helpers/evaluator-tools

setup() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) skip "the macOS window tools need tmux and process tools Windows Git Bash lacks";; esac
  evt_setup
  M="$LT/macos"
  cp -R "$EVT_FIX/Firefox.app" "$W/Firefox.app"
  FFBIN="$W/Firefox.app/Contents/MacOS/firefox"
  export EVSHOW_STATE="$W/state" EVSHOW_TOOLS="$T" EVSHOW_TMUX="$EVT_FIX/tmux-stub.sh" EVSHOW_OPEN="$EVT_FIX/open-stub.sh"
  export EVSHOW_FIREFOX_APP="$W/Firefox.app" TMUX_LOG="$W/tmux.log" FF_LOG="$W/ff.log" OPEN_LOG="$W/open.log" TMUX_PANE=%7
  unset FF_DIE FF_SLOW TMUX_FAIL OPEN_FAIL
  mkdir -p "$EVSHOW_STATE"
  : > "$TMUX_LOG"; : > "$FF_LOG"; : > "$OPEN_LOG"
  D="$EVSHOW_STATE"
}

teardown() {
  if [ -n "${W:-}" ] && [ -x "${T:-/nonexistent}/evshow.sh" ] && [ -f "$W/state/log" ]; then evt "$T/evshow.sh" disarm >/dev/null 2>&1; fi
  evt_cleanup
}

# page <file-page.sh args>: register the page of a file; PT its title, PF the page, PO what win-app.sh printed
page() {
  local pg
  evo "$LT/common/file-page.sh" "$@"; [ "$rc" = 0 ] || return 1
  pg=${out#page: }; PT=${pg#*|}; PF=${pg%%|*}
  evo "$M/win-app.sh" --hidden --title "$PT" firefox -new-window "$PF"; PO=$out
  [ "$rc" = 0 ]
}

# the four kinds of item, registered in this order: 1001 a file, 1002 a terminal, 1003 a web address, 1004 own HTML
file_item() {
  F1="$W/notes a.txt"; printf 'line one\nline two\nline three\n' > "$F1"
  page "$F1" || return 1
  T1=$PT; P1=$PF
}
terminal_item() {
  TT="evtool-$$"
  evo "$M/term-open.sh" "$TT" "$W" 'echo hi'; [ "$rc" = 0 ]
}
web_item() {
  evo "$M/win-app.sh" --hidden --title "web k3" firefox -new-window "https://example.com/web%20k3"; [ "$rc" = 0 ]
}
own_item() {
  printf '<title>own k4</title>' > "$W/own k4.html"
  evo "$M/win-app.sh" --hidden --title "own k4" firefox "$W/own k4.html"; [ "$rc" = 0 ]
}
four_items() { file_item && terminal_item && web_item && own_item; }

item_pid() { cat "$D/item/$1.pid"; }
ff_last() { tail -n 1 "$FF_LOG"; }
died() { wait_until 5 gone "$1" || { echo "pid $1 is still running"; return 1; }; }
start1() { evo "$M/win.sh" start "$T1" 734 30 706 789 5 0 30 734 789 2222 "$W/pic.png"; }
next2() { evo "$M/win.sh" next 1001 "$TT" 734 30 706 789 5 2222 "" 0 30 734 789; }
user_process() {
  without_bats_fds bash "$EVT_FIX/user-process.sh" "$W/user.pid" >/dev/null 2>&1 &
  wait_until 10 test -s "$W/user.pid" || return 1
  USER_PID=$(cat "$W/user.pid")
}

# bats test_tags=feature:evaluator-tools
@test "registering a file item opens nothing yet and remembers the file" {
  file_item
  assert_equal "$PO" "hidden: 1001 0 0 $T1 (deferred)"
  run grep -x 'kind=file' "$D/item/1001"
  assert_success
  run grep -xF "target=$P1" "$D/item/1001"
  assert_success
}

# bats test_tags=feature:evaluator-tools
@test "registering a window without a title is refused" {
  file_item
  evo "$M/win-app.sh" --hidden firefox "$F1"
  assert_equal "$rc" 2
}

# bats test_tags=feature:evaluator-tools
@test "registering a file that does not exist says so" {
  evo "$M/win-app.sh" --hidden --title z firefox /no/such.html
  assert_equal "$rc" 1
  has "$out$(cat "$W/err")" "not hidden: no such file"
}

# bats test_tags=feature:evaluator-tools
@test "asking for a VS Code window says VS Code is retired" {
  evo "$M/win-app.sh" code x
  assert_equal "$rc" 2
  has "$out$(cat "$W/err")" "not opened: VS Code is retired"
}

# bats test_tags=feature:evaluator-tools
@test "asking for a Windows Terminal window is refused" {
  evo "$M/win-app.sh" --hidden --title z wt
  assert_equal "$rc" 2
}

# bats test_tags=feature:evaluator-tools
@test "win.sh me names the tmux pane and no window geometry" {
  evo "$M/win.sh" me
  assert_equal "$(cat "$W/out" "$W/err")" "me: %7 0 0 0 0 0"
}

# bats test_tags=feature:evaluator-tools
@test "opening a terminal item starts a tmux session and defers the window" {
  file_item
  terminal_item
  assert_equal "$out" "opened $TT id=1002 (deferred)"
  run grep -F "new-session -d -s $TT -c $W" "$TMUX_LOG"
  assert_success
}

# bats test_tags=feature:evaluator-tools
@test "nothing is opened while items are only registered" {
  four_items
  run cat "$FF_LOG" "$OPEN_LOG"
  assert_success
  assert_output ""
  [ ! -e "$D/ffprof" ]
}

# bats test_tags=feature:evaluator-tools
@test "showing the first item starts its own Firefox on a fresh profile" {
  file_item
  start1
  assert_equal "$rc" 0
  assert_equal "$(line1 "$out")" "shown: 1001 $T1 mode=firefox"
  assert_equal "$(cat "$FF_LOG")" "-new-instance -profile $D/ffprof/1001 -new-window $P1"
  alive "$(item_pid 1001)"
}

# bats test_tags=feature:evaluator-tools
@test "the shown Firefox profile has no default-browser, welcome or restore prompt" {
  file_item
  start1
  for pref in '"browser.shell.checkDefaultBrowser", false' '"browser.aboutwelcome.enabled", false' '"browser.sessionstore.resume_from_crash", false'; do
    grep -qF "$pref" "$D/ffprof/1001/user.js" || { echo "no $pref"; return 1; }
  done
}

# bats test_tags=feature:evaluator-tools
@test "showing an item takes no screenshot and does not use the default browser" {
  file_item
  start1
  assert_equal "$(line1 "$out")" "shown: 1001 $T1 mode=firefox"
  assert_file_not_exist "$W/pic.png"
  assert_equal "$(cat "$OPEN_LOG")" ""
}

# bats test_tags=feature:evaluator-tools
@test "the next item closes the previous Firefox and deletes its profile" {
  file_item; terminal_item
  start1
  old=$(item_pid 1001)
  next2
  assert_equal "$(line1 "$out")" "shown: 1002 $TT mode=firefox"
  died "$old"
  [ ! -e "$D/ffprof/1001" ]
}

# bats test_tags=feature:evaluator-tools
@test "a terminal item is shown as a page of the session's text with its colours kept" {
  file_item; terminal_item
  start1
  next2
  run grep -E "^capture-pane -e -p -S - -t =$TT:" "$TMUX_LOG"
  assert_success
  tp="$D/pages/term-1002.html"
  assert_equal "$(ff_last)" "-new-instance -profile $D/ffprof/1002 -new-window $tp"
  for want in '<span style="color:#c33">red words</span> then plain &lt;b&gt;' '<span style="color:#00ff00;font-weight:bold">bold green</span>' "<title>$TT</title>" '<header><b>terminal '; do
    grep -qF -- "$want" "$tp" || { echo "the page lacks: $want"; cat "$tp"; return 1; }
  done
}

# bats test_tags=feature:evaluator-tools
@test "a web item is shown as its own address and the terminal page's Firefox is closed" {
  four_items
  evo "$M/win.sh" show "$TT" 1 2 3 4
  old=$(item_pid 1002)
  evo "$M/win.sh" show "web k3" 1 2 3 4
  assert_equal "$(line1 "$out")" "shown: 1003 web k3 mode=firefox"
  assert_equal "$(ff_last)" "-new-instance -profile $D/ffprof/1003 -new-window https://example.com/web%20k3"
  died "$old"
}

# bats test_tags=feature:evaluator-tools
@test "your own HTML file is shown as itself, in the only Firefox of the run" {
  four_items
  evo "$M/win.sh" show "web k3" 1 2 3 4
  evo "$M/win.sh" next 1003 "own k4" 1 2 3 4 5 2222
  assert_equal "$(line1 "$out")" "shown: 1004 own k4 mode=firefox"
  assert_equal "$(ff_last)" "-new-instance -profile $D/ffprof/1004 -new-window $W/own k4.html"
  assert_equal "$(evt_ff_count "$D")" 1
  assert_equal "$(cat "$OPEN_LOG")" ""
}

# bats test_tags=feature:evaluator-tools
@test "closing the items ends their tmux session, Firefox and profiles and kills nothing of yours" {
  four_items
  evo "$M/win.sh" show "own k4" 1 2 3 4
  shown=$(item_pid 1004)
  user_process
  # a stale pid file that now names a process of yours
  echo "$USER_PID" > "$D/item/1003.pid"
  evo "$M/term-close.sh" "$TT" 1002
  run grep -E "^kill-session -t $TT" "$TMUX_LOG"
  assert_success
  evo "$M/win.sh" close 1004
  assert_equal "$out" "closed: 1004"
  died "$shown"
  evo "$M/win.sh" close-cloaked
  [ ! -e "$D/ffprof" ]
  alive "$USER_PID"
}

# bats test_tags=feature:evaluator-tools
@test "restoring the desktop on a Mac says nothing changed" {
  evo "$M/win.sh" setwin 2222 0 0 1440 900 0
  assert_equal "$out" "now unchanged"
}

# bats test_tags=feature:evaluator-tools
@test "closing a window this session did not open is refused" {
  evo "$M/win.sh" close 4242
  assert_equal "$rc" 1
  has "$out$(cat "$W/err")" "refused: window 4242 was not opened by this session"
}

# bats test_tags=feature:evaluator-tools
@test "showing an unknown item says no window matches" {
  evo "$M/win.sh" show nothing-here 1 2 3 4
  assert_equal "$rc" 1
  has "$out$(cat "$W/err")" "not shown: no window matches"
}

# bats test_tags=feature:evaluator-tools
@test "an unknown win.sh command is a usage error" {
  evo "$M/win.sh" bogus
  assert_equal "$rc" 2
}

# bats test_tags=feature:evaluator-tools
@test "the Firefox path is the program inside the app" {
  evo "$M/win-app.sh" --path firefox
  assert_equal "$out" "$W/Firefox.app/Contents/MacOS/firefox"
}

# bats test_tags=feature:evaluator-tools
@test "without Firefox installed the page opens in your default browser and says why" {
  export EVSHOW_FIREFOX_APP="$W/no-Firefox.app"
  file_item
  evo "$M/win.sh" show "$PT" 734 30 706 789
  assert_equal "$rc" 0
  assert_equal "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 3
  assert_equal "$(line1 "$out")" "firefox failed: $W/no-Firefox.app is not installed"
  assert_equal "$(printf '%s\n' "$out" | sed -n 2p)" "shown: 1001 $PT mode=browser"
  assert_equal "$(cat "$OPEN_LOG")" "$PF"
}

# bats test_tags=feature:evaluator-tools
@test "closing a page that went to your browser leaves it there" {
  export EVSHOW_FIREFOX_APP="$W/no-Firefox.app"
  file_item
  evo "$M/win.sh" show "$PT" 734 30 706 789
  evo "$M/win.sh" close 1001
  has "$out" "closed: 1001 (the page stays in your browser"
}

# bats test_tags=feature:evaluator-tools
@test "without Firefox installed the Firefox path is open" {
  export EVSHOW_FIREFOX_APP="$W/no-Firefox.app"
  evo "$M/win-app.sh" --path firefox
  assert_equal "$out" "open"
}

# bats test_tags=feature:evaluator-tools
@test "a Firefox that exits at once is reported quickly and the page opens in your browser" {
  export FF_DIE=1
  file_item
  evo "$M/win.sh" show "$PT"
  # well under the 10 s a live Firefox is given
  printf '%s\n' "$(line1 "$out")" | grep -qE '^firefox failed: Firefox \(pid [0-9]+\) exited [0-4]\.[0-9] s after its start'
  has "$out" "shown: 1001 $PT mode=browser"
  assert_equal "$(cat "$OPEN_LOG")" "$PF"
  [ ! -e "$D/ffprof/1001" ]
}

# bats test_tags=feature:evaluator-tools
@test "when neither Firefox nor your browser opens, the failure says why" {
  export FF_DIE=1 OPEN_FAIL="No application knows how to open it"
  file_item
  evo "$M/win.sh" show "$PT"
  assert_equal "$rc" 1
  assert_equal "$(printf '%s\n' "$out" | tail -n 1)" "not shown: open: No application knows how to open it"
}

# bats test_tags=feature:evaluator-tools
@test "a Firefox still running 10 seconds after its start counts as shown" {
  export FF_SLOW=1
  file_item
  t0=$SECONDS
  evo "$M/win.sh" show "$PT"
  took=$((SECONDS - t0))
  assert_equal "$(line1 "$out")" "shown: 1001 $PT mode=firefox"
  [ "$took" -ge 9 ] || { echo "printed after $took s"; return 1; }
  alive "$(item_pid 1001)"
}

# bats test_tags=feature:evaluator-tools
@test "a terminal item whose session is gone is not shown and says what tmux said" {
  export TMUX_FAIL="can't find session: gone"
  evo "$M/term-open.sh" "gone-$$" "$W"
  evo "$M/win.sh" show "gone-$$"
  assert_equal "$rc" 1
  has "$out$(cat "$W/err")" "not shown: tmux: can't find session: gone"
  assert_equal "$(cat "$FF_LOG")" ""
}

# bats test_tags=feature:evaluator-tools
@test "screen capture on a Mac says it did not capture" {
  evo "$M/screen-capture.sh" x
  assert_equal "$rc" 1
  has "$out$(cat "$W/err")" "not captured: "
}

# bats test_tags=feature:evaluator-tools
@test "a whole run on the Mac tools shows two items one after the other and ends with no Firefox left" {
  export EVSHOW_TRANSCRIPTS="$D/tr" EVSHOW_OS=mac
  mkdir -p "$D/tr"; TR="$D/tr/s.jsonl"; : > "$TR"
  user_process
  printf 'a\n' > "$W/a.txt"; printf 'b\n' > "$W/b.txt"
  page "$W/a.txt"; a=$PT
  page "$W/b.txt"; b=$PT
  evo "$T/evshow.sh" arm first "$a" "$b"; assert_equal "$rc" 0
  evt_question q0 first "$TR" "$D"
  evt_answer q0 Yes "$TR"
  wait_until 30 test -e "$D/done"
  evo "$T/evshow.sh" wait 20
  has "$out" "shown: 1001 $a"
  has "$out" "fired-by watcher"
  evt_question q1 next "$TR" "$D"
  evt_answer q1 Works "$TR"
  wait_until 30 test -e "$D/done"
  evo "$T/evshow.sh" wait 20
  has "$out" "shown: 1002 $b mode=firefox"
  second=$(item_pid 1002)
  alive "$second"
  evo "$T/evshow.sh" end
  has "$out" "now unchanged"
  died "$second"
  [ ! -e "$D/ffprof" ]
  assert_equal "$(evt_ff_count "$D")" 0
  evo "$T/evshow.sh" path shown
  assert_equal "$out" "no picture (macOS)"
  alive "$USER_PID"
}

watcher_judged() { grep -qE 'watcher: (answer was not Yes|answer seen)' "$D/log"; }

# bats test_tags=feature:evaluator-tools
@test "an answer other than Yes to the readiness question shows nothing" {
  export EVSHOW_TRANSCRIPTS="$D/tr" EVSHOW_WIN="$EVT_FIX/win-stub.sh" EVSHOW_OS=mac
  mkdir -p "$D/tr"; : > "$D/tr/s.jsonl"
  evo "$T/evshow.sh" arm first "item-a x1" "item-b x2"
  assert_equal "$rc" 0
  evt_question q1 first "$D/tr/s.jsonl" "$D"
  evt_answer q1 "Not yet" "$D/tr/s.jsonl"
  wait_until 20 watcher_judged
  run cat "$D/log"
  assert_output --partial "watcher: answer was not Yes"
  assert_file_not_exist "$D/answer"
  run cat "$D/calls"
  refute_output --partial "start"
}

# bats test_tags=feature:evaluator-tools
@test "the page of a line range starts with the first line asked for" {
  printf 'line one\nline two\nline three\nline four\nline five\n' > "$W/five.txt"
  evo "$LT/common/file-page.sh" "$W/five.txt" 2-4
  assert_equal "$rc" 0
  local pg=${out#page: }
  run cat "${pg%%|*}"
  assert_output --partial '<span class="note">lines 2-4</span>'
  assert_output --partial '<span class="n">2</span>line two'
  assert_output --partial '<span class="n">4</span>line four'
  refute_output --partial 'line one'
  refute_output --partial 'line five'
}
