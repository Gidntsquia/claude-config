#!/bin/bash
# usage: term-open.sh <Title> <dir> <command...>   (Title must be unique; random suffix advised)
# macOS: makes a detached tmux session <Title> you own in <dir>, runs <command> in it, records the terminal item and puts
# NOTHING on screen; prints "opened <Title> id=<id> (deferred)". `win.sh show "<Title>" ...` shows a static page of what the
# session holds at that moment (`tmux capture-pane -e -p -S -`, colours kept) in a Firefox of its own.
# Drive it only via: tmux send-keys -t <Title> ...   Close: term-close.sh <Title> <id>.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$here/maclib.sh"
[ $# -ge 2 ] || { echo "usage: term-open.sh <Title> <dir> <command...>" >&2; exit 2; }
t="$1"; dir="$2"; shift 2
mac_state || { echo "not opened: no session state dir (set EVSHOW_STATE)"; exit 1; }
command -v "$TMUX_BIN" >/dev/null 2>&1 || { echo "not opened: tmux is not installed"; exit 1; }
"$TMUX_BIN" has-session -t "=$t" 2>/dev/null && { echo "not opened: a tmux session named $t already exists (it is someone else's)"; exit 1; }
[ -d "$dir" ] || { echo "not opened: no such folder: $dir"; exit 1; }
e=$("$TMUX_BIN" new-session -d -s "$t" -c "$dir" -x 200 -y 50 2>&1) || { echo "not opened: tmux: $e"; exit 1; }
if [ $# -gt 0 ]; then "$TMUX_BIN" send-keys -t "$t" C-u; "$TMUX_BIN" send-keys -t "$t" -l "$*"; "$TMUX_BIN" send-keys -t "$t" Enter; fi
id=$(inew term "$t" "$dir")
echo "opened $t id=$id (deferred)"
