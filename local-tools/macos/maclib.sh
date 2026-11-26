#!/bin/bash
# Sourced by the macOS win.sh / win-app.sh / term-open.sh. bash 3.2, osascript and python3 only: no Accessibility, no Screen
# Recording, no compiler, no node, no `timeout`. Automation permission (your terminal app -> Firefox / iTerm2) is the one
# macOS prompt, asked by macOS itself the first time.
#
# An ITEM is one thing the evaluator shows. The openers only record it (<state>/item/<id>: kind, title, target, state=deferred);
# the show step opens its window. <id> is the window id the helpers print and take: a number this session gave the item,
# kept for its lifetime; the app's own window id is stored beside it (wid) and never taken from a list.
# Windows are found by their unique title only, and a Firefox window is touched only while its name still holds that title,
# so the user's own Firefox is never scripted, moved or closed.
MACHERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MACTOOLS="${EVSHOW_TOOLS:-$HOME/.claude/local-tools}"   # where evsession.sh and file-page.sh are installed
[ -f "$MACTOOLS/evsession.sh" ] || MACTOOLS="$MACHERE/../common"
. "$MACTOOLS/evsession.sh"
FFAPP="${EVSHOW_FIREFOX_APP:-/Applications/Firefox.app}"   # EVSHOW_FIREFOX_APP=<path> moves the lookup (tests: a missing path = no Firefox)
FFBIN="$FFAPP/Contents/MacOS/firefox"
OSA_BIN="${EVSHOW_OSASCRIPT:-osascript}"                   # EVSHOW_OSASCRIPT=<script> stands in for osascript (tests: no window is opened)
have_firefox() { [ -x "$FFBIN" ]; }

et() { python3 -I -c 'import datetime,zoneinfo; print(datetime.datetime.now(zoneinfo.ZoneInfo("America/New_York")).strftime("%H:%M:%S.%f")[:12])'; }

mac_state() {  # sets D (this session's state dir); 1 = no session
  D=$(ev_state_dir create) || return 1
  [ -n "$D" ] || return 1
  mkdir -p "$D/item"
}

# osa <timeout-s> <AppleScript text> [args...]   (OSA_LANG=JavaScript osa ... for JXA)  -> OSA_OUT = its result; on an error or no answer in time: OSA_ERR = its text, return 1.
# A script that waits on a macOS permission prompt nobody answers is killed at the timeout.
osa() {
  local to=$1 sc=$2 o p n=0 rc; shift 2
  o="$D/osa.$$.$RANDOM"; OSA_OUT=""; OSA_ERR=""
  if [ -n "${OSA_LANG:-}" ]; then "$OSA_BIN" -l "$OSA_LANG" -e "$sc" "$@" > "$o" 2> "$o.err" &
  else "$OSA_BIN" -e "$sc" "$@" > "$o" 2> "$o.err" & fi
  p=$!
  while kill -0 "$p" 2>/dev/null; do
    if [ "$n" -ge $((to * 10)) ]; then
      kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
      OSA_ERR="no answer within ${to}s (a macOS permission prompt may be waiting)"; rm -f "$o" "$o.err"; return 1
    fi
    sleep 0.1; n=$((n + 1))
  done
  wait "$p"; rc=$?
  OSA_OUT=$(cat "$o" 2>/dev/null)
  OSA_ERR=$(tr '\n' ' ' < "$o.err" 2>/dev/null | sed -e 's/^[0-9:]*: *//' -e 's/ *$//')
  rm -f "$o" "$o.err"
  [ "$rc" -eq 0 ] || { [ -n "$OSA_ERR" ] || OSA_ERR="exit $rc"; return 1; }
  return 0
}
osa_gone() { case "$OSA_ERR" in *"-1728"*|*"-1719"*|*"-600"*|*"Invalid index"*) return 0;; esac; return 1; }   # the window (or app) is not there

# ---- items ------------------------------------------------------------------------------------------------------
inew() {  # inew <kind web|term> <title> <target> -> prints the new id
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
  local f id
  for f in $(ls "$D/item" 2>/dev/null | grep -E '^[0-9]+$' | sort -rn); do
    [ "$(iget "$f" state)" = closed ] && continue
    case "$(iget "$f" title)" in *"$1"*) echo "$f";; esac
  done
}

# ---- screen and apps --------------------------------------------------------------------------------------------
mac_geom() {  # "term X Y W H" and "item X Y W H": the terminal takes the left 51% of the main display below the menu bar
  # (and beside/above the Dock), the item the rest. NSScreen through osascript: no permission prompt.
  local v
  OSA_LANG=JavaScript osa 10 'ObjC.import("AppKit"); var s = $.NSScreen.screens.objectAtIndex(0); var f = s.frame, v = s.visibleFrame;
    [v.origin.x, f.size.height - v.origin.y - v.size.height, v.size.width, v.size.height].map(Math.round).join(" ")'
  v=$OSA_OUT
  case "$v" in
    *[0-9]" "[0-9]*) ;;
    *)  # no AppKit answer: the Finder desktop bounds below a 25-point menu bar
      osa 10 'tell application "Finder" to get bounds of window of desktop' || return 1
      v=$(echo "$OSA_OUT" | tr -d ',' | awk '{print $1, $2 + 25, $3 - $1, $4 - $2 - 25}') ;;
  esac
  echo "$v" | awk '{ tw = int($3 * 0.51); printf "term %d %d %d %d\nitem %d %d %d %d\n", $1, $2, tw, $4, $1 + tw, $2, $3 - tw, $4 }'
}
front_bundle() { lsappinfo info -only bundleid -app "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed -n 's/.*="\(.*\)".*/\1/p' | head -1; }
app_running() { pgrep -x "$1" >/dev/null 2>&1; }
term_app() {  # the app terminal items open in: the one `win.sh me` found, else iTerm2 when installed, else Terminal
  local a; a=$(cat "$D/termapp" 2>/dev/null)
  [ -n "$a" ] && { echo "$a"; return; }
  if [ -d "${EVSHOW_ITERM_APP:-/Applications/iTerm.app}" ]; then echo iTerm2; else echo Terminal; fi
}
refocus() {  # give the keyboard back: to the terminal `win.sh me` found, else to the app that was in front before the show
  local a; a=$(cat "$D/termapp" 2>/dev/null)
  if [ -n "$a" ]; then osa 5 'on run argv
tell application (item 1 of argv) to activate
end run' "$a" && return 0; fi
  [ -n "${1:-}" ] && osa 5 'on run argv
tell application id (item 1 of argv) to activate
end run' "$1"
  return 0
}
file_url() { python3 -I -c 'import sys, urllib.parse as u; print("file://" + u.quote(sys.argv[1]))' "$1"; }
