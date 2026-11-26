#!/bin/bash
# macOS window helper of the evaluator. Same subcommands, output-line prefixes and exit codes (1 failed, 2 usage) as the WSL
# win.sh; a window id stands where HWND does (see maclib.sh: the id is this session's number for the item).
#   win.sh me                           -> YOUR terminal: the iTerm2 (else Terminal) window whose session tty is this tmux client's
#                                          tty (#{client_tty}; outside tmux: the tty of the nearest ancestor process). Saves it for the
#                                          watcher; prints "me: <id> L T W H MAX"; none: exit 1 "not found: 0 windows hold <tty>"
#   win.sh show "<title>" X Y W H [s]   -> opens the recorded item whose title holds <title> (the openers only record it), waits for its
#                                          window, places it, gives the keyboard back to the terminal;
#                                          prints "shown: <id> <title> L T W H"; exit 1 "not shown: <cause>"
#   win.sh start "<title>" X Y W H s TX TY TW TH <term id> [picture.png]   -> place the terminal, then show (evshow.sh, first item)
#   win.sh next <old id> "<title>" X Y W H s <term id> [picture.png] [TX TY TW TH] -> show, then close the old item (evshow.sh)
#   win.sh front|untop|close <id>       -> raise / nothing to undo / close (close exits 1 if the window is gone)
#   win.sh place <id> X Y W H           -> move and size, no focus;  win.sh rect <id> -> "L T W H"
#   win.sh find "<title>"               -> "<id> <title>" of exactly ONE item of this session; else exit 1 "not found: N windows hold ..."
#   win.sh setwin <id> L T W H MAX      -> put the terminal back; prints "now L T W H MAX"; exit 1 if gone
#   win.sh geom                         -> "term X Y W H" and "item X Y W H": terminal = left 51% of the main display below the menu
#                                          bar, item = the rest
#   win.sh close-cloaked ["<title>"]    -> forget every item (only those under <title>) that was recorded and never shown
#   win.sh list-topmost                 -> nothing (macOS has no always-on-top flag)
#   win.sh quit                         -> kill this run's Firefox by pid and remove its profile (evshow.sh end)
# Web items open in ONE Firefox per run: firefox -new-instance -profile <state>/ff (first-run pages off). Without
# /Applications/Firefox.app: Safari, with the line "browser: Safari (Firefox recommended: full features)".
# The picture (start/next with a path) is a headless-Firefox screenshot of the item at its shown size; a terminal item's
# picture is its `tmux capture-pane` text through file-page.sh. Any osascript failure is ONE line
# `not shown: osascript: <its text>`, exit 1.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$here/maclib.sh"
mac_state || { echo "error: no session state dir (no transcript for this cwd; set EVSHOW_STATE)"; exit 1; }

# ---- AppleScript, one app name per script (@APP@), every value through argv ---------------------------------------
S_FIND='on run argv
tell application "@APP@"
set o to ""
repeat with w in (every window whose name contains (item 1 of argv))
set o to o & (id of w) & linefeed
end repeat
return o
end tell
end run'
# Safari: only a window that holds this one page (1 tab). A page Safari put into one of the user's windows as a tab is never
# found, so it is never moved or closed.
S_FIND_SAFARI='on run argv
tell application "Safari"
set o to ""
repeat with w in (every window whose name contains (item 1 of argv))
if (count of tabs of w) is 1 then set o to o & (id of w) & linefeed
end repeat
return o
end tell
end run'
S_CLOSE_SAFARI='if (count of tabs of w) > 1 then
close current tab of w
else
close w
end if
end tell
end run'
# argv: wid, title guard ("" = none), then L T R B for place
S_HEAD='on run argv
tell application "@APP@"
set w to window id ((item 1 of argv) as integer)
if (item 2 of argv) is not "" then
if (name of w) does not contain (item 2 of argv) then error "window " & (item 1 of argv) & " no longer shows " & (item 2 of argv)
end if
'
S_RECT='set b to bounds of w
return ((item 1 of b) as text) & " " & (item 2 of b) & " " & (item 3 of b) & " " & (item 4 of b)
end tell
end run'
S_PLACE='set bounds of w to {(item 3 of argv) as integer, (item 4 of argv) as integer, (item 5 of argv) as integer, (item 6 of argv) as integer}
'
S_CLOSE='close w
end tell
end run'
S_FRONT='set index of w to 1
end tell
end run'
S_ITERM_NEW='on run argv
tell application "iTerm2"
set w to (create window with default profile command (item 1 of argv))
return id of w
end tell
end run'
S_TERMINAL_NEW='on run argv
tell application "Terminal"
set t to do script (item 1 of argv)
repeat with w in windows
try
if (selected tab of w) is t then return id of w
end try
end repeat
return id of front window
end tell
end run'
S_ME_ITERM='on run argv
tell application "iTerm2"
repeat with w in windows
repeat with tb in tabs of w
repeat with s in sessions of tb
if (tty of s) is (item 1 of argv) then
set b to bounds of w
return ((id of w) as text) & " " & (item 1 of b) & " " & (item 2 of b) & " " & (item 3 of b) & " " & (item 4 of b)
end if
end repeat
end repeat
end repeat
end tell
return ""
end run'
S_ME_TERMINAL='on run argv
tell application "Terminal"
repeat with w in windows
repeat with tb in tabs of w
if (tty of tb) is (item 1 of argv) then
set b to bounds of w
return ((id of w) as text) & " " & (item 1 of b) & " " & (item 2 of b) & " " & (item 3 of b) & " " & (item 4 of b)
end if
end repeat
end repeat
end tell
return ""
end run'
forapp() { printf '%s' "$2" | sed "s/@APP@/$1/g"; }
ltrb2ltwh() { echo "$1" | tr -d ',' | awk '{print $1, $2, $3 - $1, $4 - $2}'; }
isnum() { case "$1" in ''|*[!0-9-]*) return 1;; esac; return 0; }

