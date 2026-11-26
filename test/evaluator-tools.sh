#!/bin/bash
# The evaluator's tools, per OS, without opening a window:
#   1. layout: local-tools/common, wsl, macos hold what each install needs; macos has the wsl command names; no .ps1 outside wsl
#   2. every .sh parses under this bash; the macOS tools use no flock, setsid, timeout, node or wslpath
#   3. evshow.sh (the same file on every OS) runs a whole two-item run against a stand-in win.sh and a written transcript
#   4. the macOS win-app.sh / term-open.sh / win.sh run against a stand-in osascript and a stand-in Firefox: deferred lines,
#      shown: lines, the Safari line without Firefox, `not shown: osascript: <text>` exit 1, usage exit 2
#   test/evaluator-tools.sh          -> all of the above; opens nothing (CI runs this on ubuntu and macos)
#   test/evaluator-tools.sh --live   -> macOS only, OPENS WINDOWS: the installed tools (~/.claude/local-tools), the real Firefox,
#                                       a web item and a terminal item beside your terminal, then everything put back
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
  export EVSHOW_STATE="$W/state" EVSHOW_TRANSCRIPTS="$W/tr"; mkdir -p "$EVSHOW_TRANSCRIPTS"; TR="$EVSHOW_TRANSCRIPTS/live.jsonl"; : > "$TR"
  out=$("$T/win.sh" me); echo "$out"; has "$out" "me: " "win.sh me finds this terminal"
  before=$(cat "$EVSHOW_STATE/term" 2>/dev/null)
  pg=$("$T/file-page.sh" "$R/README.md"); echo "$pg"; has "$pg" "page: " "file-page.sh builds a page"
  pg=${pg#page: }; title=${pg#*|}; html=${pg%%|*}
  out=$("$T/win-app.sh" --hidden --title "$title" firefox -new-window "$html"); echo "$out"; has "$out" "(deferred)" "win-app.sh --hidden records and opens nothing"
  TT="evlive-$RANDOM"
  out=$("$T/term-open.sh" "$TT" "$R" 'echo terminal item of the live test'); echo "$out"; has "$out" "opened $TT id=" "term-open.sh records the terminal item"
  n=$(osascript -e 'tell application "Firefox" to count (every window whose name contains "'"$title"'")' 2>/dev/null || echo 0)
  [ "${n:-0}" = 0 ] && ok "no window is open before the answer" || bad "a window was open before the answer ($n)"
  "$T/evshow.sh" arm first "$title" "$TT" | tail -1
  sleep 1.5; ask q0 "$TR"; sleep 1; answer q0 Yes "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 30); echo "$out"; has "$out" "shown: " "item 1 (web) shown after the answer"; has "$out" "elapsed " "elapsed line logged"
  f=$(lsappinfo info -only name -app "$(lsappinfo front)" | head -1); echo "front: $f"
  [ -s "$("$T/evshow.sh" path shown)" ] && ok "shown.png exists for item 1 ($("$T/evshow.sh" path shown))" || bad "no shown.png for item 1"
  cp "$("$T/evshow.sh" path shown)" "${EVLIVE_KEEP:-$W}/live-item1.png" 2>/dev/null
  sleep 2; ask q1 "$TR"; sleep 1; answer q1 Works "$TR"
  out=$("$T/evshow.sh" wait 30); echo "$out"; has "$out" "shown: " "item 2 (terminal) shown after the answer"
  cp "$("$T/evshow.sh" path shown)" "${EVLIVE_KEEP:-$W}/live-item2.png" 2>/dev/null
  sleep 2; ask q2 "$TR"; sleep 1; answer q2 Works "$TR"; sleep 1
  out=$("$T/evshow.sh" end); echo "$out"; has "$out" "now " "end restores the terminal"
  now=$(printf '%s\n' "$out" | sed -n 's/^now //p'); [ "$now" = "${before#* }" ] && ok "terminal back at its saved place ($now)" || bad "terminal at '$now', saved '${before#* }'"
  "$T/evshow.sh" history; out=$("$T/evshow.sh" noflash); has "$out" "no-flash: not measured (macOS)" "noflash line"
  tmux kill-session -t "$TT" 2>/dev/null
  pgrep -f "$EVSHOW_STATE/ff" >/dev/null && bad "this run's Firefox is still running" || ok "this run's Firefox is gone"
  echo "$([ $fails -eq 0 ] && echo "all live checks passed" || echo "$fails live check(s) failed")"; exit $((fails > 0))
fi

# ---- 1. layout ---------------------------------------------------------------------------------------------------
for f in evshow.sh evshow_watch.py evshow_noflash.py evsession.sh file-page.sh md2html.py phone-shot.sh phone-shot.mjs; do
  [ -f "$LT/common/$f" ] && ok "common/$f" || bad "common/$f missing"; done
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
for f in "$LT"/common/*.py; do python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" || bad "python: $f"; done; ok "python files parse"

# ---- 3. evshow.sh, a whole run against a stand-in win.sh --------------------------------------------------------
T="$W/tools"; mkdir -p "$T"; for f in "$LT"/common/* "$LT"/macos/*; do ln -s "$f" "$T/$(basename "$f")"; done
cat > "$W/winstub.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$EVSHOW_STATE/calls"
case "$1" in
  geom) echo "term 0 30 734 789"; echo "item 734 30 706 789";;
  start) echo "shown: 1001 $2 $3 $4 $5 $6"; echo "shown-at $(TZ=America/New_York date +%T).000"; [ -n "${13:-}" ] && echo png > "${13}";;
  next)  echo "shown: 1002 $3 $4 $5 $6 $7"; echo "shown-at $(TZ=America/New_York date +%T).000";;
  setwin) echo "now $3 $4 $5 $6 $7";;
esac
exit 0
EOF
chmod +x "$W/winstub.sh"
run_evshow() {  # run_evshow <os>
  local os=$1 S="$W/ev-$1" TR out
  mkdir -p "$S/tr"; TR="$S/tr/s.jsonl"; : > "$TR"
  export EVSHOW_STATE="$S/state" EVSHOW_TRANSCRIPTS="$S/tr" EVSHOW_TOOLS="$T" EVSHOW_WIN="$W/winstub.sh" EVSHOW_OS="$os"
  mkdir -p "$EVSHOW_STATE"; echo "2222 0 0 1440 900 0" > "$EVSHOW_STATE/term"
  out=$("$T/evshow.sh" arm first "item-a x1" "item-b x2"); has "$out" "armed first 'item-a x1'" "[$os] arm first"
  sleep 1; ask q0 "$TR"; sleep 0.5; answer q0 Yes "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 20); [ -n "${EVT_DEBUG:-}" ] && echo "$out"; has "$out" "shown: 1001 item-a x1 734 30 706 789" "[$os] item 1 shown at the geometry win.sh geom gave"
  has "$out" "elapsed " "[$os] elapsed line"; has "$out" "fired-by watcher" "[$os] the watcher fired the show"; has "$out" "item 1 of 2 shown (id 1001); next item 2 armed" "[$os] says id, arms item 2"
  has "$out" "capture $EVSHOW_STATE/shown.png" "[$os] picture copied to shown.png"
  grep -q "^start item-a x1 734 30 706 789 5 0 30 734 789 2222 " "$EVSHOW_STATE/calls" && ok "[$os] start got item rect, terminal rect and the terminal id" || bad "[$os] start call: $(grep '^start' "$EVSHOW_STATE/calls")"
  sleep 1; ask q1 "$TR"; sleep 0.5; answer q1 Works "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 20); has "$out" "shown: 1002 item-b x2" "[$os] item 2 shown"; has "$out" "LAST item" "[$os] last item said"
  grep -q "^next 1001 item-b x2 " "$EVSHOW_STATE/calls" && ok "[$os] next closes item 1" || bad "[$os] next call: $(grep '^next' "$EVSHOW_STATE/calls")"
  out=$("$T/evshow.sh" end); has "$out" "now 0 0 1440 900 0" "[$os] end puts the terminal back"
  grep -q "^quit" "$EVSHOW_STATE/calls" && ok "[$os] end runs win.sh quit" || bad "[$os] no quit call"
  grep -q "zlog\|^gate" "$EVSHOW_STATE/calls" && bad "[$os] started the WSL sampler" || ok "[$os] no z-order sampler, no gate captures"
  out=$("$T/evshow.sh" noflash); [ "$os" = mac ] && has "$out" "no-flash: not measured (macOS)" "[$os] noflash line"
  out=$("$T/evshow.sh" history); has "$out" "shown -> question" "[$os] shown -> question logged"
  "$T/evshow.sh" disarm >/dev/null 2>&1
  unset EVSHOW_STATE EVSHOW_TRANSCRIPTS EVSHOW_TOOLS EVSHOW_WIN EVSHOW_OS
}
run_evshow mac
out=$(EVSHOW_OS=other EVSHOW_TOOLS="$T" "$T/evshow.sh" status 2>&1); has "$out" "no window tools for this OS" "evshow.sh says so on an OS without window tools"

# ---- 4. the macOS tools against a stand-in osascript and Firefox ------------------------------------------------
cat > "$W/osastub.sh" <<'EOF'
#!/bin/bash
# stand-in osascript: answers by the script's text; OSA_FAIL=<text> makes every call fail with it
sc=""; args=()
while [ $# -gt 0 ]; do case "$1" in -l) shift 2;; -e) sc="$2"; shift 2;; *) args+=("$1"); shift;; esac; done
echo "${sc%%$'\n'*} | ${args[*]:-}" >> "$OSA_LOG"
[ -n "${OSA_FAIL:-}" ] && { echo "0:0: execution error: $OSA_FAIL" >&2; exit 1; }
case "$sc" in
  *NSScreen*) echo "0 30 1440 789";;
  *"tty of s"*) echo "2222 0 0 1440 900";;
  *"count of tabs of w) is 1"*) [ -n "${OSA_SAFARI_HANG:-}" ] && sleep 30; [ -e "$OSA_WINDOWS" ] && grep -F -- "${args[0]}" "$OSA_WINDOWS" | cut -d'|' -f1;;
  *"every window whose name contains"*) [ -e "$OSA_WINDOWS" ] && grep -F -- "${args[0]}" "$OSA_WINDOWS" | cut -d'|' -f1;;
  *"make new document"*) echo "77|$(basename "${args[0]}" .html | sed 's/%20/ /g')" >> "$OSA_WINDOWS";;
  *"create window with default profile"*) echo 88;;
  *"set bounds"*) echo "${args[2]}, ${args[3]}, ${args[4]}, ${args[5]}";;
  *"set b to bounds"*) echo "734, 30, 1440, 819";;
esac
exit 0
EOF
cat > "$W/Firefox.app.sh" <<'EOF'
#!/bin/bash
# stand-in Firefox: records its arguments; "opens" a window by adding "<id>|<file name>" to the windows list; writes the picture
echo "$*" >> "$FF_LOG"
shot=""; url=""; while [ $# -gt 0 ]; do case "$1" in --screenshot) shot="$2"; shift 2;; -profile|--window-size) shift 2;; -*) shift;; *) url="$1"; shift;; esac; done
if [ -n "$shot" ]; then printf 'PNG' > "$shot"; exit 0; fi
n=$(( $(wc -l < "$OSA_WINDOWS" 2>/dev/null || echo 0) + 41 )); echo "$n|$(basename "$url" .html | sed 's/%20/ /g')" >> "$OSA_WINDOWS"
case " $(tail -1 "$FF_LOG") " in *" -new-instance "*) exec sleep 60;; esac
EOF
cat > "$W/openstub.sh" <<'EOF'
#!/bin/bash
# stand-in `open -a Safari <file url>`: "opens" a Safari window named after the file
echo "open $*" >> "$OSA_LOG"; u="${3:-}"; echo "78|$(basename "$u" .html | sed 's/%20/ /g')" >> "$OSA_WINDOWS"
EOF
chmod +x "$W/openstub.sh"
mkdir -p "$W/Firefox.app/Contents/MacOS"; cp "$W/Firefox.app.sh" "$W/Firefox.app/Contents/MacOS/firefox"; chmod +x "$W/osastub.sh" "$W/Firefox.app/Contents/MacOS/firefox"
mac_env() { export EVSHOW_STATE="$W/mac-$1" EVSHOW_TOOLS="$T" EVSHOW_OSASCRIPT="$W/osastub.sh" EVSHOW_OPEN="$W/openstub.sh" OSA_LOG="$W/mac-$1.osa" OSA_WINDOWS="$W/mac-$1.windows" FF_LOG="$W/mac-$1.ff"; : > "$OSA_LOG"; : > "$FF_LOG"; rm -f "$OSA_WINDOWS"; unset OSA_FAIL OSA_SAFARI_HANG EVSHOW_SAFARI_WAIT; }
M="$LT/macos"

mac_env ff; export EVSHOW_FIREFOX_APP="$W/Firefox.app"
printf '<title>page-a k3</title>' > "$W/page-a k3.html"
out=$("$M/win-app.sh" --hidden --title "page-a k3" firefox -new-window "$W/page-a k3.html"); [ "$out" = "hidden: 1001 0 0 page-a k3 (deferred)" ] && ok "win-app.sh --hidden: $out" || bad "win-app.sh --hidden printed: $out"
[ ! -s "$FF_LOG" ] && [ ! -e "$OSA_WINDOWS" ] && ok "the opener started no Firefox and no window" || bad "the opener started something: $(cat "$FF_LOG")"
"$M/win-app.sh" --hidden firefox "$W/page-a k3.html" >/dev/null; [ $? = 2 ] && ok "no --title: exit 2" || bad "no --title should exit 2"
out=$("$M/win-app.sh" --hidden --title z firefox /no/such.html); rc=$?; [ $rc = 1 ] && has "$out" "not hidden: no such file" "missing file: exit 1, one line"
out=$("$M/win-app.sh" code x); [ $? = 2 ] && has "$out" "not opened: VS Code is retired" "win-app.sh code: exit 2"
"$M/win-app.sh" --hidden --title z wt >/dev/null 2>&1; [ $? = 2 ] && ok "unknown app: exit 2" || bad "unknown app should exit 2"
out=$("$M/win.sh" me 2>&1); case "$out" in "me: 2222 0 0 1440 900 0"|"not found: "*) ok "win.sh me: one line ($out)";; *) bad "win.sh me printed: $out";; esac
echo "2222 0 0 1440 900 0" > "$EVSHOW_STATE/term"; echo iTerm2 > "$EVSHOW_STATE/termapp"
out=$("$M/win.sh" geom); [ "$out" = "term 0 30 734 789
item 734 30 706 789" ] && ok "geom: terminal left 51% below the menu bar, item the rest" || bad "geom printed: $out"
out=$("$M/win.sh" start "page-a k3" 734 30 706 789 5 0 30 734 789 2222 "$W/pic.png"); rc=$?
has "$out" "shown: 1001 page-a k3 734 30 706 789" "start: shown line with the id the opener printed"; [ $rc = 0 ] || bad "start exit $rc"
has "$(cat "$FF_LOG")" "-new-instance -profile $EVSHOW_STATE/ff -new-window file://" "one Firefox per run: -new-instance -profile <state>/ff"
grep -q 'browser.aboutwelcome.enabled", false' "$EVSHOW_STATE/ff/user.js" && ok "first-run pages are off in the run's profile" || bad "no first-run prefs"
has "$(cat "$OSA_LOG")" "| 2222  0 30 734 819" "terminal placed left by its window id"
has "$(cat "$OSA_LOG")" "| iTerm2" "the terminal app is reactivated"
has "$out" "capture: $W/pic.png 706x789" "picture by headless Firefox at the item's size"; has "$(cat "$FF_LOG")" "--headless -new-instance -profile $EVSHOW_STATE/ffshot --screenshot" "headless picture uses its own profile"
tmux() { :; }   # (term-open.sh needs the real tmux; skipped when there is none)
if command -v tmux >/dev/null 2>&1 && \tmux -L "evt$$" new-session -d -s probe 2>/dev/null; then \tmux -L "evt$$" kill-server
  TT="evtool-$$-$RANDOM"; out=$("$M/term-open.sh" "$TT" "$W" 'echo hi'); has "$out" "opened $TT id=1002 (deferred)" "term-open.sh: $out"
  out=$("$M/win.sh" next 1001 "$TT" 734 30 706 789 5 2222 "" 0 30 734 789); has "$out" "shown: 1002 $TT 734 30 706 789" "next: terminal item shown"
  has "$(cat "$OSA_LOG")" "attach -t $TT" "iTerm2 create window ... tmux attach -t <Title>"
  [ "$(sed -n 's/^state=//p' "$EVSHOW_STATE/item/1001")" = closed ] && ok "next closed the old item" || bad "old item not closed"
  out=$("$M/term-close.sh" "$TT" 1002); has "$out" "closed: 1002" "term-close.sh closes the window"; command tmux has-session -t "=$TT" 2>/dev/null && bad "tmux session left" || ok "tmux session killed"
else echo "SKIP term-open.sh (no tmux server can start here)"; "$M/win.sh" close 1001 >/dev/null; fi
unset -f tmux
out=$("$M/win.sh" close 4242); [ $? = 1 ] && has "$out" "refused: window 4242 was not opened by this session" "a window this session did not open is refused"
out=$("$M/win.sh" show nothing-here 1 2 3 4); [ $? = 1 ] && has "$out" "not shown: no window matches" "show of an unknown title: not shown, exit 1"
"$M/win.sh" bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown subcommand: exit 2" || bad "unknown subcommand should exit 2"
p=$(cat "$EVSHOW_STATE/ffpid" 2>/dev/null); out=$("$M/win.sh" quit); kill -0 "$p" 2>/dev/null && bad "quit left pid $p" || ok "quit killed this run's Firefox by pid ($p)"
[ ! -e "$EVSHOW_STATE/ff" ] && ok "quit removed the run's profile" || bad "profile left"

mac_env err; export EVSHOW_FIREFOX_APP="$W/Firefox.app"
"$M/win-app.sh" --hidden --title "page-a k3" firefox "$W/page-a k3.html" >/dev/null
out=$(OSA_FAIL="Not authorized to send Apple events to Firefox. (-1743)" "$M/win.sh" show "page-a k3" 734 30 706 789); rc=$?
[ "$out" = "not shown: osascript: execution error: Not authorized to send Apple events to Firefox. (-1743)" ] && [ $rc = 1 ] && ok "osascript failure: one line, exit 1: $out" || bad "osascript failure printed (rc $rc): $out"
"$M/win.sh" quit >/dev/null

mac_env safari; export EVSHOW_FIREFOX_APP="$W/no-Firefox.app"
out=$("$M/win-app.sh" --hidden --title "page-a k3" firefox "$W/page-a k3.html"); has "$out" "(deferred)" "no Firefox: the opener still records"
out=$("$M/win.sh" show "page-a k3" 734 30 706 789); rc=$?
has "$out" "browser: Safari (Firefox recommended: full features)" "no Firefox: the Safari line"; has "$out" "shown: 1001 page-a k3 734 30 706 789" "Safari answered: placed by id"
[ ! -s "$FF_LOG" ] && ok "no Firefox was started" || bad "Firefox was started"
has "$(cat "$OSA_LOG")" "open -a Safari file://" "a file page goes to Safari through open (AppleScript cannot load file:// there)"
"$M/win-app.sh" --hidden --title "web-b k4" firefox "https://example.com/web-b%20k4.html" >/dev/null
out=$("$M/win.sh" show "web-b k4" 734 30 706 789); has "$out" "shown: 1002 web-b k4 734 30 706 789" "a web URL opens as a new Safari document, placed by id"
"$M/win.sh" close 1002 >/dev/null
out=$("$M/win.sh" close 1001); has "$out" "closed: 1001" "Safari window closed by id"
mac_env safari2; export EVSHOW_FIREFOX_APP="$W/no-Firefox.app" OSA_SAFARI_HANG=1 EVSHOW_SAFARI_WAIT=1
"$M/win-app.sh" --hidden --title "page-a k3" firefox "$W/page-a k3.html" >/dev/null
out=$("$M/win.sh" show "page-a k3" 734 30 706 789); rc=$?
has "$out" "shown: safari unplaced page-a k3" "Safari gave no answer in time: opened plainly, unplaced"; [ $rc = 0 ] || bad "unplaced exit $rc"
out=$("$M/screen-capture.sh" x); [ $? = 1 ] && has "$out" "not captured: " "screen-capture.sh: one line, exit 1"

echo "$([ $fails -eq 0 ] && echo "all checks passed" || echo "$fails check(s) failed")"
exit $((fails > 0))
