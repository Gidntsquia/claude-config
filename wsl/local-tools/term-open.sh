#!/bin/bash
# usage: term-open.sh <Title> <dir> <command...>   (Title must be unique; random suffix advised)
# Opens a NEW, HIDDEN Windows Terminal window titled <Title> (win-app.sh --hidden), attached to a tmux session <Title> you own,
# runs <command>, prints "opened <Title> HWND=<hwnd> (hidden: ...)". Exit 1 if the window did not appear hidden.
# Drive it only via: tmux send-keys -t <Title> ...   Place/show it with: win.sh show "<Title>" X Y W H
# The window is registered in THIS session's launched.txt (evsession.sh).
# The window uses the Windows Terminal profile $TERM_OPEN_PROFILE (default Ubuntu) for its font and colors;
# without -p, wt.exe gives a bare command line the base settings (no Nerd Font: icons show as blanks).
set -e
# WSL only: needs wt.exe, wsl.exe and win.sh (PowerShell window control); Windows and macOS have none of these.
grep -qi microsoft /proc/version 2>/dev/null || { echo "term-open.sh: WSL only (this is $(uname))"; exit 1; }
t="$1"; dir="$2"; shift 2
"$HOME/.claude/local-tools/game-guard.sh" "term-open.sh $t $dir $*" >/dev/null && { echo "not opened: a full-screen game is running (game-guard.sh)"; exit 3; }
W="$HOME/.claude/local-tools/win.sh"
tmux new-session -d -s "$t" -c "$dir" -x 200 -y 50
# Opened hidden (win-app.sh --hidden: layered alpha 0 + off-screen before the first paint, registered in launched.txt);
# win.sh show "<Title>" X Y W H un-hides and places it. EVSHOW_WT=<path> overrides wt.exe (tests).
out=$(EVSHOW_HIDE_TIMEOUT="${EVSHOW_HIDE_TIMEOUT:-20}" bash "$HOME/.claude/local-tools/win-app.sh" --hidden --title "$t" wt -w new -p "${TERM_OPEN_PROFILE:-Ubuntu}" \
  --title "$t" --suppressApplicationTitle wsl.exe -d "${WSL_DISTRO_NAME:-Ubuntu}" -- tmux attach -t "$t") \
  || { echo "$out" | grep -v '^hide-log'; tmux kill-session -t "$t" 2>/dev/null; exit 1; }
hidden=$(printf '%s\n' "$out" | grep '^hidden: ' | head -1)
for i in $(seq 1 30); do [ "$(tmux list-clients -t "$t" 2>/dev/null | wc -l)" -gt 0 ] && break; sleep 0.5; done
[ "$(tmux list-clients -t "$t" | wc -l)" -gt 0 ] || { echo "window never attached"; tmux kill-session -t "$t" 2>/dev/null; exit 1; }
hwnd=$(printf '%s\n' "$hidden" | awk '{print $2}')
[ -n "$hwnd" ] || { for i in $(seq 1 20); do out=$("$W" find "$t") && break; sleep 0.5; done || { echo "$out"; exit 1; }; hwnd=${out%% *}; "$W" reg "$hwnd" "$t" >/dev/null; }
if [ $# -gt 0 ]; then tmux send-keys -t "$t" C-u; tmux send-keys -t "$t" -l "$*"; tmux send-keys -t "$t" Enter; fi
echo "opened $t HWND=$hwnd${hidden:+ ($hidden)}"