# wplace <app> <wid> <guard title> X Y W H -> RECT="L T W H" as read back; 1 = OSA_ERR
wplace() {
  osa 10 "$(forapp "$1" "$S_HEAD$S_PLACE$S_RECT")" "$2" "$3" "$4" "$5" "$(($4 + $6))" "$(($5 + $7))" || return 1
  RECT=$(ltrb2ltwh "$OSA_OUT")
}
wrect() { osa 10 "$(forapp "$1" "$S_HEAD$S_RECT")" "$2" "$3" || return 1; RECT=$(ltrb2ltwh "$OSA_OUT"); }
guard_of() { case "$(iget "$1" app)" in Firefox|Safari) iget "$1" title;; *) echo "";; esac; }   # browsers: only while the name holds our title
ff_alive() { local p; p=$(cat "$D/ffpid" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }

ff_open() {  # ff_open <url>: this run's Firefox, started once; later pages open as new windows of the same instance
  if ff_alive; then "$FFBIN" -profile "$D/ff" -new-window "$1" >> "$D/ff.log" 2>&1 &
  else
    rm -rf "$D/ff"; mkdir -p "$D/ff"
    cat > "$D/ff/user.js" <<'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("app.update.auto", false);
EOF
    MOZ_DISABLE_SAFE_MODE_KEY=1 nohup "$FFBIN" -new-instance -profile "$D/ff" -new-window "$1" >> "$D/ff.log" 2>&1 &
    echo $! > "$D/ffpid"
    return 2   # cold start: the caller allows more time
  fi
}

wait_window() {  # wait_window <app> <title> <seconds> [osascript timeout, 10] -> WID; 1 = none (OSA_ERR holds a real osascript failure, else "")
  local t0=$SECONDS hard=""
  WID=""
  while :; do
    if osa "${4:-10}" "$(if [ "$1" = Safari ]; then printf '%s' "$S_FIND_SAFARI"; else forapp "$1" "$S_FIND"; fi)" "$2"; then
      WID=$(printf '%s\n' "$OSA_OUT" | grep -E '^[0-9]+$' | tail -1)
      [ -n "$WID" ] && return 0
    else
      osa_gone || { hard=$OSA_ERR; break; }   # anything but "not there yet": permission refused, no answer
    fi
    [ $((SECONDS - t0)) -ge "$3" ] && break
    sleep 0.2
  done
  OSA_ERR=$hard; return 1
}

open_web() {  # open_web <id> <title> <timeout>: 0 opened (app, wid set); 1 = a line was printed
  local id=$1 title=$2 to=$3 url
  url=$(iget "$id" target)
  if have_firefox; then
    ff_open "$url"; [ $? -eq 2 ] && to=$((to + 10))
    if ! wait_window Firefox "$title" "$to"; then
      if [ -n "$OSA_ERR" ]; then echo "not shown: osascript: $OSA_ERR"
      else echo "not shown: no window matches '$title' within ${to}s (the page <title> or the file name must hold it)"; fi
      return 1
    fi
    iset "$id" app Firefox; iset "$id" wid "$WID"; return 0
  fi
  echo "browser: Safari (Firefox recommended: full features)"
  # Safari is sandboxed: AppleScript cannot make it load a file:// page (the document stays "Untitled"), `open -a Safari`
  # can. So a file page is opened with `open`, a web URL as a new document; then the window is found by its title (a window
  # with that one tab only), placed and later closed by id. No AppleScript answer within 10 s: the page is opened the plain
  # way (if it is not yet) and the line is `shown: safari unplaced <title>`.
  local sw="${EVSHOW_SAFARI_WAIT:-10}" opened=""
  case "$url" in
    file://*) ${EVSHOW_OPEN:-open} -a Safari "$url" 2>/dev/null && opened=1 ;;
    *) osa "$sw" 'on run argv
tell application "Safari" to make new document with properties {URL:(item 1 of argv)}
end run' "$url" && opened=1 ;;
  esac
  if [ -n "$opened" ] && wait_window Safari "$title" "$to" "$sw"; then iset "$id" app Safari; iset "$id" wid "$WID"; return 0; fi
  [ -n "$opened" ] || ${EVSHOW_OPEN:-open} -a Safari "$url" 2>/dev/null
  iset "$id" app safari-unplaced; iset "$id" state shown
  echo "shown: safari unplaced $title"
  return 3
}

