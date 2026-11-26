#!/bin/bash
# macOS show helper of the evaluator. Same subcommands, output-line prefixes and exit codes (1 failed, 2 usage) as the WSL
# win.sh; a window id stands where HWND does (see maclib.sh: the id is this session's number for the item).
# Every item is shown as a PAGE IN A FIREFOX OF ITS OWN. No window is moved or sized (your terminal may be full screen and
# is never touched), no picture is taken, and X Y W H are accepted and ignored.
#   win.sh me                           -> where the evaluator runs; prints "me: <tmux pane or tty> 0 0 0 0 0"; none: exit 1 "not found: 0 windows hold ..."
#   win.sh show "<title>" X Y W H [s]   -> shows the recorded item whose title holds <title> (the openers only record it);
#                                          prints "shown: <id> <title> mode=firefox" (or mode=browser, below); exit 1 "not shown: <cause>"
#   win.sh start "<title>" X Y W H s TX TY TW TH <term id> [picture.png]   -> show (evshow.sh, first item)
#   win.sh next <old id> "<title>" X Y W H s <term id> [picture.png] [TX TY TW TH] -> close the old item, then show (evshow.sh)
#   win.sh close <id>                   -> kills the Firefox this session started for that item, deletes its profile; prints "closed: <id>"
#   win.sh find "<title>"               -> "<id> <title>" of exactly ONE item of this session; else exit 1 "not found: N windows hold ..."
#   win.sh close-cloaked ["<title>"]    -> forget every item (only those under <title>) that was recorded and never shown;
#                                          with no title also kills any Firefox of this run still alive and deletes the run's profiles
#   win.sh setwin ...                   -> prints "now unchanged" (the terminal is never moved)
#   win.sh front|untop|place|rect|geom|list-topmost|quit -> nothing to do here; exit 0
# What a show opens:
#   file page (file-page.sh)            that page
#   http(s) URL, .html file             itself
#   terminal item (term-open.sh)        a static page built at the show: the text of `tmux capture-pane -e -p -S -` on its
#                                       session, colours kept (termpage.py). It is a snapshot: it does not update.
# How: the previous item's Firefox pid is killed first; then <Firefox.app>/Contents/MacOS/firefox -new-instance
#   -profile <state>/ffprof/<id> -new-window <page>, on a fresh profile (no welcome, restore or default-browser prompt);
#   its pid is recorded in <state>/item/<id>.pid. Only a pid whose command line holds that profile path is ever killed.
# `shown: ... mode=firefox` = that Firefox is running and has written its profile's prefs.js (about 0.5 s before its
# window is drawn), or is still running 10 s after its start.
# Firefox.app absent, or its process gone within those 10 s: ONE line `firefox failed: <reason>`, then `open "<page>"`
# (your default browser; that page is never closed) and `shown: <id> <title> mode=browser`. `open` failing too:
# `not shown: open: <its text>`, exit 1.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$here/maclib.sh"
mac_state || { echo "error: no session state dir (no transcript for this cwd; set EVSHOW_STATE)"; exit 1; }

