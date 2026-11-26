#!/bin/bash
# The evaluator's tools, per OS, without opening anything:
#   1. layout: local-tools/common, wsl, macos hold what each install needs; macos has the wsl command names; no .ps1 outside wsl
#   2. every .sh parses under this bash; the macOS tools use no flock, setsid, timeout, node or wslpath, set no window bounds,
#      run no AppleScript and open no tmux pane, iTerm2 split or iTerm2 tab
#   3. evshow.sh (the same file on every OS) runs a whole two-item run against a stand-in win.sh and a written transcript
#   4. the macOS win-app.sh / term-open.sh / win.sh run against a stand-in Firefox, tmux and open: each show starts a
#      separate Firefox on a fresh profile and first kills the one before; a terminal item is a page of its coloured text;
#      Firefox absent or gone = `firefox failed:` then `open`; the end leaves no Firefox and no profile
#   5. phone-shot.sh on macOS: for real on a 3-screen page when Firefox.app is installed (headless, no window): parts of
#      780x1688; with a stand-in Firefox that never opens its port: `no picture`, exit 1, no file
#   test/evaluator-tools.sh          -> all of the above; opens no window (CI runs this on ubuntu and macos)
#   test/evaluator-tools.sh --live   -> macOS only, OPENS A SEPARATE FIREFOX WINDOW for a few seconds per item: the installed
#                                       tools (~/.claude/local-tools), a file, a terminal item and a web page, then all closed
# Exit 0 = every line PASS.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
LT="$R/local-tools"
fails=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 (wanted '$2' in: $(printf '%s' "$1" | head -5 | tr '\n' '~'))";; esac; }
W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"
trap 'rm -rf "$W"' EXIT
q() { python3 -c 'import json,sys,datetime; print(json.dumps({"timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00","Z"), "message": {"content": [json.loads(sys.argv[1])]}}))' "$1"; }
ask()    { q "{\"type\":\"tool_use\",\"name\":\"AskUserQuestion\",\"id\":\"$1\"}" >> "$2"; }
answer() { q "{\"type\":\"tool_result\",\"tool_use_id\":\"$1\",\"content\":\"User has answered: \\\"Q\\\"=\\\"$2\\\"\"}" >> "$3"; }

