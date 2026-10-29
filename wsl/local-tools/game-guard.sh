#!/bin/bash
# usage: game-guard.sh [what...]   exit 0 and print "game: <name>" if a full-screen game is running (so NO window may be
# opened, shown, moved or focused); exit 1 silently otherwise. Sourced into win-app.sh, win.sh and term-open.sh, which
# refuse their action while it says yes and append the refused request to ~/.cache/claude-config/game-deferred.log.
# Games: process names in GAME_GUARD_PROCS (default "deadlock project8"); GAME_GUARD=off disables the check.
[ "${GAME_GUARD:-}" = off ] && exit 1
grep -qi microsoft /proc/version 2>/dev/null || exit 1
procs="${GAME_GUARD_PROCS:-deadlock project8}"
g=$(powershell.exe -NoProfile -Command "(Get-Process -Name ($(printf "'%s'," $procs | sed 's/,$//')) -ErrorAction SilentlyContinue | Select-Object -First 1).Name" 2>/dev/null | tr -d '\r\n ')
[ -n "$g" ] || exit 1
echo "game: $g"
if [ $# -gt 0 ]; then
  mkdir -p "$HOME/.cache/claude-config"
  echo "$(TZ=America/New_York date '+%F %T') ET  game=$g  refused: $*" >> "$HOME/.cache/claude-config/game-deferred.log"
  echo "deferred: $g is running; not touching any window. Request logged in ~/.cache/claude-config/game-deferred.log: $*" >&2
fi
exit 0
