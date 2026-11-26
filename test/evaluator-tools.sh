#!/bin/bash
# The evaluator's tools, per OS, without opening anything:
#   1. layout: local-tools/common, wsl, macos hold what each install needs; macos has the wsl command names; no .ps1 outside wsl
#   2. every .sh parses under this bash; the macOS tools use no flock, setsid, timeout, node or wslpath, set no window bounds
#      and start no browser of their own
#   3. evshow.sh (the same file on every OS) runs a whole two-item run against a stand-in win.sh and a written transcript
#   4. the macOS win-app.sh / term-open.sh / win.sh run against a stand-in tmux, osascript and open: each mode's command
#      (tmux pane, iTerm2 split, iTerm2 tab), the rotation, web items through `open` only, the fall back to the tmux pane
#   test/evaluator-tools.sh          -> all of the above; opens nothing (CI runs this on ubuntu and macos)
#   test/evaluator-tools.sh --live   -> macOS only, in tmux inside iTerm2, OPENS A PANE, A SPLIT AND A TAB in your terminal for
#                                       a few seconds each: the installed tools (~/.claude/local-tools), a file, a terminal item
#                                       and a file again, one per mode, then everything closed
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
  [ -n "${TMUX_PANE:-}" ] || { echo "--live runs inside tmux (the tmux pane mode splits this pane)"; exit 2; }
  T="$HOME/.claude/local-tools"; [ -x "$T/win.sh" ] || { echo "FAIL $T/win.sh is not installed (./install.sh)"; exit 1; }
  export EVSHOW_STATE="$W/state" EVSHOW_TRANSCRIPTS="$W/tr"; unset EVSHOW_MAC_MODE; mkdir -p "$EVSHOW_TRANSCRIPTS"; TR="$EVSHOW_TRANSCRIPTS/live.jsonl"; : > "$TR"
  panes() { tmux list-panes -t "$TMUX_PANE" | wc -l | tr -d ' '; }
  sessions() { osascript -e 'tell application "iTerm2"
set n to 0
repeat with w in windows
repeat with tb in tabs of w
set n to n + (count of sessions of tb)
end repeat
end repeat
return n
end tell' 2>/dev/null; }
  bounds() { osascript -e 'tell application "iTerm2" to get bounds of current window' 2>/dev/null; }
  p0=$(panes); s0=$(sessions); b0=$(bounds); echo "before: $p0 tmux panes, $s0 iTerm2 sessions, window bounds $b0"
  out=$("$T/win.sh" me); echo "$out"; has "$out" "me: $TMUX_PANE " "win.sh me finds this pane"
  pg=$("$T/file-page.sh" "$R/README.md"); pg=${pg#page: }; t1=${pg#*|}
  out=$("$T/win-app.sh" --hidden --title "$t1" firefox -new-window "${pg%%|*}"); echo "$out"; has "$out" "(deferred)" "win-app.sh --hidden records and opens nothing"
  TT="evlive-$RANDOM"
  out=$("$T/term-open.sh" "$TT" "$R" 'echo terminal item of the live test'); echo "$out"; has "$out" "opened $TT id=" "term-open.sh records the terminal item"
  pg=$("$T/file-page.sh" "$R/AGENTS.md"); pg=${pg#page: }; t3=${pg#*|}; "$T/win-app.sh" --hidden --title "$t3" firefox "${pg%%|*}" >/dev/null
  [ "$(panes)" = "$p0" ] && [ "$(sessions)" = "$s0" ] && ok "nothing is open before the answer" || bad "something opened before the answer"
  "$T/evshow.sh" arm first "$t1" "$TT" "$t3" | tail -1
  sleep 1.5; ask q0 "$TR"; sleep 1; answer q0 Yes "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 30); echo "$out"; has "$out" "shown: 1001 $t1 mode=tmux" "item 1 (file) shown in a tmux pane after the answer"; has "$out" "elapsed " "elapsed line logged"
  [ "$(panes)" = $((p0 + 1)) ] && ok "one more tmux pane" || bad "tmux panes: $(panes), wanted $((p0 + 1))"
  sleep 2; ask q1 "$TR"; sleep 1; answer q1 Works "$TR"
  out=$("$T/evshow.sh" wait 30); echo "$out"; has "$out" "shown: 1002 $TT mode=iterm" "item 2 (terminal) shown in an iTerm2 split"
  [ "$(panes)" = "$p0" ] && ok "item 1's pane is closed" || bad "tmux panes: $(panes), wanted $p0"
  [ "$(sessions)" = $((s0 + 1)) ] && ok "one more iTerm2 session" || bad "iTerm2 sessions: $(sessions), wanted $((s0 + 1))"
  [ -n "$(tmux list-clients -t "$TT" 2>/dev/null)" ] && ok "the split is attached to tmux session $TT" || bad "no client on $TT"
  sleep 2; ask q2 "$TR"; sleep 1; answer q2 Works "$TR"
  out=$("$T/evshow.sh" wait 30); echo "$out"; has "$out" "shown: 1003 $t3 mode=tab" "item 3 (file) shown in an iTerm2 tab"
  [ "$(sessions)" = $((s0 + 1)) ] && ok "item 2's split is closed, the tab is open" || bad "iTerm2 sessions: $(sessions), wanted $((s0 + 1))"
  sleep 2; ask q3 "$TR"; sleep 1; answer q3 Works "$TR"; sleep 1
  out=$("$T/evshow.sh" end); echo "$out"; has "$out" "now unchanged" "end prints now unchanged"
  sleep 1; [ "$(panes)" = "$p0" ] && [ "$(sessions)" = "$s0" ] && ok "everything is closed ($p0 panes, $s0 sessions)" || bad "left open: $(panes) panes, $(sessions) sessions"
  [ "$(bounds)" = "$b0" ] && ok "the iTerm2 window was not resized ($b0)" || bad "window bounds now $(bounds), were $b0"
  "$T/evshow.sh" history; out=$("$T/evshow.sh" noflash); has "$out" "no-flash: not measured (macOS)" "noflash line"
  out=$("$T/evshow.sh" path shown); [ "$out" = "no picture (macOS)" ] && ok "path shown: $out" || bad "path shown printed: $out"
  tmux kill-session -t "$TT" 2>/dev/null
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
x=$(grep -nE 'set bounds|Firefox|Safari|--headless|-new-instance' "$LT"/macos/*.sh | grep -v '^[^:]*:[0-9]*:#')
[ -z "$x" ] && ok "macOS tools set no window bounds and start no browser of their own" || bad "macOS tools hold: $x"
for f in "$LT"/common/*.py; do python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" || bad "python: $f"; done; ok "python files parse"

# ---- 3. evshow.sh, a whole run against a stand-in win.sh --------------------------------------------------------
T="$W/tools"; mkdir -p "$T"; for f in "$LT"/common/* "$LT"/macos/*; do ln -s "$f" "$T/$(basename "$f")"; done
cat > "$W/winstub.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$EVSHOW_STATE/calls"
case "$1" in
  start) echo "shown: 1001 $2 mode=tmux"; echo "shown-at $(TZ=America/New_York date +%T).000";;
  next)  echo "shown: 1002 $3 mode=iterm"; echo "shown-at $(TZ=America/New_York date +%T).000";;
esac
exit 0
EOF
chmod +x "$W/winstub.sh"
run_evshow() {  # run_evshow <os>
  local os=$1 S="$W/ev-$1" TR out
  mkdir -p "$S/tr"; TR="$S/tr/s.jsonl"; : > "$TR"
  export EVSHOW_STATE="$S/state" EVSHOW_TRANSCRIPTS="$S/tr" EVSHOW_TOOLS="$T" EVSHOW_WIN="$W/winstub.sh" EVSHOW_OS="$os"
  mkdir -p "$EVSHOW_STATE"; echo 2 > "$EVSHOW_STATE/modeidx"
  out=$("$T/evshow.sh" arm first "item-a x1" "item-b x2"); has "$out" "armed first 'item-a x1'" "[$os] arm first"
  [ ! -e "$EVSHOW_STATE/modeidx" ] && ok "[$os] arm first starts the mode rotation over" || bad "[$os] modeidx left from an earlier run"
  sleep 1; ask q0 "$TR"; sleep 0.5; answer q0 Yes "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 20); [ -n "${EVT_DEBUG:-}" ] && echo "$out"; has "$out" "shown: 1001 item-a x1 mode=tmux" "[$os] item 1 shown, the line as win.sh printed it"
  has "$out" "elapsed " "[$os] elapsed line"; has "$out" "fired-by watcher" "[$os] the watcher fired the show"; has "$out" "item 1 of 2 shown (id 1001); next item 2 armed" "[$os] says id, arms item 2"
  case "$out" in *shown.png*|*gate.png*) bad "[$os] a picture line was printed";; *) ok "[$os] no picture line";; esac
  grep -q "^start item-a x1 0 0 0 0 5 0 0 0 0 " "$EVSHOW_STATE/calls" && ok "[$os] start carries no geometry" || bad "[$os] start call: $(grep '^start' "$EVSHOW_STATE/calls")"
  sleep 1; ask q1 "$TR"; sleep 0.5; answer q1 Works "$TR"; sleep 1.5
  out=$("$T/evshow.sh" wait 20); has "$out" "shown: 1002 item-b x2 mode=iterm" "[$os] item 2 shown"; has "$out" "LAST item" "[$os] last item said"
  grep -q "^next 1001 item-b x2 " "$EVSHOW_STATE/calls" && ok "[$os] next closes item 1" || bad "[$os] next call: $(grep '^next' "$EVSHOW_STATE/calls")"
  out=$("$T/evshow.sh" end); has "$out" "now unchanged" "[$os] end prints now unchanged"
  grep -q "^close 1002" "$EVSHOW_STATE/calls" && ok "[$os] end closes the open item" || bad "[$os] no close call"
  grep -q "^geom\|^setwin\|^quit\|^place\|zlog\|^gate" "$EVSHOW_STATE/calls" && bad "[$os] geometry, setwin, quit or sampler call: $(grep '^geom\|^setwin\|^quit\|^place' "$EVSHOW_STATE/calls")" || ok "[$os] no geom, setwin, place, quit, sampler or gate call"
  out=$("$T/evshow.sh" noflash); has "$out" "no-flash: not measured (macOS)" "[$os] noflash line"
  out=$("$T/evshow.sh" path shown); [ "$out" = "no picture (macOS)" ] && ok "[$os] path shown: $out" || bad "[$os] path shown printed: $out"
  out=$("$T/evshow.sh" history); has "$out" "shown -> question" "[$os] shown -> question logged"
  has "$out" "shown: 1001 item-a x1 mode=tmux" "[$os] history holds item 1's shown: line"; has "$out" "shown: 1002 item-b x2 mode=iterm" "[$os] history holds item 2's shown: line"
  "$T/evshow.sh" disarm >/dev/null 2>&1
  unset EVSHOW_STATE EVSHOW_TRANSCRIPTS EVSHOW_TOOLS EVSHOW_WIN EVSHOW_OS
}
run_evshow mac
out=$(EVSHOW_OS=other EVSHOW_TOOLS="$T" "$T/evshow.sh" status 2>&1); has "$out" "no window tools for this OS" "evshow.sh says so on an OS without window tools"

# ---- 4. the macOS tools against a stand-in tmux, osascript and open ---------------------------------------------
cat > "$W/tmuxstub.sh" <<'EOF'
#!/bin/bash
# stand-in tmux: records its arguments; split-window prints a pane id; TMUX_FAIL=<text> makes split-window fail with it
echo "$*" >> "$TMUX_LOG"
case "$1" in
  split-window) [ -n "${TMUX_FAIL:-}" ] && { echo "$TMUX_FAIL" >&2; exit 1; }; echo "%91";;
  display-message) echo "/dev/ttys099";;
  has-session) exit 1;;
esac
exit 0
EOF
cat > "$W/osastub.sh" <<'EOF'
#!/bin/bash
# stand-in osascript: records "<what the script does>|<args>"; OSA_FAIL=<text> makes every call fail with it; OSA_HANG=1 never answers
sc=""; args=()
while [ $# -gt 0 ]; do case "$1" in -l) shift 2;; -e) sc="$2"; shift 2;; *) args+=("$1"); shift;; esac; done
case "$sc" in *"split vertically with default profile command"*) w=split;; *"create tab with default profile command"*) w=tab;; *"tell s to close"*) w=close;; *) w=other;; esac
echo "$w|${args[*]:-}" >> "$OSA_LOG"
[ -n "${OSA_HANG:-}" ] && sleep 30
[ -n "${OSA_FAIL:-}" ] && { echo "0:0: execution error: $OSA_FAIL" >&2; exit 1; }
echo sent
EOF
cat > "$W/openstub.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$OPEN_LOG"
EOF
chmod +x "$W/tmuxstub.sh" "$W/osastub.sh" "$W/openstub.sh"; mkdir -p "$W/iTerm.app"
mac_env() {
  export EVSHOW_STATE="$W/mac-$1" EVSHOW_TOOLS="$T" EVSHOW_TMUX="$W/tmuxstub.sh" EVSHOW_OSASCRIPT="$W/osastub.sh" EVSHOW_OPEN="$W/openstub.sh" EVSHOW_ITERM_APP="$W/iTerm.app"
  export TMUX_LOG="$W/mac-$1.tmux" OSA_LOG="$W/mac-$1.osa" OPEN_LOG="$W/mac-$1.open" TMUX_PANE="%7"
  : > "$TMUX_LOG"; : > "$OSA_LOG"; : > "$OPEN_LOG"; unset OSA_FAIL OSA_HANG TMUX_FAIL EVSHOW_MAC_MODE; }
M="$LT/macos"
page() {  # page <file> [A-B]: builds its file page and records it; sets PT (title)
  local pg; pg=$("$LT/common/file-page.sh" "$@"); pg=${pg#page: }; PT=${pg#*|}
  PO=$("$M/win-app.sh" --hidden --title "$PT" firefox -new-window "${pg%%|*}"); }

mac_env rot
printf 'line one\nline two\nline three\n' > "$W/notes a.txt"
page "$W/notes a.txt"; t1=$PT
[ "$PO" = "hidden: 1001 0 0 $t1 (deferred)" ] && ok "win-app.sh --hidden: $PO" || bad "win-app.sh --hidden printed: $PO"
[ "$(sed -n 's/^kind=//p' "$EVSHOW_STATE/item/1001")" = file ] && [ "$(sed -n 's/^target=//p' "$EVSHOW_STATE/item/1001")" = "$W/notes a.txt" ] && ok "a file page is recorded as its source file" || bad "item 1001: $(tr '\n' ' ' < "$EVSHOW_STATE/item/1001")"
"$M/win-app.sh" --hidden firefox "$W/notes a.txt" >/dev/null; [ $? = 2 ] && ok "no --title: exit 2" || bad "no --title should exit 2"
out=$("$M/win-app.sh" --hidden --title z firefox /no/such.html); rc=$?; [ $rc = 1 ] && has "$out" "not hidden: no such file" "missing file: exit 1, one line"
out=$("$M/win-app.sh" code x); [ $? = 2 ] && has "$out" "not opened: VS Code is retired" "win-app.sh code: exit 2"
"$M/win-app.sh" --hidden --title z wt >/dev/null 2>&1; [ $? = 2 ] && ok "unknown app: exit 2" || bad "unknown app should exit 2"
out=$("$M/win.sh" me 2>&1); [ "$out" = "me: %7 0 0 0 0 0" ] && ok "win.sh me: $out" || bad "win.sh me printed: $out"
TT="evtool-$$"; out=$("$M/term-open.sh" "$TT" "$W" 'echo hi'); [ "$out" = "opened $TT id=1002 (deferred)" ] && ok "term-open.sh: $out" || bad "term-open.sh printed: $out"
has "$(cat "$TMUX_LOG")" "new-session -d -s $TT -c $W" "term-open.sh makes the detached tmux session"
page "$W/notes a.txt" 2-3; t3=$PT
page "$W/notes a.txt"; t4=$PT
"$M/win-app.sh" --hidden --title "web k5" firefox -new-window "https://example.com/web%20k5" >/dev/null
printf '<title>own k6</title>' > "$W/own k6.html"; "$M/win-app.sh" --hidden --title "own k6" firefox "$W/own k6.html" >/dev/null
[ ! -s "$OSA_LOG" ] && [ ! -s "$OPEN_LOG" ] && ! grep -q 'split-window' "$TMUX_LOG" && ok "the openers put nothing on screen" || bad "an opener opened something: $(cat "$OSA_LOG" "$OPEN_LOG")"

out=$("$M/win.sh" start "$t1" 734 30 706 789 5 0 30 734 789 2222 "$W/pic.png"); rc=$?
[ "$(printf '%s\n' "$out" | head -1)" = "shown: 1001 $t1 mode=tmux" ] && [ $rc = 0 ] && ok "item 1: shown: 1001 ... mode=tmux (X Y W H ignored)" || bad "start printed (rc $rc): $out"
has "$(cat "$TMUX_LOG")" "split-window -h -d -l 50% -t %7 -P -F #{pane_id} /bin/sh " "tmux mode: split-window -h -d, 50%, on the evaluator's pane"
has "$(cat "$EVSHOW_STATE/item/1001.sh")" "exec less -R " "a file page's command is less -R"; has "$(cat "$EVSHOW_STATE/item/1001.sh")" "notes" "... on its source file"
[ ! -e "$W/pic.png" ] && ok "no picture is taken" || bad "a picture was written"
out=$("$M/win.sh" show "web k5" 1 2 3 4); [ "$(printf '%s\n' "$out" | head -1)" = "shown: 1005 web k5 mode=browser" ] && ok "a URL: shown: 1005 web k5 mode=browser" || bad "web show printed: $out"
[ "$(cat "$OPEN_LOG")" = "https://example.com/web%20k5" ] && ok "a URL goes to open and nothing else" || bad "open got: $(cat "$OPEN_LOG")"
out=$("$M/win.sh" next 1001 "$TT" 734 30 706 789 5 2222 "" 0 30 734 789)
[ "$(printf '%s\n' "$out" | head -1)" = "shown: 1002 $TT mode=iterm" ] && ok "item 2 (the web item did not count): mode=iterm" || bad "next printed: $out"
has "$(cat "$OSA_LOG")" "split|/dev/ttys099 /bin/sh " "iterm mode: split vertically of the session on the tmux client's tty"
grep -q "^display-message -p -t %7 #{client_tty}" "$TMUX_LOG" && ok "the tty asked of tmux is #{client_tty}" || bad "no client_tty call: $(cat "$TMUX_LOG")"
grep -Eq "^exec env -u TMUX .* attach -t $TT\$" "$EVSHOW_STATE/item/1002.sh" && ok "a terminal item's command is env -u TMUX tmux attach -t <Title>" || bad "launcher: $(cat "$EVSHOW_STATE/item/1002.sh")"
grep -q "^kill-pane -t %91" "$TMUX_LOG" && ok "the item before is closed by its pane id" || bad "no kill-pane: $(cat "$TMUX_LOG")"
out=$("$M/win.sh" next 1002 "$t3" 1 2 3 4 5 2222); [ "$(printf '%s\n' "$out" | head -1)" = "shown: 1003 $t3 mode=tab" ] && ok "item 3: mode=tab" || bad "next printed: $out"
has "$(cat "$OSA_LOG")" "tab|/dev/ttys099 /bin/sh " "tab mode: create tab in that session's window"
has "$(cat "$EVSHOW_STATE/item/1003.sh")" "exec less -R +2 " "a line range opens less at its first line"
grep -q "^detach-client -s $TT" "$TMUX_LOG" && ok "closing a terminal item detaches its tmux client" || bad "no detach-client"
out=$("$M/win.sh" next 1003 "$t4" 1 2 3 4 5 2222); [ "$(printf '%s\n' "$out" | head -1)" = "shown: 1004 $t4 mode=tmux" ] && ok "item 4: the rotation is back at mode=tmux" || bad "next printed: $out"
out=$("$M/win.sh" show "own k6"); [ "$(printf '%s\n' "$out" | head -1)" = "shown: 1006 own k6 mode=browser" ] && [ "$(tail -1 "$OPEN_LOG")" = "$W/own k6.html" ] && ok "a .html file goes to open: mode=browser" || bad "html show: $out / $(tail -1 "$OPEN_LOG")"
out=$("$M/win.sh" close 1005); has "$out" "closed: 1005 (the page stays in your browser" "a browser page is never closed"
[ "$(wc -l < "$OPEN_LOG" | tr -d ' ')" = 2 ] && ok "open ran once per web item" || bad "open calls: $(cat "$OPEN_LOG")"
out=$("$M/term-close.sh" "$TT" 1002); grep -q "^kill-session -t $TT" "$TMUX_LOG" && ok "term-close.sh kills the tmux session" || bad "no kill-session"
out=$("$M/win.sh" setwin 2222 0 0 1440 900 0); [ "$out" = "now unchanged" ] && ok "setwin: $out" || bad "setwin printed: $out"
out=$("$M/win.sh" close 4242); [ $? = 1 ] && has "$out" "refused: window 4242 was not opened by this session" "a window this session did not open is refused"
out=$("$M/win.sh" show nothing-here 1 2 3 4); [ $? = 1 ] && has "$out" "not shown: no window matches" "show of an unknown title: not shown, exit 1"
"$M/win.sh" bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown subcommand: exit 2" || bad "unknown subcommand should exit 2"

mac_env fixed; export EVSHOW_MAC_MODE=tab
page "$W/notes a.txt"; a=$PT; page "$W/notes a.txt"; b=$PT
o1=$("$M/win.sh" show "$a" | head -1); o2=$("$M/win.sh" next 1001 "$b" 0 0 0 0 5 x | head -1)
[ "$o1" = "shown: 1001 $a mode=tab" ] && [ "$o2" = "shown: 1002 $b mode=tab" ] && ok "EVSHOW_MAC_MODE=tab fixes the mode for the run" || bad "fixed mode printed: $o1 / $o2"

mac_env err; export EVSHOW_MAC_MODE=iterm OSA_FAIL="Not authorized to send Apple events to iTerm2. (-1743)"
page "$W/notes a.txt"
out=$("$M/win.sh" show "$PT" 734 30 706 789); rc=$?
[ "$out" = "mode iterm failed: execution error: Not authorized to send Apple events to iTerm2. (-1743)
shown: 1001 $PT mode=tmux
$(printf '%s\n' "$out" | tail -1)" ] && [ $rc = 0 ] && ok "osascript exits 1: 'mode iterm failed: <its text>', then shown in tmux mode" || bad "osascript failure printed (rc $rc): $out"
grep -q '^split-window' "$TMUX_LOG" && ok "... and the tmux pane was opened" || bad "no split-window after the failure"

mac_env hang; export EVSHOW_MAC_MODE=tab OSA_HANG=1
page "$W/notes a.txt"
if [ -n "${EVT_FAST:-}" ]; then echo "SKIP osascript silent for 10 s (EVT_FAST)"; else
  out=$("$M/win.sh" show "$PT"); has "$out" "mode tab failed: osascript gave no answer within 10s" "osascript silent for 10 s: mode tab failed"; has "$out" "shown: 1001 $PT mode=tmux" "... then shown in tmux mode"
fi

mac_env noiterm; export EVSHOW_MAC_MODE=iterm EVSHOW_ITERM_APP="$W/no-iTerm.app"
page "$W/notes a.txt"
out=$("$M/win.sh" show "$PT"); has "$out" "mode iterm failed: iTerm2 is not installed" "no iTerm2: mode iterm failed"; has "$out" "shown: 1001 $PT mode=tmux" "... then shown in tmux mode"
[ ! -s "$OSA_LOG" ] && ok "osascript was not called without iTerm2" || bad "osascript was called: $(cat "$OSA_LOG")"

mac_env notmux; export EVSHOW_MAC_MODE=iterm OSA_FAIL="boom" TMUX_FAIL="no space for new pane"
page "$W/notes a.txt"
out=$("$M/win.sh" show "$PT"); rc=$?
[ "$out" = "mode iterm failed: execution error: boom
not shown: tmux: no space for new pane" ] && [ $rc = 1 ] && ok "tmux fails too: not shown: <its text>, exit 1" || bad "double failure printed (rc $rc): $out"
mac_env nopane; unset TMUX_PANE; export EVSHOW_MAC_MODE=tmux
page "$W/notes a.txt"
out=$("$M/win.sh" show "$PT"); [ $? = 1 ] && has "$out" "not shown: tmux: the evaluator is not in a tmux pane" "outside tmux the tmux mode says so, exit 1"
! grep -q '^split-window' "$TMUX_LOG" && ok "... and splits nobody's pane" || bad "split-window ran without a pane"
out=$("$M/screen-capture.sh" x); [ $? = 1 ] && has "$out" "not captured: " "screen-capture.sh: one line, exit 1"

echo "$([ $fails -eq 0 ] && echo "all checks passed" || echo "$fails check(s) failed")"
exit $((fails > 0))
