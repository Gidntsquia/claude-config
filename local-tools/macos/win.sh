#!/bin/bash
# macOS show helper of the evaluator. Same subcommands, output-line prefixes and exit codes (1 failed, 2 usage) as the WSL
# win.sh; a window id stands where HWND does (see maclib.sh: the id is this session's number for the item).
# Items are shown INSIDE the terminal the evaluator runs in. No window is moved or sized (iTerm2 may be full screen), no
# browser is started, and X Y W H are accepted and ignored.
#   win.sh me                           -> where the evaluator runs: saves its tmux pane and the tmux client's tty for the watcher;
#                                          prints "me: <pane or tty> 0 0 0 0 0"; none: exit 1 "not found: 0 windows hold ..."
#   win.sh show "<title>" X Y W H [s]   -> shows the recorded item whose title holds <title> (the openers only record it);
#                                          prints "shown: <id> <title> mode=<mode>"; exit 1 "not shown: <cause>"
#   win.sh start "<title>" X Y W H s TX TY TW TH <term id> [picture.png]   -> show (evshow.sh, first item)
#   win.sh next <old id> "<title>" X Y W H s <term id> [picture.png] [TX TY TW TH] -> close the old item, then show (evshow.sh)
#   win.sh close <id>                   -> close what this session opened for that item; prints "closed: <id>"
#   win.sh find "<title>"               -> "<id> <title>" of exactly ONE item of this session; else exit 1 "not found: N windows hold ..."
#   win.sh close-cloaked ["<title>"]    -> forget every item (only those under <title>) that was recorded and never shown
#   win.sh setwin ...                   -> prints "now unchanged" (the terminal is never moved)
#   win.sh front|untop|place|rect|geom|list-topmost|quit -> nothing to do here; exit 0
# What a show runs:
#   terminal item (term-open.sh)        `env -u TMUX tmux attach -t <Title>`
#   file page (file-page.sh)            `less -R <its source file>`
#   http(s) URL, .html file             `open "<it>"` only: the default browser, never scripted or closed; mode=browser
# Modes, for file and terminal items:
#   tmux    tmux split-window -h -d, 50%, right of the evaluator's pane; closed with kill-pane
#   iterm   iTerm2 `split vertically` of the session whose tty is the tmux client's (#{client_tty}); the keyboard stays with the evaluator
#   tab     iTerm2 `create tab` in that session's window, left selected (the evaluator's tab is behind it until you switch back)
#           both are closed through the item's id: its command is ended and the iTerm2 session on its tty is closed
# The Nth file or terminal item of a run uses tmux, iterm, tab, tmux, ... (web items do not count).
# EVSHOW_MAC_MODE=tmux|iterm|tab fixes one mode for the run.
# `shown:` means the open command exited 0; nobody checks the screen and there is no picture.
# iTerm2 absent or not running, or osascript failing or silent for 10 s: one line `mode <mode> failed: <its text>`, then the
# item is shown in tmux mode. tmux failing too: `not shown: <its text>`, exit 1.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$here/maclib.sh"
mac_state || { echo "error: no session state dir (no transcript for this cwd; set EVSHOW_STATE)"; exit 1; }

# ---- AppleScript, every value through argv: (1) a tty, (2) the command ---------------------------------------------
# Finding the session is waited for (an error or 10 s of silence fails the mode). iTerm2's reply to the split or the tab
# is not: iTerm2 3.7 opened the tab and never answered `create tab ... command`, and answered a split only sometimes
# (seen 2026-11-26, window in full screen). The pane or tab counts as open when the command it was given has started
# (open_iterm waits for the launcher's pid file).
S_HEAD='on run argv
tell application "iTerm2"
repeat with w in windows
repeat with tb in tabs of w
repeat with s in sessions of tb
'
S_TAIL='end repeat
end repeat
end repeat
end tell
error "no iTerm2 session holds " & (item 1 of argv)
end run'
S_SPLIT="$S_HEAD"'if (tty of s) is (item 1 of argv) then
ignoring application responses
tell s to split vertically with default profile command (item 2 of argv)
tell s to select
end ignoring
return "sent"
end if
'"$S_TAIL"
S_TAB="$S_HEAD"'if (tty of s) is (item 1 of argv) then
ignoring application responses
tell w to create tab with default profile command (item 2 of argv)
end ignoring
return "sent"
end if
'"$S_TAIL"
S_CLOSE="$S_HEAD"'if (tty of s) is (item 1 of argv) then
tell s to close
return "closed"
end if
'"$S_TAIL"

