#!/bin/bash
# usage: me-two-test.sh        (run inside tmux, in the terminal you are looking at)
# Proof for `win.sh me` with one tmux session in two terminals, without opening anything visible and without taking focus:
# attaches a second, HIDDEN Windows Terminal to THIS tmux session (read-only, ignore-size: your terminal keeps its size and
# nothing can be typed through it), then runs `win.sh me` twice:
#   1. as is                                   -> expects two `me:` lines, exit 0
#   2. with the hidden terminal topmost (above yours in z-order) -> `me: took` must still name the FOREGROUND window when the
#      foreground window is one of the two (the foreground rule decides, not z-order); when neither is foreground it must name
#      the hidden one (topmost in z-order).
# Prints the helper's lines, then `me-two: PASS` (exit 0) or `me-two: FAIL <why>` (exit 1). The hidden terminal is closed at the end.
# While a full-screen game runs win-app.sh refuses: `me-two: not run: <its line>`, exit 3.
set -u
T="$HOME/.claude/local-tools"
[ -n "${TMUX:-}" ] || { echo "me-two: FAIL not inside tmux"; exit 1; }
ses=$(tmux display-message -p '#{session_name}'); tok="me2-$RANDOM$RANDOM"
out=$("$T/win-app.sh" --hidden --title "$tok" wt -w new -p "${TERM_OPEN_PROFILE:-Ubuntu}" --title "$tok" --suppressApplicationTitle \
  wsl.exe -d "${WSL_DISTRO_NAME:-Ubuntu}" -- tmux attach -t "=$ses" -f ignore-size,read-only 2>&1 | tr -d '\r'); rc=${PIPESTATUS[0]}
h=$(printf '%s\n' "$out" | awk '/^hidden: /{print $2; exit}')
[ "$rc" -eq 3 ] && { echo "me-two: not run: $(printf '%s\n' "$out" | grep '^not hidden' | tail -1)"; exit 3; }
[ -n "$h" ] || { echo "me-two: FAIL second terminal not opened: $(printf '%s\n' "$out" | grep -v '^hide-log' | tail -1)"; exit 1; }
trap '"$T/win.sh" untop "$h" >/dev/null 2>&1; "$T/win.sh" close "$h" >/dev/null 2>&1' EXIT
for _ in $(seq 1 20); do [ "$(tmux list-clients -t "=$ses" | wc -l)" -ge 2 ] && break; sleep 0.5; done
echo "clients on session $ses: $(tmux list-clients -t "=$ses" | wc -l); hidden terminal $h"
bad=""
run() {  # $1 = label; sets took, n
  local o r fg; fg=$("$T/win.sh" fginfo | tr -d '\r' | awk '{print $1}')
  o=$("$T/win.sh" me 2>&1); r=$?; printf '%s\n' "$o" | sed "s/^/$1: /"; echo "$1: rc=$r foreground=$fg"
  took=$(printf '%s\n' "$o" | sed -n 's/^me: took \([0-9]*\) of \([0-9]*\)$/\1 \2/p'); first=$(printf '%s\n' "$o" | awk '/^me: [0-9]/{print $2; exit}')
  [ "$r" -eq 0 ] || bad="$bad; $1 exit $r"
  [ "$(printf '%s\n' "$o" | grep -c '^me: ')" -eq 2 ] || bad="$bad; $1 printed $(printf '%s\n' "$o" | grep -c '^me: ') me: lines"
  [ "${took#* }" = 2 ] || bad="$bad; $1 saw '${took#* }' windows, want 2"
  [ "${took% *}" = "$first" ] || bad="$bad; $1 took ${took% *} but the me: line names $first"
  FG=$fg; TOOK=${took% *}
}
run "as-is"; other=$TOOK
"$T/win.sh" front "$h" >/dev/null 2>&1
run "hidden-on-top"
if [ "$FG" != "$h" ] && [ "$FG" = "$other" ]; then [ "$TOOK" = "$FG" ] || bad="$bad; hidden-on-top took $TOOK, want the foreground $FG"; echo "branch: foreground"
else [ "$TOOK" = "$h" ] || bad="$bad; hidden-on-top took $TOOK, want the topmost $h (neither window is foreground)"; echo "branch: topmost in z-order"; fi
[ -z "$bad" ] && { echo "me-two: PASS"; exit 0; }
echo "me-two: FAIL ${bad#; }"; exit 1
