#!/usr/bin/env bash
# runner.sh <job id>: fires a scheduled /run-agent run. It is exec'd at fire time by the sleeping loop that
# run-agent.sh starts (start_runner: a fixed 5-line `bash -c` that sleeps to run_at, then `exec`s this file), so
# editing or committing this file never changes a pending job until it fires, and a job picks up fixes at fire
# time. Everything below is one function called inside braces, so bash reads the whole file before running it.
# Re-fetches the 5-hour window reset once for window runs (waits for it, one hour at most), then respawns the
# recorded pane into the recorded claude command. Woke late: < 1 h late fires at once (jobs.log `fired late`),
# later is skipped. Target split/window (human-made jobs): a brand-new tmux window; pane gone -> a new window in
# the recorded session; server gone -> a new detached session. A job made from an agent session (from_agent)
# only ever respawns its own pane: pane gone -> jobs.log `waiting: no pane`, the job stays pending and fires
# when a human run-agent call next sees that tmux server. Outcome -> ~/.claude/run-agent/jobs.log.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
J="$HERE/jobs.py"; P="$HERE/parse.py"

main() {
  local id="$1"
  python3 "$J" setpid "$id" "$$"

  now() { date +%s; }
  field() { python3 "$J" get "$id" "$1"; }
  fmt() { python3 "$P" --fmt "$1"; }
  log() { python3 "$J" done "$id" "$1" "${2:-}" >/dev/null; }

  local run_at until_at window socket pane session cwd agent folder shown target from_agent
  run_at=$(field run_at); until_at=$(field until); window=$(field window)
  socket=$(field socket); pane=$(field pane); session=$(field session); cwd=$(field cwd)
  agent=$(field agent); folder=$(field folder); shown=$(field shown); target=$(field target)
  from_agent=$(field from_agent)

  wait_until() {  # sleep until epoch $1; never a negative sleep
    local t
    while :; do
      t=$(( $1 - $(now) ))
      [ "$t" -le 0 ] && return
      sleep "$t"
    done
  }
  wait_until "$run_at"
  local late=$(( $(now) - run_at )) outcome=fired
  if [ "$late" -gt 3600 ]; then
    log skipped "woke $((late / 60)) min late (was due $(fmt "$run_at"))"; exit 0
  fi
  [ "$late" -gt 60 ] && outcome="fired late"

  if [ "$window" = 1 ]; then
    local fresh cap
    if fresh=$(python3 "$P" --reset 2>/dev/null) && [ "$fresh" -gt "$run_at" ]; then
      if [ -n "$until_at" ] && [ "$fresh" -gt "$until_at" ]; then
        log skipped "reset $(fmt "$fresh") is after until $(fmt "$until_at")"; exit 0
      fi
      cap=$(( run_at + 3600 ))
      [ "$fresh" -gt "$cap" ] && fresh=$cap
      wait_until "$fresh"
    fi
  fi

  local cmd first TM wrap sname
  mapfile -d '' -t cmd < <(python3 "$J" argv "$id")
  first="scheduled run #$id fired at $(fmt "$(now)"): $shown"
  TM=(tmux); [ -n "$socket" ] && TM=(tmux -S "$socket")
  wrap=(bash -c 'printf "%s\n" "$1"; RUN_AGENT_FROM="$3" "${@:4}"; exec "$2"' run-agent "$first" "${SHELL:-bash}" "$agent" "${cmd[@]}")

  if [ -n "$pane" ] && "${TM[@]}" display -p -t "$pane" '#{pane_id}' >/dev/null 2>&1; then
    if [ -n "$target" ] && [ "$from_agent" != 1 ]; then
      # split/window: a brand-new window after the recorded pane's window; the recorded pane is left alone.
      if RA_SOCKET="$socket" bash "$HERE/run-agent.sh" --open window "$pane" "$cwd" "$agent: $folder" "${wrap[@]}" >/dev/null; then
        log "$outcome in new window"; exit 0
      fi
    elif "${TM[@]}" respawn-pane -k -t "$pane" -c "$cwd" "${wrap[@]}"; then
      log "$outcome"; exit 0
    fi
  fi
  if [ "$from_agent" = 1 ]; then
    # an agent's job never opens a window or session: wait for a human run-agent call on this server
    python3 "$J" set "$id" waiting 1 >/dev/null; python3 "$J" setpid "$id" 0 >/dev/null
    python3 "$J" log "$id" "waiting: no pane" >/dev/null; exit 0
  fi
  sname="$agent: $folder"
  if [ -n "$session" ] && "${TM[@]}" has-session -t "=$session" 2>/dev/null; then
    if "${TM[@]}" new-window -t "=$session" -n "$sname" -c "$cwd" "${wrap[@]}"; then log "$outcome in new window"; exit 0; fi
  fi
  # tmux disallows ':' and '.' in session names
  sname="${sname//:/}"; sname="${sname//./_}"
  if "${TM[@]}" new-session -d -s "$sname" -c "$cwd" "${wrap[@]}"; then log "$outcome in new session"; exit 0; fi
  log failed "tmux could not start the command"
  exit 1
}

{ main "$@"; exit $?; }