open_term() {  # open_term <id> <title>
  local id=$1 title=$2 app tm
  app=$(term_app); tm=$(command -v tmux || echo tmux)
  if [ "$app" = iTerm2 ]; then osa 10 "$S_ITERM_NEW" "$tm attach -t $title"
  else osa 10 "$S_TERMINAL_NEW" "$tm attach -t $title"; fi || { echo "not shown: osascript: $OSA_ERR"; return 1; }
  isnum "$OSA_OUT" || { echo "not shown: osascript: $app gave no window id ($OSA_OUT)"; return 1; }
  iset "$id" app "$app"; iset "$id" wid "$OSA_OUT"
}

do_shot() {  # do_shot <id> <png> <W> <H>: the item's picture by headless Firefox (its own scratch profile); never fails the show
  local id=$1 png=$2 w=$3 h=$4 url t out p n=0
  have_firefox || { echo "capture: none (no Firefox: Safari takes no picture)"; return 0; }
  if [ "$(iget "$id" kind)" = term ]; then
    t=$(iget "$id" title); mkdir -p "$D/pages"
    tmux capture-pane -p -t "$t" > "$D/pages/$t.txt" 2>/dev/null || { echo "capture: none (tmux session $t is gone)"; return 0; }
    out=$(FILE_PAGE_DIR="$D/pages" "$MACTOOLS/file-page.sh" "$D/pages/$t.txt")
    case "$out" in page:*) out=${out#page: }; url=$(file_url "${out%%|*}");; *) echo "capture: none ($out)"; return 0;; esac
  else url=$(iget "$id" target); fi
  rm -rf "$D/ffshot"; mkdir -p "$D/ffshot"; rm -f "$png"
  "$FFBIN" --headless -new-instance -profile "$D/ffshot" --screenshot "$png" --window-size="$w,$h" "$url" > /dev/null 2>&1 &
  p=$!
  while kill -0 "$p" 2>/dev/null; do [ "$n" -ge 200 ] && { kill "$p" 2>/dev/null; break; }; sleep 0.1; n=$((n + 1)); done
  wait "$p" 2>/dev/null; rm -rf "$D/ffshot"
  if [ -s "$png" ]; then echo "capture: $png ${w}x${h} (headless Firefox picture of the item)"
  else echo "capture: none (headless Firefox gave no picture)"; fi
}

do_close() {  # do_close <id>: 0 closed (or nothing to close), 1 gone / not ours
  local id=$1 app wid t
  if ! ihas "$id"; then
    case "$id" in ''|0|safari) return 0;; esac
    echo "refused: window $id was not opened by this session"; return 1
  fi
  case "$(iget "$id" state)" in
    deferred) iset "$id" state closed; echo "closed: $id (recorded, never opened)"; return 0;;
    closed) echo "not found: window $id is already closed"; return 1;;
  esac
  app=$(iget "$id" app); wid=$(iget "$id" wid); t=$(iget "$id" title)
  iset "$id" state closed
  case "$app" in
    safari-unplaced) echo "left open: the Safari page of $id was not placed by this session (no window of its own, or no AppleScript answer); it is yours to close"; return 0;;
    Firefox) ff_alive || { echo "not found: window $id is gone (this run's Firefox is not running)"; return 1; };;
    iTerm2|Terminal) tmux detach-client -s "$t" 2>/dev/null; sleep 0.3;;
  esac
  if osa 10 "$(forapp "$app" "$S_HEAD$([ "$app" = Safari ] && printf '%s' "$S_CLOSE_SAFARI" || printf '%s' "$S_CLOSE")")" "$wid" "$(guard_of "$id")"; then echo "closed: $id"; return 0; fi
  case "$app" in iTerm2|Terminal) osa_gone && { echo "closed: $id"; return 0; };; esac   # the window closed itself when tmux detached
  if osa_gone; then echo "not found: window $id is gone"; else echo "not closed: osascript: $OSA_ERR"; fi
  return 1
}

