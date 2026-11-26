#!/bin/bash
# Sourced by the macOS win.sh / win-app.sh / term-open.sh. bash 3.2, tmux, osascript and python3 only: no Accessibility, no
# Screen Recording, no compiler, no node, no `timeout`. Automation permission (your terminal app -> iTerm2) is the one macOS
# prompt, asked by macOS itself the first time, and only the `iterm` and `tab` modes need it.
#
# An ITEM is one thing the evaluator shows. The openers only record it (<state>/item/<id>: kind, title, target, state=deferred);
# the show step opens it INSIDE the terminal the evaluator runs in (win.sh: a tmux pane, an iTerm2 split pane or an iTerm2 tab),
# or hands a web page to the default browser with `open`. <id> is the window id the helpers print and take: a number this
# session gave the item, kept for its lifetime. No tool moves or sizes a window, and only what this session opened is closed.
MACHERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MACTOOLS="${EVSHOW_TOOLS:-$HOME/.claude/local-tools}"   # where evsession.sh and file-page.sh are installed
[ -f "$MACTOOLS/evsession.sh" ] || MACTOOLS="$MACHERE/../common"
. "$MACTOOLS/evsession.sh"
OSA_BIN="${EVSHOW_OSASCRIPT:-osascript}"   # EVSHOW_OSASCRIPT=<script> stands in for osascript (tests: nothing is opened)
TMUX_BIN="${EVSHOW_TMUX:-tmux}"            # EVSHOW_TMUX=<script> stands in for tmux (tests)
OPEN_BIN="${EVSHOW_OPEN:-open}"            # EVSHOW_OPEN=<script> stands in for open (tests)
ITERM_APP="${EVSHOW_ITERM_APP:-/Applications/iTerm.app}"   # EVSHOW_ITERM_APP=<path> moves the lookup (tests: a missing path = no iTerm2)

et() { python3 -I -c 'import datetime,zoneinfo; print(datetime.datetime.now(zoneinfo.ZoneInfo("America/New_York")).strftime("%H:%M:%S.%f")[:12])'; }

mac_state() {  # sets D (this session's state dir); 1 = no session
  D=$(ev_state_dir create) || return 1
  [ -n "$D" ] || return 1
  mkdir -p "$D/item"
}

# osa <timeout-s> <AppleScript text> [args...] -> OSA_OUT = its result; on an error or no answer in time: OSA_ERR = its text, return 1.
# A script that waits on a macOS permission prompt nobody answers is killed at the timeout.
osa() {
  local to=$1 sc=$2 o p n=0 rc; shift 2
  o="$D/osa.$$.$RANDOM"; OSA_OUT=""; OSA_ERR=""
  "$OSA_BIN" -e "$sc" "$@" > "$o" 2> "$o.err" &
  p=$!
  while kill -0 "$p" 2>/dev/null; do
    if [ "$n" -ge $((to * 10)) ]; then
      kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
      OSA_ERR="osascript gave no answer within ${to}s (a macOS permission prompt may be waiting)"; rm -f "$o" "$o.err"; return 1
    fi
    sleep 0.1; n=$((n + 1))
  done
  wait "$p"; rc=$?
  OSA_OUT=$(cat "$o" 2>/dev/null)
  OSA_ERR=$(tr '\n' ' ' < "$o.err" 2>/dev/null | sed -e 's/^[0-9:]*: *//' -e 's/ *$//')
  rm -f "$o" "$o.err"
  [ "$rc" -eq 0 ] || { [ -n "$OSA_ERR" ] || OSA_ERR="osascript exit $rc"; return 1; }
  return 0
}

# ---- items ------------------------------------------------------------------------------------------------------
inew() {  # inew <kind file|term|web> <title> <target> -> prints the new id
  local n id
  n=$(cat "$D/item/.n" 2>/dev/null || echo 1000); id=$((n + 1)); echo "$id" > "$D/item/.n"
  { echo "kind=$1"; echo "title=$2"; echo "target=$3"; echo "state=deferred"; } > "$D/item/$id"
  echo "$id|$2" >> "$D/launched.txt"
  echo "$id"
}
iget() { sed -n "s/^$2=//p" "$D/item/$1" 2>/dev/null | head -1; }
iset() {  # iset <id> <key> <value>
  local f="$D/item/$1"; [ -f "$f" ] || return 1
  grep -v "^$2=" "$f" > "$f.tmp"; echo "$2=$3" >> "$f.tmp"; mv "$f.tmp" "$f"
}
ihas() { case "$1" in ''|*[!0-9]*) return 1;; esac; [ -f "$D/item/$1" ]; }
ifind() {  # ifind <title text> -> ids (newest first) of this session's items, not closed, whose title holds the text
  local f
  for f in $(ls "$D/item" 2>/dev/null | grep -E '^[0-9]+$' | sort -rn); do
    [ "$(iget "$f" state)" = closed ] && continue
    case "$(iget "$f" title)" in *"$1"*) echo "$f";; esac
  done
}

# ---- where the evaluator runs -----------------------------------------------------------------------------------
my_pane() {  # the tmux pane the evaluator runs in: saved by `win.sh me`, else this process's own
  local p; p=$(cat "$D/pane" 2>/dev/null); echo "${p:-${TMUX_PANE:-}}"
}
my_tty() {  # the tty iTerm2 knows this terminal by: the tmux client's tty; outside tmux the tty of the nearest ancestor
  local t pane pp _
  t=$(cat "$D/ctty" 2>/dev/null); [ -n "$t" ] && { echo "$t"; return; }
  pane=$(my_pane)
  if [ -n "$pane" ]; then t=$("$TMUX_BIN" display-message -p -t "$pane" '#{client_tty}' 2>/dev/null); [ -n "$t" ] && { echo "$t"; return; }; fi
  [ -n "${TMUX:-}" ] && return 0   # in tmux with no client attached: no tty
  pp=$$; for _ in 1 2 3 4 5 6 7 8 9 10; do
    t=$(ps -o tty= -p "$pp" 2>/dev/null | tr -d ' '); case "$t" in ''|'??'|'?') ;; *) echo "/dev/$t"; return;; esac
    pp=$(ps -o ppid= -p "$pp" 2>/dev/null | tr -d ' '); [ "${pp:-1}" -gt 1 ] 2>/dev/null || break; done
}
iterm_ready() {  # 0 = iTerm2 is installed and running; else ITERM_WHY says which. A stand-in osascript counts as running.
  [ -d "$ITERM_APP" ] || { ITERM_WHY="iTerm2 is not installed"; return 1; }
  [ -n "${EVSHOW_OSASCRIPT:-}" ] || pgrep -x iTerm2 >/dev/null 2>&1 || { ITERM_WHY="iTerm2 is not running"; return 1; }
  return 0
}
