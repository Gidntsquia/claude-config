#!/bin/bash
# usage: term-open.sh <Title> <dir> <command...>   (Title must be unique; random suffix advised)
# macOS: makes a detached tmux session <Title> you own in <dir>, runs <command> in it, records the terminal item and opens NO
# window; prints "opened <Title> id=<id> (deferred)". `win.sh show "<Title>" ...` opens the window: iTerm2
# `create window with default profile command "tmux attach -t <Title>"`, or Terminal.app `do script` without iTerm2.
# Drive it only via: tmux send-keys -t <Title> ...   Close: term-close.sh <Title> <id>.
# When the terminal app is running and osascript cannot reach it (Automation refused), ONE line `not opened: <its text>`, exit 1.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$here/maclib.sh"
[ $# -ge 2 ] || { echo "usage: term-open.sh <Title> <dir> <command...>" >&2; exit 2; }
t="$1"; dir="$2"; shift 2
mac_state || { echo "not opened: no session state dir (set EVSHOW_STATE)"; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "not opened: tmux is not installed"; exit 1; }
tmux has-session -t "=$t" 2>/dev/null && { echo "not opened: a tmux session named $t already exists (it is someone else's)"; exit 1; }
[ -d "$dir" ] || { echo "not opened: no such folder: $dir"; exit 1; }
app=$(term_app)
if app_running "$app"; then   # can osascript reach the app that will hold the window? (asks nothing when it is not running)
  osa 10 "tell application \"$app\" to count windows" || { echo "not opened: $OSA_ERR"; exit 1; }
fi
e=$(tmux new-session -d -s "$t" -c "$dir" -x 200 -y 50 2>&1) || { echo "not opened: tmux: $e"; exit 1; }
if [ $# -gt 0 ]; then tmux send-keys -t "$t" C-u; tmux send-keys -t "$t" -l "$*"; tmux send-keys -t "$t" Enter; fi
id=$(inew term "$t" "$dir")
echo "opened $t id=$id (deferred)"
