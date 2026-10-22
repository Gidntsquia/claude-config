#!/usr/bin/env bash
# runner.sh <job id>: the detached runner behind a scheduled /run-agent run. Started by run-agent.sh with
# `setsid nohup`, so it survives the claude session and pane that scheduled it (not a reboot). Sleeps to
# run_at, re-fetches the 5-hour window reset once for window runs (waits for it, one hour at most), then
# respawns the recorded pane into the recorded claude command; pane gone -> a new window in the recorded
# tmux session; server gone -> a new detached session. Outcome -> ~/.claude/run-agent/jobs.log.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
J="$HERE/jobs.py"; P="$HERE/parse.py"
id="$1"
python3 "$J" setpid "$id" "$$"

now() { date +%s; }
field() { python3 "$J" get "$id" "$1"; }
fmt() { python3 "$P" --fmt "$1"; }

run_at=$(field run_at); until_at=$(field until); window=$(field window)
socket=$(field socket); pane=$(field pane); session=$(field session); cwd=$(field cwd)
agent=$(field agent); folder=$(field folder); shown=$(field shown)
log() { python3 "$J" done "$id" "$1" "${2:-}" >/dev/null; }

wait_until() {  # sleep until epoch $1
  local t
  while :; do
    t=$(( $1 - $(now) ))
    [ "$t" -le 0 ] && return
    sleep "$t"
  done
}
wait_until "$run_at"

if [ "$window" = 1 ]; then
  if fresh=$(python3 "$P" --reset 2>/dev/null) && [ "$fresh" -gt "$run_at" ]; then
    if [ -n "$until_at" ] && [ "$fresh" -gt "$until_at" ]; then
      log skipped "reset $(fmt "$fresh") is after until $(fmt "$until_at")"; exit 0
    fi
    cap=$(( run_at + 3600 ))
    [ "$fresh" -gt "$cap" ] && fresh=$cap
    wait_until "$fresh"
  fi
fi

mapfile -d '' -t cmd < <(python3 "$J" argv "$id")
first="scheduled run #$id fired at $(fmt "$(now)"): $shown"
TM=(tmux); [ -n "$socket" ] && TM=(tmux -S "$socket")
wrap=(bash -c 'printf "%s\n" "$1"; "${@:3}"; exec "$2"' run-agent "$first" "${SHELL:-bash}" "${cmd[@]}")

if [ -n "$pane" ] && "${TM[@]}" display -p -t "$pane" '#{pane_id}' >/dev/null 2>&1; then
  if "${TM[@]}" respawn-pane -k -t "$pane" -c "$cwd" "${wrap[@]}"; then log fired; exit 0; fi
fi
sname="$agent: $folder"
if [ -n "$session" ] && "${TM[@]}" has-session -t "=$session" 2>/dev/null; then
  if "${TM[@]}" new-window -t "=$session" -n "$sname" -c "$cwd" "${wrap[@]}"; then log "fired in new window"; exit 0; fi
fi
# tmux disallows ':' and '.' in session names
sname="${sname//:/}"; sname="${sname//./_}"
if "${TM[@]}" new-session -d -s "$sname" -c "$cwd" "${wrap[@]}"; then log "fired in new session"; exit 0; fi
log failed "tmux could not start the command"
exit 1