do_show() {  # do_show <title> X Y W H <timeout> <picture or ""> <old id to close or ""> -> 0 shown, 1 not shown
  local title=$1 x=$2 y=$3 w=$4 h=$5 to=${6:-5} cap=${7:-} old=${8:-} id front rc=0 L T W H
  id=$(ifind "$title" | head -1)
  if [ -z "$id" ]; then
    [ -n "$old" ] && do_close "$old" > /dev/null
    echo "not shown: no window matches '$title' (this session recorded no item under that title)"; return 1
  fi
  isnum "$to" || to=5; [ "$to" -ge 5 ] || to=5
  front=$(front_bundle)
  if [ "$(iget "$id" app)" = safari-unplaced ]; then echo "shown: safari unplaced $title"; return 0; fi
  if [ "$(iget "$id" state)" != shown ]; then
    if [ "$(iget "$id" kind)" = term ]; then open_term "$id" "$title"; else open_web "$id" "$title" "$to"; fi; rc=$?
  fi
  [ -n "$old" ] && [ "$old" != "$id" ] && do_close "$old" > /dev/null
  [ "$rc" -eq 3 ] && { refocus "$front"; echo "shown-at $(et)"; return 0; }   # Safari, unplaced
  [ "$rc" -ne 0 ] && { refocus "$front"; return 1; }
  if ! wplace "$(iget "$id" app)" "$(iget "$id" wid)" "$(guard_of "$id")" "$x" "$y" "$w" "$h"; then
    refocus "$front"; echo "not shown: osascript: $OSA_ERR"; return 1
  fi
  refocus "$front"
  iset "$id" state shown
  echo "shown: $id $title $RECT"; echo "shown-at $(et)"
  if [ -n "$cap" ]; then read -r L T W H <<EOF
$RECT
EOF
    do_shot "$id" "$cap" "$W" "$H"; fi
  return 0
}