ff_pid() {  # ff_pid <id>: the recorded pid if it is still the Firefox this session started on that item's profile; else nothing
  local pid; pid=$(cat "$D/item/$1.pid" 2>/dev/null)
  case "$pid" in ''|*[!0-9]*) return 0;; esac
  ps -o command= -p "$pid" 2>/dev/null | grep -qF -- "$D/ffprof/$1" && echo "$pid"
  return 0
}
ff_kill() {  # ff_kill <id>: ends that item's Firefox (TERM, after 3 s KILL) and deletes its profile
  local pid n=0; pid=$(ff_pid "$1")
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null
    while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n + 1)); done
    kill -0 "$pid" 2>/dev/null && { kill -9 "$pid" 2>/dev/null; sleep 0.2; }
  fi
  rm -f "$D/item/$1.pid"; rm -rf "$D/ffprof/$1"
  [ "$(cat "$D/ffcur" 2>/dev/null)" = "$1" ] && rm -f "$D/ffcur"
  return 0
}
ff_open() {  # ff_open <id> <page> -> 0 = running (pid in <state>/item/<id>.pid); 1 = ERR, nothing of this try left
  local id=$1 page=$2 bin="$FF_APP/Contents/MacOS/firefox" prof="$D/ffprof/$1" pid n=0
  [ -x "$bin" ] || { ERR="$FF_APP is not installed"; return 1; }
  rm -rf "$prof"; mkdir -p "$prof" || { ERR="cannot make the profile folder $prof"; return 1; }
  cat > "$prof/user.js" <<'PREFS'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("startup.homepage_override_url", "");
user_pref("browser.startup.page", 0);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.preonboarding.enabled", false);
user_pref("termsofuse.bypassNotification", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", -1);
user_pref("toolkit.startup.max_resumed_crashes", -1);
user_pref("browser.disableResetPrompt", true);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.warnOnQuitShortcut", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("app.update.auto", false);
user_pref("app.normandy.enabled", false);
user_pref("extensions.autoDisableScopes", 0);
user_pref("signon.rememberSignons", false);
PREFS
  # started in a session of its own: it outlives this script and the shell that ran it
  pid=$(python3 -I -c 'import subprocess,sys
d=subprocess.DEVNULL
print(subprocess.Popen(sys.argv[1:],stdin=d,stdout=d,stderr=d,start_new_session=True).pid)' \
    "$bin" -new-instance -profile "$prof" -new-window "$page" 2>/dev/null)
  case "$pid" in ''|*[!0-9]*) rm -rf "$prof"; ERR="Firefox could not be started"; return 1;; esac
  echo "$pid" > "$D/item/$id.pid"
  while [ "$n" -lt 100 ]; do   # 10 s: gone = failed; alive and prefs.js written (about 0.5 s before its window is drawn) = running
    kill -0 "$pid" 2>/dev/null || { ERR="Firefox (pid $pid) exited $((n / 10)).$((n % 10)) s after its start"; rm -f "$D/item/$id.pid"; rm -rf "$prof"; return 1; }
    [ -e "$prof/prefs.js" ] && break
    sleep 0.1; n=$((n + 1))
  done
  echo "$id" > "$D/ffcur"
  return 0
}
term_page() {  # term_page <id> -> PAGE = the snapshot page of the item's tmux session; 1 = ERR
  local t cap; t=$(iget "$1" title)
  mkdir -p "$D/pages"; PAGE="$D/pages/term-$1.html"; cap="$D/pages/term-$1.ansi"
  "$TMUX_BIN" capture-pane -e -p -S - -t "=$t:" > "$cap" 2> "$cap.err" \
    || { ERR="tmux: $(tr '\n' ' ' < "$cap.err")"; rm -f "$cap" "$cap.err"; return 1; }
  python3 -I "$here/termpage.py" "$t" "$t" "$PAGE" < "$cap" 2> "$cap.err" \
    || { ERR="termpage.py: $(tail -1 "$cap.err")"; rm -f "$cap" "$cap.err"; return 1; }
  rm -f "$cap" "$cap.err"
}

do_close() {  # do_close <id>: 0 closed (or nothing to close), 1 not ours / already closed
  local id=$1 mode
  if ! ihas "$id"; then
    case "$id" in ''|0) return 0;; esac
    echo "refused: window $id was not opened by this session"; return 1
  fi
  case "$(iget "$id" state)" in
    deferred) iset "$id" state closed; echo "closed: $id (recorded, never opened)"; return 0;;
    closed) echo "not found: window $id is already closed"; return 1;;
  esac
  mode=$(iget "$id" mode)
  iset "$id" state closed
  [ "$mode" = browser ] && { echo "closed: $id (the page stays in your browser: it is yours to close)"; return 0; }
  ff_kill "$id"
  echo "closed: $id"; return 0
}