launcher() {  # launcher <id>: writes <state>/item/<id>.sh (records its pid, then runs the item's command); CMD = how to run it
  local id=$1 f="$D/item/$1.sh" tm line
  rm -f "$D/item/$id.pid"
  {
    echo '#!/bin/sh'
    printf 'echo $$ > %q\n' "$D/item/$id.pid"
    if [ "$(iget "$id" kind)" = term ]; then
      tm=$(command -v "$TMUX_BIN" 2>/dev/null || echo "$TMUX_BIN")   # the full path: a command iTerm2 starts has a short PATH
      printf 'exec env -u TMUX %q attach -t %q\n' "$tm" "$(iget "$id" title)"
    else
      line=$(iget "$id" line)
      printf 'exec less -R %s%q\n' "${line:+"+$line "}" "$(iget "$id" target)"
    fi
  } > "$f"
  CMD="/bin/sh $(printf '%q' "$f")"
}

open_tmux() {  # -> REF = the new pane's id; 1 = ERR
  local pane out
  pane=$(my_pane)
  [ -n "$pane" ] || { ERR="tmux: the evaluator is not in a tmux pane"; return 1; }
  out=$("$TMUX_BIN" split-window -h -d -l '50%' -t "$pane" -P -F '#{pane_id}' "$CMD" 2>&1) \
    || out=$("$TMUX_BIN" split-window -h -d -t "$pane" -P -F '#{pane_id}' "$CMD" 2>&1) \
    || { ERR="tmux: $(printf '%s' "$out" | tr '\n' ' ')"; return 1; }
  REF=$out
}
item_tty() {  # item_tty <id>: the tty its command runs on (from the launcher's pid); empty = it never started
  local pid t
  pid=$(cat "$D/item/$1.pid" 2>/dev/null); case "$pid" in ''|*[!0-9]*) return 0;; esac
  t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' '); case "$t" in ''|'??'|'?') return 0;; esac
  echo "/dev/$t"
}
iterm_close() {  # iterm_close <id> <tty>: ends the item's command, then closes the iTerm2 session on that tty; never the evaluator's own
  local pid; pid=$(cat "$D/item/$1.pid" 2>/dev/null)
  case "$pid" in ''|*[!0-9]*) ;; *) kill -HUP "$pid" 2>/dev/null;; esac
  [ -n "$2" ] && [ "$2" != "$(my_tty)" ] || return 0
  sleep 0.3; osa 10 "$S_CLOSE" "$2" >/dev/null 2>&1; return 0   # a session that is already gone is closed
}
open_iterm() {  # open_iterm <iterm|tab> <id> -> REF = the tty of the new iTerm2 session; 1 = ERR (nothing of this try is left open)
  local tty n=0 t
  iterm_ready || { ERR=$ITERM_WHY; return 1; }
  tty=$(my_tty); [ -n "$tty" ] || { ERR="no tty found for this terminal"; return 1; }
  if [ "$1" = tab ]; then osa 10 "$S_TAB" "$tty" "$CMD"; else osa 10 "$S_SPLIT" "$tty" "$CMD"; fi || ERR=$OSA_ERR
  if [ -z "$ERR" ]; then   # the command it was given has started = the pane or tab is open (the stand-in osascript of the tests starts none)
    while [ ! -s "$D/item/$2.pid" ] && [ -z "${EVSHOW_OSASCRIPT:-}" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    [ -s "$D/item/$2.pid" ] || [ -n "${EVSHOW_OSASCRIPT:-}" ] || ERR="iTerm2 started no $([ "$1" = tab ] && echo tab || echo pane) within 10s"
  fi
  t=$(item_tty "$2")
  if [ -n "$ERR" ]; then [ -n "$t" ] && iterm_close "$2" "$t"; return 1; fi   # it opened late or half: closed before the tmux try
  REF=$t
}
pick_mode() {  # the mode of the next file or terminal item
  local n
  case "${EVSHOW_MAC_MODE:-}" in tmux|iterm|tab) echo "$EVSHOW_MAC_MODE"; return;; esac
  n=$(cat "$D/modeidx" 2>/dev/null || echo 0); case "$n" in ''|*[!0-9]*) n=0;; esac
  echo $((n + 1)) > "$D/modeidx"
  case $((n % 3)) in 0) echo tmux;; 1) echo iterm;; 2) echo tab;; esac
}