place_term() {  # place_term <term id> X Y W H: 1 = a `not shown:` line was printed
  local app; app=$(cat "$D/termapp" 2>/dev/null)
  [ -n "$1" ] && [ -n "$app" ] || return 0
  wplace "$app" "$1" "" "$2" "$3" "$4" "$5" && return 0
  if osa_gone; then echo "not shown: window $1 no longer exists (the terminal)"; else echo "not shown: osascript: $OSA_ERR"; fi
  return 1
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  me)
    pane=${TMUX_PANE:-}; tty=""
    if [ -n "${TMUX:-}" ]; then tty=$(tmux display-message -p ${pane:+-t "$pane"} '#{client_tty}' 2>/dev/null); fi
    if [ -z "$tty" ]; then   # not in tmux: the tty of the nearest ancestor that has one
      pp=$$; for _ in 1 2 3 4 5 6 7 8 9 10; do
        t=$(ps -o tty= -p "$pp" 2>/dev/null | tr -d ' '); case "$t" in ''|'??'|'?') ;; *) tty="/dev/$t"; break;; esac
        pp=$(ps -o ppid= -p "$pp" 2>/dev/null | tr -d ' '); [ "${pp:-1}" -gt 1 ] 2>/dev/null || break; done
    fi
    [ -n "$tty" ] || { echo "not found: 0 windows hold this session (no tmux client and no tty)"; exit 1; }
    found=""; app=""; err=""
    for a in iTerm2 Terminal; do
      app_running "$a" || continue
      if [ "$a" = iTerm2 ]; then osa 10 "$S_ME_ITERM" "$tty"; else osa 10 "$S_ME_TERMINAL" "$tty"; fi || { err=$OSA_ERR; continue; }
      [ -n "$OSA_OUT" ] && { found=$OSA_OUT; app=$a; break; }
    done
    if [ -z "$found" ]; then
      [ -n "$err" ] && { echo "not found: osascript: $err"; exit 1; }
      echo "not found: 0 windows hold $tty (iTerm2 and Terminal windows were looked at)"; exit 1
    fi
    set -- $found
    line="$1 $(ltrb2ltwh "$2 $3 $4 $5") 0"
    echo "$line" > "$D/term"; echo "$app" > "$D/termapp"
    echo "me: $line";;
  geom) mac_geom || { echo "not shown: osascript: $OSA_ERR"; exit 1; };;
  show)
    [ $# -ge 5 ] || { echo "usage: win.sh show \"<title>\" X Y W H [timeout-s]" >&2; exit 2; }
    do_show "$1" "$2" "$3" "$4" "$5" "${6:-5}" "" "";;
  start)   # title X Y W H s TX TY TW TH term [picture]
    [ $# -ge 10 ] || { echo "usage: win.sh start \"<title>\" X Y W H s TX TY TW TH <term id> [picture.png]" >&2; exit 2; }
    place_term "${11:-}" "$7" "$8" "$9" "${10}" || exit 1
    do_show "$1" "$2" "$3" "$4" "$5" "$6" "${12:-}" "";;
  next)    # old title X Y W H s term [picture] [TX TY TW TH]
    [ $# -ge 7 ] || { echo "usage: win.sh next <old id> \"<title>\" X Y W H s <term id> [picture.png] [TX TY TW TH]" >&2; exit 2; }
    if [ $# -ge 13 ]; then place_term "${8:-}" "${10}" "${11}" "${12}" "${13}" || { do_close "$1" > /dev/null; exit 1; }; fi
    do_show "$2" "$3" "$4" "$5" "$6" "$7" "${9:-}" "$1";;
  close) [ $# -ge 1 ] || { echo "usage: win.sh close <id>" >&2; exit 2; }; do_close "$1";;
  untop) exit 0;;
  front|place|rect)
    [ $# -ge 1 ] || { echo "usage: win.sh $cmd <id> ..." >&2; exit 2; }
    ihas "$1" || { echo "refused: window $1 was not opened by this session"; exit 1; }
    [ "$(iget "$1" state)" = shown ] && isnum "$(iget "$1" wid)" || { echo "not found: window $1 is not open (state $(iget "$1" state))"; exit 1; }
    app=$(iget "$1" app); wid=$(iget "$1" wid); g=$(guard_of "$1")
    case "$cmd" in
      rect) wrect "$app" "$wid" "$g" || { echo "not found: osascript: $OSA_ERR"; exit 1; }; echo "$RECT";;
      place) [ $# -ge 5 ] || { echo "usage: win.sh place <id> X Y W H" >&2; exit 2; }
        wplace "$app" "$wid" "$g" "$2" "$3" "$4" "$5" || { echo "not shown: osascript: $OSA_ERR"; exit 1; }; echo "placed: $1 $RECT";;
      front) osa 10 "$(forapp "$app" "$S_HEAD$S_FRONT")" "$wid" "$g" || { echo "not shown: osascript: $OSA_ERR"; exit 1; }; echo "front: $1";;
    esac;;
  find)
    [ $# -ge 1 ] || { echo "usage: win.sh find \"<title>\"" >&2; exit 2; }
    ids=$(ifind "$1"); n=$(printf '%s' "$ids" | grep -c .)
    if [ "$n" -eq 1 ]; then echo "$ids $(iget "$ids" title)"; exit 0; fi
    l=""; for i in $ids; do l="$l${l:+; }$i|$(iget "$i" state)|$(iget "$i" title)"; done
    echo "not found: $n windows hold '$1'${l:+: $l}"; exit 1;;
  setwin)
    [ $# -ge 5 ] || { echo "usage: win.sh setwin <id> L T W H MAX" >&2; exit 2; }
    app=$(cat "$D/termapp" 2>/dev/null); [ -n "$app" ] || { echo "not found: no terminal saved (win.sh me)"; exit 1; }
    wplace "$app" "$1" "" "$2" "$3" "$4" "$5" || { if osa_gone; then echo "not found: window $1 no longer exists"; else echo "not shown: osascript: $OSA_ERR"; fi; exit 1; }
    echo "now $RECT ${6:-0}";;
  close-cloaked)
    for i in $(ifind "${1:-}"); do
      [ "$(iget "$i" state)" = deferred ] && { iset "$i" state closed; echo "closed: $i (recorded, never opened) $(iget "$i" title)"; }
    done; exit 0;;
  list-topmost) exit 0;;
  quit)
    p=$(cat "$D/ffpid" 2>/dev/null)
    if [ -n "$p" ]; then
      if kill "$p" 2>/dev/null; then
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$p" 2>/dev/null || break; sleep 0.2; done
        kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null
        echo "firefox: this run's instance (pid $p) ended"
      fi
      rm -f "$D/ffpid"
    fi
    rm -rf "$D/ff" "$D/ffshot"; exit 0;;
  *) sed -n '2,26p' "$0"; exit 2;;
esac
