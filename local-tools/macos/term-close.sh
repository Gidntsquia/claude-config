#!/bin/bash
# usage: term-close.sh <Title> <id>  -> closes that item's page and kills the tmux session term-open.sh made.
[ $# -ge 2 ] || { echo "usage: term-close.sh <Title> <id>" >&2; exit 2; }
"$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/win.sh" close "$2"; rc=$?
"${EVSHOW_TMUX:-tmux}" kill-session -t "$1" 2>/dev/null
exit $rc
