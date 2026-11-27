#!/bin/bash
# Stands in for tmux: records each call; capture-pane prints a coloured pane, or fails with $TMUX_FAIL.
echo "$*" >> "$TMUX_LOG"
case "$1" in
  capture-pane) [ -n "${TMUX_FAIL:-}" ] && { echo "$TMUX_FAIL" >&2; exit 1; }
    printf '$ make test\n\033[31mred words\033[0m then plain <b>\n\033[1;38;5;46mbold green\033[0m\n\n\n';;
  has-session) exit 1;;
esac
exit 0