if [ "${1:-}" = --live ]; then
  [ "$(uname -s)" = Darwin ] || { echo "--live is macOS only"; exit 2; }
  T="$HOME/.claude/local-tools"; [ -x "$T/win.sh" ] || { echo "FAIL $T/win.sh is not installed (./install.sh)"; exit 1; }
  [ -x /Applications/Firefox.app/Contents/MacOS/firefox ] || { echo "--live needs /Applications/Firefox.app"; exit 2; }
  export EVSHOW_STATE="$W/state" EVSHOW_TRANSCRIPTS="$W/tr"; mkdir -p "$EVSHOW_TRANSCRIPTS"; TR="$EVSHOW_TRANSCRIPTS/live.jsonl"; : > "$TR"
  # every Firefox and iTerm2 window: owner pid, bounds (CGWindowList: needs no permission, reads no window content)
  wins() { osascript -l JavaScript -e 'ObjC.import("CoreGraphics"); var l=ObjC.castRefToObject($.CGWindowListCopyWindowInfo(0,0)); var o=[]; for (var i=0;i<l.count;i++){ var w=l.objectAtIndex(i); var n=ObjC.unwrap(w.objectForKey("kCGWindowOwnerName")); if(n=="Firefox"||n=="iTerm2"){ var b=ObjC.deepUnwrap(w.objectForKey("kCGWindowBounds")); o.push(ObjC.unwrap(w.objectForKey("kCGWindowOwnerPID"))+" "+n+" "+b.X+","+b.Y+" "+b.Width+"x"+b.Height+" "+(ObjC.unwrap(w.objectForKey("kCGWindowIsOnscreen"))?"on":"off")); } } o.sort().join("\n")' 2>/dev/null; }
  ours() { local p n=0; for p in $(pgrep -f -- "-profile $EVSHOW_STATE/ffprof/"); do case "$(ps -o comm= -p "$p" 2>/dev/null)" in */firefox) n=$((n + 1));; esac; done; echo "$n"; }   # the Firefox main processes this run started
  bigwin() { wins | awk -v p="$1" '$1 == p && $NF == "on" { split($4, a, "x"); if (a[1] >= 400 && a[2] >= 300) n++ } END { print n + 0 }'; }
  ff0=$(pgrep -x firefox | sort | tr '\n' ' '); w0=$(wins); echo "before: your Firefox pids [$ff0], $(printf '%s\n' "$w0" | grep -c .) Firefox and iTerm2 windows"
  out=$("$T/win.sh" me); echo "$out"; has "$out" "me: " "win.sh me"
  pg=$("$T/file-page.sh" "$R/README.md"); pg=${pg#page: }; t1=${pg#*|}
  out=$("$T/win-app.sh" --hidden --title "$t1" firefox -new-window "${pg%%|*}"); echo "$out"; has "$out" "(deferred)" "win-app.sh --hidden records and opens nothing"
  TT="evlive-$RANDOM"
  out=$("$T/term-open.sh" "$TT" "$R" "printf '\\033[31mred line of the live test\\033[0m\\n'; ls -G"); echo "$out"; has "$out" "opened $TT id=" "term-open.sh records the terminal item"
  printf '<!doctype html><title>web item evlive</title><h1>The web item of the live test</h1>' > "$W/web.html"
  "$T/win-app.sh" --hidden --title "web item evlive" firefox -new-window "$W/web.html" >/dev/null
  [ "$(ours)" = 0 ] && [ "$(wins)" = "$w0" ] && ok "nothing is open before the answer" || bad "something opened before the answer"
  "$T/evshow.sh" arm first "$t1" "$TT" "web item evlive" | tail -1
  sleep 1.5; ask q0 "$TR"; sleep 1; answer q0 Yes "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 30); echo "$out"; has "$out" "shown: 1001 $t1 mode=firefox" "item 1 (file) shown in a separate Firefox after the answer"; has "$out" "elapsed " "elapsed line logged"
  p1=$(cat "$EVSHOW_STATE/item/1001.pid" 2>/dev/null); sleep 3
  [ "$(ours)" = 1 ] && ok "one Firefox of this run is running (pid $p1)" || bad "Firefox processes of this run: $(ours), wanted 1"
  [ "$(bigwin "$p1")" = 1 ] && ok "it has one window on screen" || bad "windows of pid $p1 on screen: $(bigwin "$p1"); $(wins | grep "^$p1 " | tr '\n' ';')"
  ask q1 "$TR"; sleep 1; answer q1 Works "$TR"
  out=$("$T/evshow.sh" wait 30); echo "$out"; has "$out" "shown: 1002 $TT mode=firefox" "item 2 (terminal) shown as a page"
  p2=$(cat "$EVSHOW_STATE/item/1002.pid" 2>/dev/null); sleep 3
  ! kill -0 "$p1" 2>/dev/null && [ ! -d "$EVSHOW_STATE/ffprof/1001" ] && ok "item 1's Firefox is gone, its profile deleted" || bad "item 1's Firefox (pid $p1) or profile is still there"
  [ "$(ours)" = 1 ] && [ "$(bigwin "$p2")" = 1 ] && ok "one Firefox of this run, one window" || bad "Firefox processes of this run: $(ours); windows of $p2: $(bigwin "$p2")"
  grep -q 'red line of the live test</span>' "$EVSHOW_STATE/pages/term-1002.html" && grep -q '<span style="color:#c33">' "$EVSHOW_STATE/pages/term-1002.html" && ok "the terminal page holds the session's text, colours kept" || bad "terminal page: $(head -c 600 "$EVSHOW_STATE/pages/term-1002.html")"
  ask q2 "$TR"; sleep 1; answer q2 Works "$TR"
  out=$("$T/evshow.sh" wait 30); echo "$out"; has "$out" "shown: 1003 web item evlive mode=firefox" "item 3 (web page) shown as itself"
  p3=$(cat "$EVSHOW_STATE/item/1003.pid" 2>/dev/null); sleep 3
  ! kill -0 "$p2" 2>/dev/null && [ "$(ours)" = 1 ] && [ "$(bigwin "$p3")" = 1 ] && ok "item 2's Firefox is gone; one Firefox of this run, one window" || bad "after item 3: $(ours) Firefox of this run, pid $p2 alive?"
  ask q3 "$TR"; sleep 1; answer q3 Works "$TR"; sleep 1
  out=$("$T/evshow.sh" end); echo "$out"; has "$out" "now unchanged" "end prints now unchanged"
  sleep 1; [ "$(ours)" = 0 ] && [ ! -d "$EVSHOW_STATE/ffprof" ] && ok "no Firefox of this run is left, the run's profiles are deleted" || bad "left: $(ours) Firefox, $(ls "$EVSHOW_STATE/ffprof" 2>/dev/null | tr '\n' ' ')"
  [ "$(pgrep -x firefox | sort | tr '\n' ' ')" = "$ff0" ] && ok "your own Firefox is as it was (pids [$ff0])" || bad "Firefox pids now [$(pgrep -x firefox | sort | tr '\n' ' ')], were [$ff0]"
  [ "$(wins)" = "$w0" ] && ok "every Firefox and iTerm2 window is where it was" || bad "windows changed: $(diff <(printf '%s\n' "$w0") <(wins) | tr '\n' ';')"
  "$T/evshow.sh" history; out=$("$T/evshow.sh" noflash); has "$out" "no-flash: not measured (macOS)" "noflash line"
  out=$("$T/evshow.sh" path shown); [ "$out" = "no picture (macOS)" ] && ok "path shown: $out" || bad "path shown printed: $out"
  tmux kill-session -t "$TT" 2>/dev/null
  echo "$([ $fails -eq 0 ] && echo "all live checks passed" || echo "$fails live check(s) failed")"; exit $((fails > 0))
fi

# ---- 1. layout ---------------------------------------------------------------------------------------------------
for f in evshow.sh evshow_watch.py evshow_noflash.py evsession.sh file-page.sh md2html.py phone-shot.sh phone-shot.mjs; do
  [ -f "$LT/common/$f" ] && ok "common/$f" || bad "common/$f missing"; done
for f in phone-bidi.py termpage.py; do [ -f "$LT/macos/$f" ] && ok "macos/$f" || bad "macos/$f missing"; done
for f in win.sh win-app.sh term-open.sh term-close.sh screen-capture.sh; do
  [ -x "$LT/wsl/$f" ] && [ -x "$LT/macos/$f" ] && ok "$f in wsl/ and macos/" || bad "$f must be executable in wsl/ and macos/"; done
n=$(ls "$LT/common" "$LT/macos" | grep -c '\.ps1$'); [ "$n" = 0 ] && ok "no .ps1 in common/ or macos/" || bad "$n .ps1 file(s) outside wsl/"
dup=$( (ls "$LT/common"; ls "$LT/macos") | sort | uniq -d; (ls "$LT/common"; ls "$LT/wsl") | sort | uniq -d)
[ -z "$dup" ] && ok "no file name is in common/ and an OS folder" || bad "in two folders: $dup"
[ ! -e "$R/wsl/local-tools" ] && ok "wsl/local-tools is gone" || bad "wsl/local-tools still exists"

# ---- 2. syntax and the fresh-Mac rule ---------------------------------------------------------------------------
for f in "$LT"/common/*.sh "$LT"/macos/*.sh "$LT"/wsl/*.sh; do bash -n "$f" 2>/dev/null || bad "syntax: $f"; done; ok "every .sh parses"
[ -x /bin/bash ] && case "$(/bin/bash --version | head -1)" in *"version 3."*) for f in "$LT"/common/*.sh "$LT"/macos/*.sh; do /bin/bash -n "$f" || bad "bash 3.2 syntax: $f"; done; ok "common/ and macos/ parse under bash 3.2";; esac
x=$(grep -nE '(^|[^a-zA-Z_.-])(flock|setsid|timeout|node|wslpath|swiftc|screencapture|powershell\.exe)( |$)' "$LT"/macos/*.sh | grep -v '^[^:]*:[0-9]*:#' | grep -v 'no `timeout`')
[ -z "$x" ] && ok "macOS tools call no flock/setsid/timeout/node/wslpath/compiler/screencapture" || bad "macOS tools call: $x"
x=$(grep -nE 'set bounds|osascript|iTerm|split-window|split vertically|create tab|EVSHOW_MAC_MODE|Safari|Chrome|chromium|screencapture' "$LT"/macos/*.sh "$LT"/macos/*.py | grep -v '^[^:]*:[0-9]*:#')
[ -z "$x" ] && ok "macOS tools set no window bounds, run no AppleScript, open no pane, split or tab, and name no other browser" || bad "macOS tools hold: $x"
x=$(grep -nE 'modeidx|EVSHOW_MAC_MODE|iTerm' "$LT"/common/evshow.sh); [ -z "$x" ] && ok "evshow.sh holds no mode rotation" || bad "evshow.sh holds: $x"
x=$(grep -ciE 'Which way of showing|EVSHOW_MAC_MODE|mode=tmux|mode=iterm|mode=tab' "$R/agents/evaluator.md"); [ "$x" = 0 ] && ok "evaluator.md has no which-mode question" || bad "evaluator.md still names the modes ($x lines)"
for f in "$LT"/common/*.py "$LT"/macos/*.py; do python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" || bad "python: $f"; done; ok "python files parse"

# ---- 3. evshow.sh, a whole run against a stand-in win.sh --------------------------------------------------------
T="$W/tools"; mkdir -p "$T"; for f in "$LT"/common/* "$LT"/macos/*; do ln -s "$f" "$T/$(basename "$f")"; done
cat > "$W/winstub.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$EVSHOW_STATE/calls"
case "$1" in
  start) echo "shown: 1001 $2 mode=firefox"; echo "shown-at $(TZ=America/New_York date +%T).000";;
  next)  echo "shown: 1002 $3 mode=firefox"; echo "shown-at $(TZ=America/New_York date +%T).000";;
esac
exit 0
EOF
chmod +x "$W/winstub.sh"
run_evshow() {  # run_evshow <os>
  local os=$1 S="$W/ev-$1" TR out
  mkdir -p "$S/tr"; TR="$S/tr/s.jsonl"; : > "$TR"
  export EVSHOW_STATE="$S/state" EVSHOW_TRANSCRIPTS="$S/tr" EVSHOW_TOOLS="$T" EVSHOW_WIN="$W/winstub.sh" EVSHOW_OS="$os"
  mkdir -p "$EVSHOW_STATE"
  out=$("$T/evshow.sh" arm first "item-a x1" "item-b x2"); has "$out" "armed first 'item-a x1'" "[$os] arm first"
  sleep 1; ask q0 "$TR"; sleep 0.5; answer q0 Yes "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 20); [ -n "${EVT_DEBUG:-}" ] && echo "$out"; has "$out" "shown: 1001 item-a x1 mode=firefox" "[$os] item 1 shown, the line as win.sh printed it"
  has "$out" "elapsed " "[$os] elapsed line"; has "$out" "fired-by watcher" "[$os] the watcher fired the show"; has "$out" "item 1 of 2 shown (id 1001); next item 2 armed" "[$os] says id, arms item 2"
  case "$out" in *shown.png*|*gate.png*) bad "[$os] a picture line was printed";; *) ok "[$os] no picture line";; esac
  grep -q "^start item-a x1 0 0 0 0 5 0 0 0 0 " "$EVSHOW_STATE/calls" && ok "[$os] start carries no geometry" || bad "[$os] start call: $(grep '^start' "$EVSHOW_STATE/calls")"
  sleep 1; ask q1 "$TR"; sleep 0.5; answer q1 Works "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 20); has "$out" "shown: 1002 item-b x2 mode=firefox" "[$os] item 2 shown"; has "$out" "LAST item" "[$os] last item said"
  grep -q "^next 1001 item-b x2 " "$EVSHOW_STATE/calls" && ok "[$os] next closes item 1" || bad "[$os] next call: $(grep '^next' "$EVSHOW_STATE/calls")"
  out=$("$T/evshow.sh" end); has "$out" "now unchanged" "[$os] end prints now unchanged"
  grep -q "^close 1002" "$EVSHOW_STATE/calls" && ok "[$os] end closes the open item" || bad "[$os] no close call"
  grep -q "^geom\|^setwin\|^quit\|^place\|zlog\|^gate" "$EVSHOW_STATE/calls" && bad "[$os] geometry, setwin, quit or sampler call: $(grep '^geom\|^setwin\|^quit\|^place' "$EVSHOW_STATE/calls")" || ok "[$os] no geom, setwin, place, quit, sampler or gate call"
  out=$("$T/evshow.sh" noflash); has "$out" "no-flash: not measured (macOS)" "[$os] noflash line"
  out=$("$T/evshow.sh" path shown); [ "$out" = "no picture (macOS)" ] && ok "[$os] path shown: $out" || bad "[$os] path shown printed: $out"
  out=$("$T/evshow.sh" history); has "$out" "shown -> question" "[$os] shown -> question logged"
  has "$out" "shown: 1001 item-a x1 mode=firefox" "[$os] history holds item 1's shown: line"; has "$out" "shown: 1002 item-b x2 mode=firefox" "[$os] history holds item 2's shown: line"
  "$T/evshow.sh" disarm >/dev/null 2>&1
  unset EVSHOW_STATE EVSHOW_TRANSCRIPTS EVSHOW_TOOLS EVSHOW_WIN EVSHOW_OS
}
run_evshow mac
out=$(EVSHOW_OS=other EVSHOW_TOOLS="$T" "$T/evshow.sh" status 2>&1); has "$out" "no window tools for this OS" "evshow.sh says so on an OS without window tools"


# ---- 4. the macOS tools against a stand-in Firefox, tmux and open -----------------------------------------------
cat > "$W/tmuxstub.sh" <<'EOF'
#!/bin/bash
# stand-in tmux: records its arguments; capture-pane prints coloured text; TMUX_FAIL=<text> makes capture-pane fail with it
echo "$*" >> "$TMUX_LOG"
case "$1" in
  capture-pane) [ -n "${TMUX_FAIL:-}" ] && { echo "$TMUX_FAIL" >&2; exit 1; }
    printf '$ make test\n\033[31mred words\033[0m then plain <b>\n\033[1;38;5;46mbold green\033[0m\n\n\n';;
  has-session) exit 1;;
esac
exit 0
EOF
mkdir -p "$W/Firefox.app/Contents/MacOS"
cat > "$W/Firefox.app/Contents/MacOS/firefox" <<'EOF'
#!/bin/bash
# stand-in Firefox: records its arguments and stays alive like a browser. FF_DIE=1 exits at once; FF_SLOW=1 never writes
# prefs.js; it never opens a port and never opens a window.
echo "$*" >> "${FF_LOG:-/dev/null}"
[ -n "${FF_DIE:-}" ] && exit 1
prof=""; while [ $# -gt 0 ]; do [ "$1" = -profile ] && prof=$2; shift; done
[ -n "${FF_SLOW:-}" ] || [ -z "$prof" ] || : > "$prof/prefs.js"
while :; do sleep 0.2; done
EOF
cat > "$W/openstub.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$OPEN_LOG"
[ -n "${OPEN_FAIL:-}" ] && { echo "$OPEN_FAIL" >&2; exit 1; }
exit 0
EOF
chmod +x "$W/tmuxstub.sh" "$W/openstub.sh" "$W/Firefox.app/Contents/MacOS/firefox"
trap 'pkill -f "$W/Firefox.app" 2>/dev/null; rm -rf "$W"' EXIT
mac_env() {
  export EVSHOW_STATE="$W/mac-$1" EVSHOW_TOOLS="$T" EVSHOW_TMUX="$W/tmuxstub.sh" EVSHOW_OPEN="$W/openstub.sh" EVSHOW_FIREFOX_APP="$W/Firefox.app"
  export TMUX_LOG="$W/mac-$1.tmux" FF_LOG="$W/mac-$1.ff" OPEN_LOG="$W/mac-$1.open" TMUX_PANE="%7"
  : > "$TMUX_LOG"; : > "$FF_LOG"; : > "$OPEN_LOG"; unset FF_DIE FF_SLOW TMUX_FAIL OPEN_FAIL; }
M="$LT/macos"
page() {  # page <file> [A-B]: builds its file page and records it; sets PT (title), PF (the page file), PO (the opener's line)
  local pg; pg=$("$LT/common/file-page.sh" "$@"); pg=${pg#page: }; PT=${pg#*|}; PF=${pg%%|*}
  PO=$("$M/win-app.sh" --hidden --title "$PT" firefox -new-window "$PF"); }
pidof() { cat "$EVSHOW_STATE/item/$1.pid" 2>/dev/null; }
alive() { local p; p=$(pidof "$1"); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
line1() { printf '%s\n' "$1" | head -1; }

mac_env run
printf 'line one\nline two\nline three\n' > "$W/notes a.txt"
page "$W/notes a.txt"; t1=$PT; f1=$PF
[ "$PO" = "hidden: 1001 0 0 $t1 (deferred)" ] && ok "win-app.sh --hidden: $PO" || bad "win-app.sh --hidden printed: $PO"
[ "$(sed -n 's/^kind=//p' "$EVSHOW_STATE/item/1001")" = file ] && [ "$(sed -n 's/^target=//p' "$EVSHOW_STATE/item/1001")" = "$f1" ] && ok "a file is recorded as its file-page.sh page" || bad "item 1001: $(tr '\n' ' ' < "$EVSHOW_STATE/item/1001")"
"$M/win-app.sh" --hidden firefox "$W/notes a.txt" >/dev/null; [ $? = 2 ] && ok "no --title: exit 2" || bad "no --title should exit 2"
out=$("$M/win-app.sh" --hidden --title z firefox /no/such.html); rc=$?; [ $rc = 1 ] && has "$out" "not hidden: no such file" "missing file: exit 1, one line"
out=$("$M/win-app.sh" code x); [ $? = 2 ] && has "$out" "not opened: VS Code is retired" "win-app.sh code: exit 2"
"$M/win-app.sh" --hidden --title z wt >/dev/null 2>&1; [ $? = 2 ] && ok "unknown app: exit 2" || bad "unknown app should exit 2"
out=$("$M/win.sh" me 2>&1); [ "$out" = "me: %7 0 0 0 0 0" ] && ok "win.sh me: $out" || bad "win.sh me printed: $out"
TT="evtool-$$"; out=$("$M/term-open.sh" "$TT" "$W" 'echo hi'); [ "$out" = "opened $TT id=1002 (deferred)" ] && ok "term-open.sh: $out" || bad "term-open.sh printed: $out"
has "$(cat "$TMUX_LOG")" "new-session -d -s $TT -c $W" "term-open.sh makes the detached tmux session"
"$M/win-app.sh" --hidden --title "web k3" firefox -new-window "https://example.com/web%20k3" >/dev/null
printf '<title>own k4</title>' > "$W/own k4.html"; "$M/win-app.sh" --hidden --title "own k4" firefox "$W/own k4.html" >/dev/null
[ ! -s "$FF_LOG" ] && [ ! -s "$OPEN_LOG" ] && [ ! -d "$EVSHOW_STATE/ffprof" ] && ok "the openers put nothing on screen and start no Firefox" || bad "an opener opened something: $(cat "$FF_LOG" "$OPEN_LOG")"
sleep 300 & USERFF=$!; disown 2>/dev/null   # stands for the user's own Firefox: a process this run did not start

out=$("$M/win.sh" start "$t1" 734 30 706 789 5 0 30 734 789 2222 "$W/pic.png"); rc=$?
[ "$(line1 "$out")" = "shown: 1001 $t1 mode=firefox" ] && [ $rc = 0 ] && ok "item 1 (file): shown: 1001 ... mode=firefox (X Y W H ignored)" || bad "start printed (rc $rc): $out"
[ "$(cat "$FF_LOG")" = "-new-instance -profile $EVSHOW_STATE/ffprof/1001 -new-window $f1" ] && ok "Firefox is started with -new-instance, a fresh profile under the state dir and the page in a new window" || bad "Firefox got: $(cat "$FF_LOG")"
alive 1001 && ok "its pid is recorded and alive ($(pidof 1001))" || bad "no live pid recorded for item 1"
grep -q '"browser.shell.checkDefaultBrowser", false' "$EVSHOW_STATE/ffprof/1001/user.js" && grep -q '"browser.aboutwelcome.enabled", false' "$EVSHOW_STATE/ffprof/1001/user.js" && grep -q '"browser.sessionstore.resume_from_crash", false' "$EVSHOW_STATE/ffprof/1001/user.js" \
  && ok "the profile turns off the welcome page, session restore and the default-browser prompt" || bad "user.js: $(cat "$EVSHOW_STATE/ffprof/1001/user.js" 2>&1 | head -5)"
[ ! -e "$W/pic.png" ] && ok "no picture is taken" || bad "a picture was written"
[ ! -s "$OPEN_LOG" ] && ok "open is not used when Firefox starts" || bad "open got: $(cat "$OPEN_LOG")"
p1=$(pidof 1001)
out=$("$M/win.sh" next 1001 "$TT" 734 30 706 789 5 2222 "" 0 30 734 789)
[ "$(line1 "$out")" = "shown: 1002 $TT mode=firefox" ] && ok "item 2 (terminal): shown: 1002 ... mode=firefox" || bad "next printed: $out"
! kill -0 "$p1" 2>/dev/null && [ ! -d "$EVSHOW_STATE/ffprof/1001" ] && ok "the item before: its Firefox pid is killed, its profile deleted" || bad "item 1's Firefox (pid $p1) or profile is still there"
grep -q "^capture-pane -e -p -S - -t =$TT:" "$TMUX_LOG" && ok "the terminal page is tmux capture-pane -e -p -S - of its session" || bad "no capture-pane call: $(cat "$TMUX_LOG")"
tp="$EVSHOW_STATE/pages/term-1002.html"
[ "$(tail -1 "$FF_LOG")" = "-new-instance -profile $EVSHOW_STATE/ffprof/1002 -new-window $tp" ] && ok "Firefox is given the snapshot page" || bad "Firefox got: $(tail -1 "$FF_LOG")"
grep -q '<span style="color:#c33">red words</span> then plain &lt;b&gt;' "$tp" && grep -q '<span style="color:#00ff00;font-weight:bold">bold green</span>' "$tp" && ok "the page holds the session's text, colours kept, markup escaped" || bad "terminal page: $(sed -n '2,6p' "$tp" 2>&1)"
grep -q "<title>$TT</title>" "$tp" && grep -q '<header><b>terminal ' "$tp" && ok "it has the file-page look (a header naming the session)" || bad "terminal page head: $(head -c 300 "$tp")"
p2=$(pidof 1002)
out=$("$M/win.sh" show "web k3" 1 2 3 4); [ "$(line1 "$out")" = "shown: 1003 web k3 mode=firefox" ] && ok "item 3 (a URL): shown: 1003 web k3 mode=firefox" || bad "web show printed: $out"
[ "$(tail -1 "$FF_LOG")" = "-new-instance -profile $EVSHOW_STATE/ffprof/1003 -new-window https://example.com/web%20k3" ] && ok "a URL is opened as itself" || bad "Firefox got: $(tail -1 "$FF_LOG")"
! kill -0 "$p2" 2>/dev/null && ok "a plain show kills the previous item's Firefox too" || bad "item 2's Firefox (pid $p2) is still alive"
out=$("$M/win.sh" next 1003 "own k4" 1 2 3 4 5 2222); [ "$(line1 "$out")" = "shown: 1004 own k4 mode=firefox" ] && [ "$(tail -1 "$FF_LOG")" = "-new-instance -profile $EVSHOW_STATE/ffprof/1004 -new-window $W/own k4.html" ] && ok "a .html file is opened as itself: mode=firefox" || bad "html show: $out / $(tail -1 "$FF_LOG")"
[ "$(pgrep -f -- "-profile $EVSHOW_STATE/ffprof/" | wc -l | tr -d ' ')" = 1 ] && ok "one Firefox of the run is alive at a time" || bad "Firefox of the run alive: $(pgrep -fl -- "-profile $EVSHOW_STATE/ffprof/")"
[ ! -s "$OPEN_LOG" ] && ok "open was never used" || bad "open got: $(cat "$OPEN_LOG")"
echo "$USERFF" > "$EVSHOW_STATE/item/1003.pid"   # a stale pid file that now names somebody else's process
out=$("$M/term-close.sh" "$TT" 1002 2>&1); grep -q "^kill-session -t $TT" "$TMUX_LOG" && ok "term-close.sh kills the tmux session" || bad "no kill-session"
p4=$(pidof 1004); out=$("$M/win.sh" close 1004); [ "$out" = "closed: 1004" ] && ! kill -0 "$p4" 2>/dev/null && ok "close kills that item's Firefox" || bad "close printed: $out"
out=$("$M/win.sh" close-cloaked); [ ! -d "$EVSHOW_STATE/ffprof" ] && ok "close-cloaked with no title deletes the run's profiles" || bad "profiles left: $(ls "$EVSHOW_STATE/ffprof")"
kill -0 "$USERFF" 2>/dev/null && ok "a process this run did not start is never signalled (a stale pid file named it)" || bad "the process standing for the user's Firefox was killed"
out=$("$M/win.sh" setwin 2222 0 0 1440 900 0); [ "$out" = "now unchanged" ] && ok "setwin: $out" || bad "setwin printed: $out"
out=$("$M/win.sh" close 4242); [ $? = 1 ] && has "$out" "refused: window 4242 was not opened by this session" "a window this session did not open is refused"
out=$("$M/win.sh" show nothing-here 1 2 3 4); [ $? = 1 ] && has "$out" "not shown: no window matches" "show of an unknown title: not shown, exit 1"
"$M/win.sh" bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown subcommand: exit 2" || bad "unknown subcommand should exit 2"
[ "$("$M/win-app.sh" --path firefox)" = "$W/Firefox.app/Contents/MacOS/firefox" ] && ok "win-app.sh --path firefox prints the binary" || bad "--path printed: $("$M/win-app.sh" --path firefox)"

mac_env absent; export EVSHOW_FIREFOX_APP="$W/no-Firefox.app"
page "$W/notes a.txt"
out=$("$M/win.sh" show "$PT" 734 30 706 789); rc=$?
[ "$out" = "firefox failed: $W/no-Firefox.app is not installed
shown: 1001 $PT mode=browser
$(printf '%s\n' "$out" | tail -1)" ] && [ $rc = 0 ] && ok "no Firefox.app: 'firefox failed: <reason>', then shown: ... mode=browser" || bad "no-Firefox show printed (rc $rc): $out"
[ "$(cat "$OPEN_LOG")" = "$PF" ] && ok "... and the page went to open" || bad "open got: $(cat "$OPEN_LOG")"
out=$("$M/win.sh" close 1001); has "$out" "closed: 1001 (the page stays in your browser" "a default-browser page is never closed"
[ "$("$M/win-app.sh" --path firefox)" = open ] && ok "win-app.sh --path firefox prints open without Firefox.app" || bad "--path printed: $("$M/win-app.sh" --path firefox)"

mac_env die; export FF_DIE=1
page "$W/notes a.txt"
out=$("$M/win.sh" show "$PT"); rc=$?
case "$(line1 "$out")" in "firefox failed: Firefox (pid "*") exited 0."*" s after its start") ok "Firefox gone after its start: $(line1 "$out")";; *) bad "dead-Firefox show printed: $out";; esac
has "$out" "shown: 1001 $PT mode=browser" "... then shown: mode=browser"; [ "$(cat "$OPEN_LOG")" = "$PF" ] && [ ! -d "$EVSHOW_STATE/ffprof/1001" ] && ok "... through open, and the failed try's profile is deleted" || bad "open got: $(cat "$OPEN_LOG")"

mac_env noopen; export FF_DIE=1 OPEN_FAIL="No application knows how to open it"
page "$W/notes a.txt"
out=$("$M/win.sh" show "$PT"); rc=$?
[ "$(printf '%s\n' "$out" | tail -1)" = "not shown: open: No application knows how to open it" ] && [ $rc = 1 ] && ok "open fails too: not shown: open: <its text>, exit 1" || bad "double failure printed (rc $rc): $out"

mac_env slow; export FF_SLOW=1
page "$W/notes a.txt"
if [ -n "${EVT_FAST:-}" ]; then echo "SKIP Firefox alive 10 s without prefs.js (EVT_FAST)"; else
  t0=$SECONDS; out=$("$M/win.sh" show "$PT"); [ "$(line1 "$out")" = "shown: 1001 $PT mode=firefox" ] && [ $((SECONDS - t0)) -ge 9 ] && alive 1001 && ok "Firefox alive 10 s after its start counts as shown: mode=firefox" || bad "slow show printed after $((SECONDS - t0)) s: $out"
  "$M/win.sh" close 1001 >/dev/null
fi

mac_env notmux; export TMUX_FAIL="can't find session: gone"
"$M/term-open.sh" "gone-$$" "$W" >/dev/null
out=$("$M/win.sh" show "gone-$$"); [ $? = 1 ] && has "$out" "not shown: tmux: can't find session: gone" "a terminal item whose session is gone: not shown, exit 1"
[ ! -s "$FF_LOG" ] && ok "... and no Firefox is started" || bad "Firefox got: $(cat "$FF_LOG")"
out=$("$M/screen-capture.sh" x); [ $? = 1 ] && has "$out" "not captured: " "screen-capture.sh: one line, exit 1"

# the whole run through evshow.sh and the real macOS win.sh: the end leaves no Firefox and no profile
mac_env end; S="$W/end"; mkdir -p "$S/tr"; TR="$S/tr/s.jsonl"; : > "$TR"
export EVSHOW_TRANSCRIPTS="$S/tr" EVSHOW_OS=mac
page "$W/notes a.txt"; a=$PT; page "$W/notes a.txt"; b=$PT
"$T/evshow.sh" arm first "$a" "$b" >/dev/null
sleep 1; ask q0 "$TR"; sleep 0.5; answer q0 Yes "$TR"; sleep 1.5
out=$("$T/evshow.sh" wait 20); has "$out" "shown: 1001 $a mode=firefox" "[run] item 1 shown after the answer"; has "$out" "fired-by watcher" "[run] the watcher fired the show"
sleep 1; ask q1 "$TR"; sleep 0.5; answer q1 Works "$TR"; sleep 1.5
out=$("$T/evshow.sh" wait 20); has "$out" "shown: 1002 $b mode=firefox" "[run] item 2 shown"
alive 1002 && ok "[run] the last item's Firefox is alive before the end" || bad "[run] item 2 has no live Firefox"
pe=$(pidof 1002); out=$("$T/evshow.sh" end); has "$out" "now unchanged" "[run] end prints now unchanged"
! kill -0 "$pe" 2>/dev/null && ok "[run] end kills the last item's Firefox" || bad "[run] pid $pe is still alive after end"
[ ! -d "$EVSHOW_STATE/ffprof" ] && [ -z "$(pgrep -f -- "-profile $EVSHOW_STATE/ffprof/")" ] && ok "[run] end deletes the run's profiles; no Firefox of the run is left" || bad "[run] left: $(ls "$EVSHOW_STATE/ffprof" 2>&1)"
out=$("$T/evshow.sh" path shown); [ "$out" = "no picture (macOS)" ] && ok "[run] path shown: $out" || bad "[run] path shown printed: $out"
kill -0 "$USERFF" 2>/dev/null && ok "[run] the process standing for the user's Firefox is still alive" || bad "[run] the user's process was killed"
"$T/evshow.sh" disarm >/dev/null 2>&1; kill "$USERFF" 2>/dev/null
unset EVSHOW_TRANSCRIPTS EVSHOW_OS EVSHOW_STATE

# ---- 5. phone-shot.sh on macOS: headless Firefox over WebDriver BiDi ------------------------------------------------
if [ "$(uname -s)" != Darwin ]; then echo "SKIP phone-shot on macOS: this is $(uname -s)"
else
  PS="$LT/common/phone-shot.sh"; PH="$W/phone"; mkdir -p "$PH"
  size() { python3 -c 'import struct,sys; b=open(sys.argv[1],"rb").read(24); print("%dx%d" % struct.unpack(">II", b[16:24]))' "$1" 2>/dev/null; }
  if [ -x /Applications/Firefox.app/Contents/MacOS/firefox ] && [ -z "${PHONE_FIREFOX_APP:-}" ]; then
    # 3 screens: 844 + 844 + 612 css px; the page writes what it was drawn at into itself
    printf '<!doctype html><meta name="viewport" content="width=device-width"><style>html,body{margin:0}div{height:2300px;background:linear-gradient(#fff,#36c)}</style><div>three screens</div>' > "$PH/three.html"
    ffb=$(pgrep -x firefox | sort | tr '\n' ' ')
    out=$("$PS" "$PH/01-three" html "$PH/three.html"); rc=$?
    [ "$out" = "png $PH/01-three-p1.png 780x1688
png $PH/01-three-p2.png 780x1688
png $PH/01-three-p3.png 780x1224" ] && [ $rc = 0 ] && ok "phone-shot html, 3 screens: three png lines, 780x1688 780x1688 780x1224" || bad "phone-shot printed (rc $rc): $out"
    [ "$(size "$PH/01-three-p1.png") $(size "$PH/01-three-p2.png") $(size "$PH/01-three-p3.png")" = "780x1688 780x1688 780x1224" ] && ok "the three files are those sizes" || bad "files: $(ls "$PH")"
    out=$(PHONE_OVERLAY_SCROLLBARS=0 "$PS" "$PH/01b-bars" html "$PH/three.html"); has "$out" "png $PH/01b-bars-p3.png 780x1224" "classic scroll bars (a Mac with a mouse, a CI runner): still 780 wide, no bar in the picture"
    [ ! -e "$PH/01-three.png" ] && [ -z "$(ls "$PH" | grep tmp-)" ] && ok "no whole-page file and no temporary file is left" || bad "left: $(ls "$PH")"
    printf '<!doctype html><meta name="viewport" content="width=device-width"><p id="o"></p><script>document.getElementById("o").textContent=innerWidth+" "+devicePixelRatio+" "+matchMedia("(max-width:400px)").matches</script>' > "$PH/probe.html"
    out=$("$PS" "$PH/02-short" html "$PH/probe.html"); case "$out" in "png $PH/02-short.png 780x"*) h=${out##*x}; [ "$h" -le 1688 ] && [ "$h" -ge 240 ] && ok "a short page is one <base>.png, 780 wide, no taller than a screen ($out)" || bad "short page: $out";; *) bad "short page printed: $out";; esac
    printf '# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- item\n' > "$PH/n.md"; out=$("$PS" "$PH/03-md" md "$PH/n.md"); has "$out" "png $PH/03-md.png 780x" "phone-shot md"
    seq 1 400 > "$PH/n.txt"; out=$("$PS" "$PH/04-text" text "$PH/n.txt"); has "$out" "png $PH/04-text-p1.png 780x1688" "phone-shot text (a long file is cut into parts)"
    out=$("$PS" "$PH/05-range" text "$PH/n.txt" 10-12); has "$out" "png $PH/05-range.png 780x" "phone-shot text A-B"
    if command -v tmux >/dev/null 2>&1; then
      PT5="evphone-$$"; tmux new-session -d -s "$PT5" -x 100 -y 40 2>/dev/null && { tmux send-keys -t "$PT5" "printf '\\033[32mgreen\\033[0m\\n'" Enter; sleep 1
        out=$("$PS" "$PH/06-tmux" tmux "$PT5"); has "$out" "png $PH/06-tmux.png 780x" "phone-shot tmux"; tmux kill-session -t "$PT5" 2>/dev/null; }
    fi
    out=$("$PS" "$PH/07-url" url "file://$PH/three.html"); has "$out" "png $PH/07-url-p3.png 780x1224" "phone-shot url"
    [ "$(pgrep -x firefox | sort | tr '\n' ' ')" = "$ffb" ] && [ -z "$(pgrep -f 'phone-ff-')" ] && ok "the headless Firefox is gone after each picture; no other Firefox was touched" || bad "Firefox pids now [$(pgrep -x firefox | sort | tr '\n' ' ')], were [$ffb]"
    out=$("$PS" "$PH/08-bad" url "http://127.0.0.1:1/nothing"); rc=$?
    case "$out" in "phone-shot.sh: no picture: BiDi browsingContext.navigate: "*) [ $rc = 1 ] && [ -z "$(ls "$PH" | grep '^08-')" ] && ok "BiDi answers with an error: one 'no picture' line, exit 1, no file ($out)" || bad "bad url: rc $rc, files $(ls "$PH" | grep '^08-')";; *) bad "bad url printed (rc $rc): $out";; esac
  else echo "SKIP phone-shot: no Firefox"; fi
  out=$(PHONE_FIREFOX_APP="$W/Firefox.app" PHONE_PORT_WAIT=3 FF_LOG="$W/phone.ff" "$PS" "$PH/09-stand" html "$W/own k4.html"); rc=$?
  case "$out" in "phone-shot.sh: no picture: port "*" did not answer in 3 s"*) [ $rc = 1 ] && ok "a Firefox that never opens its port: $out, exit 1" || bad "silent port: rc $rc";; *) bad "silent port printed (rc $rc): $out";; esac
  [ -z "$(ls "$PH" | grep '^09-')" ] && ok "... and no file is left" || bad "left: $(ls "$PH" | grep '^09-')"
  grep -q -- '--headless --remote-debugging-port=[0-9]* -new-instance -profile ' "$W/phone.ff" && ok "... it was started headless on a scratch profile and a port of its own" || bad "stand-in Firefox got: $(cat "$W/phone.ff" 2>&1)"
  sleep 0.5; [ -z "$(pgrep -f 'phone-ff-')" ] && ok "... and it was killed before the tool exited" || bad "still alive: $(pgrep -fl 'phone-ff-')"
  out=$(PHONE_FIREFOX_APP="$W/no-Firefox.app" "$PS" "$PH/10-none" html "$W/own k4.html"); rc=$?
  [ "$out" = "phone-shot.sh: no picture: $W/no-Firefox.app is not installed" ] && [ $rc = 1 ] && ok "no Firefox.app: $out, exit 1" || bad "no-Firefox phone-shot printed (rc $rc): $out"
  x=$(grep -niE 'node|playwright|chrom' "$LT/macos/phone-bidi.py"); [ -z "$x" ] && ok "the macOS phone tool uses no node, Playwright or Chrome" || bad "phone-bidi.py holds: $x"
fi

echo "$([ $fails -eq 0 ] && echo "all checks passed" || echo "$fails check(s) failed")"
exit $((fails > 0))
