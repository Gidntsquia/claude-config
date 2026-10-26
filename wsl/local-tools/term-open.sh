#!/bin/bash
# usage: term-open.sh <Title> <dir> <command...>   (Title must be unique; random suffix advised)
# Opens a NEW Windows Terminal window titled <Title>, attached to a tmux session <Title> you own,
# runs <command>, prints "opened <Title> HWND=<hwnd>". Exit 1 + candidates if the title is not exactly one window.
# Drive it only via: tmux send-keys -t <Title> ...   Place/show it with: win.sh show "<Title>" X Y W H
# The window is registered in THIS session's launched.txt (evsession.sh). EVSHOW_WT=<path> overrides wt.exe (tests).
# The window uses the Windows Terminal profile $TERM_OPEN_PROFILE (default Ubuntu) for its font and colors;
# without -p, wt.exe gives a bare command line the base settings (no Nerd Font: icons show as blanks).
set -e
# WSL only: needs wt.exe, wsl.exe and win.sh (PowerShell window control); Windows and macOS have none of these.
grep -qi microsoft /proc/version 2>/dev/null || { echo "term-open.sh: WSL only (this is $(uname))"; exit 1; }
t="$1"; dir="$2"; shift 2
W="$HOME/.claude/local-tools/win.sh"
WT="${EVSHOW_WT:-$(bash "$HOME/.claude/local-tools/win-app.sh" --path wt)}"
[ -x "$WT" ] || { echo "wt.exe not found: $WT"; exit 1; }
tmux new-session -d -s "$t" -c "$dir" -x 200 -y 50
"$WT" -w new -p "${TERM_OPEN_PROFILE:-Ubuntu}" --title "$t" --suppressApplicationTitle \
  wsl.exe -d "${WSL_DISTRO_NAME:-Ubuntu}" -- tmux attach -t "$t" >/dev/null 2>&1 || { echo "wt.exe failed (exit $?)"; tmux kill-session -t "$t" 2>/dev/null; exit 1; }
for i in $(seq 1 30); do [ "$(tmux list-clients -t "$t" 2>/dev/null | wc -l)" -gt 0 ] && break; sleep 0.5; done
[ "$(tmux list-clients -t "$t" | wc -l)" -gt 0 ] || { echo "window never attached"; tmux kill-session -t "$t" 2>/dev/null; exit 1; }
for i in $(seq 1 20); do out=$("$W" find "$t") && break; sleep 0.5; done || { echo "$out"; exit 1; }
hwnd=${out%% *}
"$W" reg "$hwnd" "$t" >/dev/null
if [ $# -gt 0 ]; then tmux send-keys -t "$t" C-u; tmux send-keys -t "$t" -l "$*"; tmux send-keys -t "$t" Enter; fi
echo "opened $t HWND=$hwnd"
