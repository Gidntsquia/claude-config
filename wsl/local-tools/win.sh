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
#   win.sh me                           -> YOUR terminal: sets the tmux/OSC title to ev-<random> AND shows it as a tmux status message
#                                          on this pane's client; finds exactly one Windows Terminal window holding it (title match,
#                                          else UI Automation text of its TermControl: a tab renamed by hand ignores titles), restores
#                                          the title, saves "HWND L T W H MAX" in <state>/term; prints "me: HWND L T W H MAX [(text marker)]"
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
  # Marker routes, all at once: tmux window name + OSC title on the pane tty (title match) and a tmux status message on this
  # pane's client (text match: a WT tab renamed by hand ignores application titles). No /dev/tty needed (the Bash tool has none).
  D=$(ev_state_dir create); P="$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")"
  if [ -n "${EVSHOW_TERMHWND:-}" ]; then   # tests: the harness names a stand-in terminal; report and record it instead of ours
    out=$("$0" wininfo "$EVSHOW_TERMHWND" | tr -d '\r'); case "$out" in *"no longer exists"*|*rror*) echo "me: not found (EVSHOW_TERMHWND=$EVSHOW_TERMHWND: $out)"; exit 1;; esac
    echo "me: $out (EVSHOW_TERMHWND)"; printf '%s\n' "$out" > "$D/term"; exit 0
  fi
  pane=${TMUX_PANE:-}; if [ -z "$pane" ] && [ -n "${TMUX:-}" ]; then pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null); fi
  if [ -z "$pane" ]; then   # not in a tmux env (a subshell of the session): the nearest ancestor on a pts is the pane
    pp=$$; for _ in 1 2 3 4 5 6 7 8; do pp=$(awk '{print $4}' "/proc/$pp/stat" 2>/dev/null) || break; [ "${pp:-1}" -gt 1 ] || break
      t=$(readlink "/proc/$pp/fd/0" 2>/dev/null); case "$t" in /dev/pts/*) pane=$(tmux list-panes -a -F '#{pane_tty} #{pane_id}' 2>/dev/null | awk -v t="$t" '$1==t{print $2}'); ptty=$t; break;; esac; done; fi
  ctty=""; [ -n "$pane" ] && { ctty=$(tmux display-message -p -t "$pane" '#{client_tty}' 2>/dev/null); ptty=$(tmux display-message -p -t "$pane" '#{pane_tty}' 2>/dev/null); }
  oldw=""; auto=""; [ -n "$pane" ] && { oldw=$(tmux display-message -p -t "$pane" '#W' 2>/dev/null); auto=$(tmux show-window-options -t "$pane" -v automatic-rename 2>/dev/null); }
  for try in 1 2 3; do m="ev-$RANDOM$RANDOM"
    [ -n "$pane" ] && tmux rename-window -t "$pane" "$m" 2>/dev/null
    [ -n "$ptty" ] && printf '\033]0;%s\007' "$m" > "$ptty" 2>/dev/null
    [ -n "$ctty" ] && tmux display-message -c "$ctty" -d 6000 "$m" 2>/dev/null
    sleep 0.4
    out=$(WSLENV="${WSLENV:+$WSLENV:}WINCTL_LINE" WINCTL_LINE="me|$m" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$P" | tr -d '\r'); rc=$?
    [ -n "$ctty" ] && tmux display-message -c "$ctty" -d 1 "" 2>/dev/null
    [ $rc -eq 0 ] && break; [ $try -lt 3 ] && echo "retry $try: $out" >&2
  done
  if [ -n "$pane" ]; then tmux rename-window -t "$pane" "${oldw:-bash}" 2>/dev/null; [ "${auto:-on}" = on ] && tmux set-window-option -t "$pane" automatic-rename on 2>/dev/null; fi
  [ -n "$ptty" ] && printf '\033]0;\007' > "$ptty" 2>/dev/null
  printf '%s\n' "$out"; [ $rc -eq 0 ] && { o=${out#me: }; printf '%s\n' "${o%% (*}" > "$D/term"; }; exit $rc
fi
IFS='|'
WSLENV="${WSLENV:+$WSLENV:}WINCTL_LINE" WINCTL_LINE="$*" exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")"
