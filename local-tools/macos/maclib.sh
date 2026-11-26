#!/bin/bash
# Sourced by the macOS win.sh / win-app.sh / term-open.sh. bash 3.2, tmux, python3 and Firefox only: no Accessibility, no
# Screen Recording, no AppleScript, no compiler, no node, no `timeout`. Nothing here asks macOS for a permission.
#
# An ITEM is one thing the evaluator shows. The openers only record it (<state>/item/<id>: kind, title, target, state=deferred);
# the show step (win.sh) opens it as a page in a Firefox of its own: a separate instance on a fresh profile under the state
# dir, whose pid is recorded and killed when the next item is shown. <id> is the window id the helpers print and take: a
# number this session gave the item, kept for its lifetime. No tool moves or sizes a window, and only what this session
# started is closed: the user's own Firefox is never signalled.
MACHERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MACTOOLS="${EVSHOW_TOOLS:-$HOME/.claude/local-tools}"   # where evsession.sh and file-page.sh are installed
[ -f "$MACTOOLS/evsession.sh" ] || MACTOOLS="$MACHERE/../common"
. "$MACTOOLS/evsession.sh"
TMUX_BIN="${EVSHOW_TMUX:-tmux}"            # EVSHOW_TMUX=<script> stands in for tmux (tests)
OPEN_BIN="${EVSHOW_OPEN:-open}"            # EVSHOW_OPEN=<script> stands in for open (tests)
FF_APP="${EVSHOW_FIREFOX_APP:-/Applications/Firefox.app}"   # EVSHOW_FIREFOX_APP=<dir> moves the lookup (tests: a stand-in, or a missing path = no Firefox)

et() { python3 -I -c 'import datetime,zoneinfo; print(datetime.datetime.now(zoneinfo.ZoneInfo("America/New_York")).strftime("%H:%M:%S.%f")[:12])'; }

mac_state() {  # sets D (this session's state dir); 1 = no session
  D=$(ev_state_dir create) || return 1
  [ -n "$D" ] || return 1
  mkdir -p "$D/item"
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
my_tty() {  # the tty of the nearest ancestor that has one (the evaluator's terminal outside tmux)
  local t pp _
  pp=$$; for _ in 1 2 3 4 5 6 7 8 9 10; do
    t=$(ps -o tty= -p "$pp" 2>/dev/null | tr -d ' '); case "$t" in ''|'??'|'?') ;; *) echo "/dev/$t"; return;; esac
    pp=$(ps -o ppid= -p "$pp" 2>/dev/null | tr -d ' '); [ "${pp:-1}" -gt 1 ] 2>/dev/null || break; done
}