do_close() {  # do_close <id>: 0 closed (or nothing to close), 1 not ours / already closed
  local id=$1 mode ref pid
  if ! ihas "$id"; then
    case "$id" in ''|0) return 0;; esac
    echo "refused: window $id was not opened by this session"; return 1
  fi
  case "$(iget "$id" state)" in
    deferred) iset "$id" state closed; echo "closed: $id (recorded, never opened)"; return 0;;
    closed) echo "not found: window $id is already closed"; return 1;;
  esac
  mode=$(iget "$id" mode); ref=$(iget "$id" ref)
  iset "$id" state closed
  [ "$mode" = browser ] && { echo "closed: $id (the page stays in your browser: it is yours to close)"; return 0; }
  [ "$(iget "$id" kind)" = term ] && "$TMUX_BIN" detach-client -s "$(iget "$id" title)" 2>/dev/null
  case "$mode" in
    tmux) [ -n "$ref" ] && "$TMUX_BIN" kill-pane -t "$ref" 2>/dev/null;;
    iterm|tab) iterm_close "$id" "$ref";;
  esac
  rm -f "$D/item/$id.pid" "$D/item/$id.sh"
  echo "closed: $id"; return 0
}

do_show() {  # do_show <title> <old id to close or ""> -> 0 shown, 1 not shown
  local title=$1 old=${2:-} id kind mode e
  id=$(ifind "$title" | head -1)
  [ -n "$old" ] && [ "$old" != "$id" ] && do_close "$old" > /dev/null   # the item before closes first: its pane's room comes back
  [ -n "$id" ] || { echo "not shown: no window matches '$title' (this session recorded no item under that title)"; return 1; }
  if [ "$(iget "$id" state)" = shown ]; then echo "shown: $id $title mode=$(iget "$id" mode)"; echo "shown-at $(et)"; return 0; fi
  kind=$(iget "$id" kind)
  if [ "$kind" = web ]; then
    e=$("$OPEN_BIN" "$(iget "$id" target)" 2>&1) || { echo "not shown: open: $(printf '%s' "$e" | tr '\n' ' ')"; return 1; }
    mode=browser; REF=""
  else
    mode=$(pick_mode); launcher "$id"; ERR=""; REF=""
    case "$mode" in
      tmux) open_tmux || { echo "not shown: $ERR"; return 1; };;
      *) if ! open_iterm "$mode" "$id"; then
           echo "mode $mode failed: $ERR"
           mode=tmux; open_tmux || { echo "not shown: $ERR"; return 1; }
         fi;;
    esac
  fi
  iset "$id" mode "$mode"; iset "$id" ref "$REF"; iset "$id" state shown
  echo "shown: $id $title mode=$mode"; echo "shown-at $(et)"
  return 0
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  me)
    pane=${TMUX_PANE:-}; tty=""
    rm -f "$D/pane" "$D/ctty"
    if [ -n "$pane" ]; then echo "$pane" > "$D/pane"; fi
    tty=$(my_tty)
    [ -n "$pane" ] || [ -n "$tty" ] || { echo "not found: 0 windows hold this session (no tmux pane and no tty)"; exit 1; }
    [ -n "$tty" ] && echo "$tty" > "$D/ctty"
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
    done; exit 0;;
  setwin) echo "now unchanged";;
  front|untop|place|rect|geom|list-topmost|quit) exit 0;;
  *) sed -n '2,31p' "$0"; exit 2;;
esac
