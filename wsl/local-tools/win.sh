#!/bin/bash
# usage (all window actions take an HWND; title lookup only in find/show):
#   win.sh fginfo                       -> "HWND L T W H MAX" of the foreground window (read once at start)
#   win.sh setwin HWND L T W H MAX      -> put that window back exactly; prints "now L T W H MAX"; exit 1 if gone
#   win.sh find "<title>"               -> "HWND title" of exactly ONE visible window; else exit 1 + candidates
#   win.sh show "<title>" X Y W H [s]   -> poll for exactly one match, un-minimize, place, topmost, no focus;
#                                          prints "shown: HWND title L T W H"; exit 1 "not shown: reason"
#   win.sh prep "<title>" [s]          -> wait for exactly one match, register it, minimize it; prints "prepped: HWND title"
#   win.sh bottom HWND                  -> send an item you launched to the bottom of the z-order (HWND_BOTTOM)
#   EVSHOW_BEHIND=1 (env): show/start/next/front place + un-minimize, then put the window at the very bottom of the
#                          z-order (HWND_BOTTOM: below every user window; never topmost, never activated)
#   win.sh min HWND                     -> minimize an item you launched
#   (show takes an optional 7th arg: your terminal HWND; fails if the item overlaps it)
#   win.sh front|untop|close HWND       -> topmost on / topmost off / close
#   win.sh place HWND X Y W H           -> un-minimize, move, size (no focus)
#   win.sh rect HWND | fgrect | placefg X Y W H | list-topmost | list-all
#   win.sh list-z                       -> every visible titled window top to bottom: "HWND|topmost|cloaked|title"
#   win.sh me                           -> YOUR terminal: sets the tmux/OSC title to ev-<random>, finds exactly one window holding it,
#                                          restores the title, saves "HWND L T W H MAX" in <state>/term; prints "me: HWND L T W H MAX"
#   win.sh zlog <seconds>               -> every 100 ms "t HH:MM:SS.mmm" + "HWND|topmost|cloaked|iconic|L T W H|title" per window
#   win.sh close-cloaked                -> close every window this session registered that is still cloaked (never shown)
# The registry of windows THIS SESSION launched (front/place/close refuse others) is <state dir>/launched.txt; the
# state dir is per session (evsession.sh: EVSHOW_STATE, else ~/.claude/local-tools/evshow.state/<Claude session id>).
# Args are joined with '|' into ONE argument so negative numbers survive powershell -File.
grep -qi microsoft /proc/version 2>/dev/null || { echo "win.sh: WSL only (this is $(uname))" >&2; exit 1; }
. "$HOME/.claude/local-tools/evsession.sh"
ev_export || { echo "error: no session state dir (no transcript for this cwd; set EVSHOW_STATE)"; exit 1; }
case "${1:-}" in show|start|next|front|place|placefg|setwin|restore) "$HOME/.claude/local-tools/game-guard.sh" "win.sh $*" >/dev/null && { echo "not shown: a full-screen game is running (game-guard.sh)"; exit 3; };; esac
if [ "${1:-}" = me ]; then
  D=$(ev_state_dir create); m="ev-$RANDOM$RANDOM"
  oldw=$(tmux display-message -p '#W' 2>/dev/null); auto=$(tmux show-window-options -v automatic-rename 2>/dev/null)
  tmux rename-window "$m" 2>/dev/null; printf '\033]0;%s\007' "$m" > /dev/tty 2>/dev/null; sleep 0.4
  out=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")" "me|$m" | tr -d '\r'); rc=$?
  if [ -n "$oldw" ]; then tmux rename-window "$oldw" 2>/dev/null; [ "${auto:-on}" = on ] && tmux set-window-option automatic-rename on 2>/dev/null; fi
  printf '\033]0;\007' > /dev/tty 2>/dev/null
  printf '%s\n' "$out"; [ $rc -eq 0 ] && printf '%s\n' "${out#me: }" > "$D/term"; exit $rc
fi
IFS='|'
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")" "$*"