do_show() {  # do_show <title> <old id to close or ""> -> 0 shown, 1 not shown
  local title=$1 old=${2:-} id cur e mode
  id=$(ifind "$title" | head -1)
  [ -n "$old" ] && [ "$old" != "$id" ] && do_close "$old" > /dev/null
  [ -n "$id" ] || { echo "not shown: no window matches '$title' (this session recorded no item under that title)"; return 1; }
  if [ "$(iget "$id" state)" = shown ]; then echo "shown: $id $title mode=$(iget "$id" mode)"; echo "shown-at $(et)"; return 0; fi
  cur=$(cat "$D/ffcur" 2>/dev/null)   # the item before: its Firefox goes first, whoever asked
  if [ -n "$cur" ] && [ "$cur" != "$id" ]; then ff_kill "$cur"; [ "$(iget "$cur" state)" = shown ] && iset "$cur" state closed; fi
  ERR=""; PAGE=$(iget "$id" target)
  if [ "$(iget "$id" kind)" = term ]; then term_page "$id" || { echo "not shown: $ERR"; return 1; }; fi
  if ff_open "$id" "$PAGE"; then mode=firefox
  else
    echo "firefox failed: $ERR"
    e=$("$OPEN_BIN" "$PAGE" 2>&1) || { echo "not shown: open: $(printf '%s' "$e" | tr '\n' ' ')"; return 1; }
    mode=browser
  fi
  iset "$id" mode "$mode"; iset "$id" state shown
  echo "shown: $id $title mode=$mode"; echo "shown-at $(et)"
  return 0
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  me)
    pane=${TMUX_PANE:-}; tty=""
    rm -f "$D/pane"
    if [ -n "$pane" ]; then echo "$pane" > "$D/pane"; else tty=$(my_tty); fi
    [ -n "$pane" ] || [ -n "$tty" ] || { echo "not found: 0 windows hold this session (no tmux pane and no tty)"; exit 1; }
    echo "me: ${pane:-$tty} 0 0 0 0 0";;
  show)
    [ $# -ge 1 ] || { echo "usage: win.sh show \"<title>\" [X Y W H] [timeout-s]" >&2; exit 2; }
    do_show "$1" "";;
  start)   # title X Y W H s TX TY TW TH term [picture]
    [ $# -ge 1 ] || { echo "usage: win.sh start \"<title>\" X Y W H s TX TY TW TH <term id> [picture.png]" >&2; exit 2; }
    do_show "$1" "";;
  next)    # old title X Y W H s term [picture] [TX TY TW TH]
    [ $# -ge 2 ] || { echo "usage: win.sh next <old id> \"<title>\" X Y W H s <term id> [picture.png] [TX TY TW TH]" >&2; exit 2; }
    do_show "$2" "$1";;
  close) [ $# -ge 1 ] || { echo "usage: win.sh close <id>" >&2; exit 2; }; do_close "$1";;
  find)
    [ $# -ge 1 ] || { echo "usage: win.sh find \"<title>\"" >&2; exit 2; }
    ids=$(ifind "$1"); n=$(printf '%s' "$ids" | grep -c .)
    if [ "$n" -eq 1 ]; then echo "$ids $(iget "$ids" title)"; exit 0; fi
    l=""; for i in $ids; do l="$l${l:+; }$i|$(iget "$i" state)|$(iget "$i" title)"; done
    echo "not found: $n windows hold '$1'${l:+: $l}"; exit 1;;
  close-cloaked)
    for i in $(ifind "${1:-}"); do
      [ "$(iget "$i" state)" = deferred ] && { iset "$i" state closed; echo "closed: $i (recorded, never opened) $(iget "$i" title)"; }
    done
    if [ -z "${1:-}" ]; then   # the end of a run: no Firefox of it stays, no profile of it stays
      for f in "$D"/item/*.pid; do [ -e "$f" ] || continue; i=$(basename "$f" .pid); ff_kill "$i"; done
      rm -rf "$D/ffprof" "$D/ffcur"
    fi
    exit 0;;
  setwin) echo "now unchanged";;
  front|untop|place|rect|geom|list-topmost|quit) exit 0;;
  *) sed -n '2,28p' "$0"; exit 2;;
esac
