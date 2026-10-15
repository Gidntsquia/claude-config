#!/bin/bash
# usage: term-close.sh <Title> <HWND>  -> closes that window and kills the tmux session term-open.sh made.
grep -qi microsoft /proc/version 2>/dev/null || { echo "term-close.sh: WSL only (this is $(uname))" >&2; exit 1; }
"$HOME/.claude/local-tools/win.sh" close "$2"; rc=$?
tmux kill-session -t "$1" 2>/dev/null
exit $rc
