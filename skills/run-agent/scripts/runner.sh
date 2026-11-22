#!/usr/bin/env bash
# runner.sh <job id>: fires a scheduled /run-agent run. It is exec'd at fire time by the sleeping loop that
# run-agent.sh starts (start_runner: a fixed 5-line `bash -c` that sleeps to run_at, then `exec`s this file), so
# editing or committing this file never changes a pending job until it fires, and a job picks up fixes at fire
# time. Everything below is one function called inside braces, so bash reads the whole file before running it.
# Re-fetches the 5-hour window reset once for window runs (waits for it, one hour at most; no wait when the reset
# is that of a new window, which means the old one is over), then respawns the
# recorded pane into the recorded claude command. Woke late: < 1 h late fires at once (jobs.log `fired late`),
# later is skipped. Target split/window (human-made jobs): a brand-new tmux window; pane gone -> a new window in
# the recorded session; server gone -> a new detached session. A job made from an agent session (from_agent)
# only ever respawns its own pane: pane gone -> jobs.log `waiting: no pane`, the job stays pending and fires
# when a human run-agent call next sees that tmux server. Outcome -> ~/.claude/run-agent/jobs.log.
# The claude command runs as the job recorded it: the absolute binary (claude_bin) with the PATH, HOME and SHELL of
# the session that scheduled it (env), so a runner living in a stripped environment still starts claude; a job
# without these fields (older versions) runs `claude` from the runner's PATH as before. After tmux accepts the
# launch the runner waits up to 30 s for a `claude` process under the pane; none (the wrapper's exit marker shows
# claude ended non-zero, or the binary is missing) -> jobs.log `failed: claude did not start (<first error line>)`,
# the error stays on screen in the pane.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# a stripped environment (cron, launchd, env -i) has no Homebrew on PATH, and that is where tmux lives on a Mac
command -v tmux >/dev/null 2>&1 || export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin"
J="$HERE/jobs.py"; P="$HERE/parse.py"

# rp <path>: the path with links resolved, whether or not it exists (GNU `realpath -m`; BSD realpath on macOS has no -m)
rp() { python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
# Test mode (RUN_AGENT_TEST=1, exported by test.sh; same two functions as run-agent.sh). tm_guard <subcommand> <socket>: a tmux command that changes
# panes runs only on the test's own servers (socket named run-agent-test-*, or under $RUN_AGENT_TEST_DIR); on any
# other socket, the default server included, it is not run: one line on stderr, exit 2. Without the flag: no-op.
tm_guard() {
  [ "${RUN_AGENT_TEST:-}" = 1 ] || return 0
  local s="$2" d="${RUN_AGENT_TEST_DIR:-}"
  if [ -n "$s" ]; then
    case "${s##*/}" in run-agent-test|run-agent-test-*) return 0 ;; esac
    [ -n "$d" ] && case "$(rp "$s")" in "$(rp "$d")"/*) return 0 ;; esac
  fi
  echo "test mode: refusing tmux $1 on ${s:-default server}" >&2
  exit 2
}
# store_guard: in test mode the job store must be a scratch one: RUN_AGENT_HOME set and outside ~/.claude.
store_guard() {
  [ "${RUN_AGENT_TEST:-}" = 1 ] || return 0
  if [ -n "${RUN_AGENT_HOME:-}" ]; then
    case "$(rp "$RUN_AGENT_HOME")/" in "$(rp "$HOME/.claude")"/*) ;; *) return 0 ;; esac
  fi
  echo "test mode: refusing the real job store" >&2
  exit 2
}

main() {
  local id="$1"
  store_guard
  python3 "$J" setpid "$id" "$$"

  now() { date +%s; }
  field() { python3 "$J" get "$id" "$1"; }
  fmt() { python3 "$P" --fmt "$1"; }
  log() { python3 "$J" done "$id" "$1" "${2:-}" >/dev/null; }

  local run_at until_at window socket pane session cwd agent folder shown target from_agent
  local claude_bin env_path env_home env_shell state_dir
  run_at=$(field run_at); until_at=$(field until); window=$(field window)
  socket=$(field socket); pane=$(field pane); session=$(field session); cwd=$(field cwd)
  agent=$(field agent); folder=$(field folder); shown=$(field shown); target=$(field target)
  from_agent=$(field from_agent)
  claude_bin=$(field claude_bin); env_path=$(field env.PATH); env_home=$(field env.HOME); env_shell=$(field env.SHELL)
  state_dir="${RUN_AGENT_HOME:-$HOME/.claude/run-agent}"
  [ -n "$env_shell" ] || env_shell="${SHELL:-bash}"
  rm -f "$state_dir/logs/$id.exit"

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
    # A reset later than run_at means the old window is still open: wait for it. Unless that reset belongs to a
    # window that opened around run_at or later (reset - 5 h is within the last hour before run_at, or after it):
    # then the old window is over and usage is there, so fire now. (21 Nov: three jobs due 8:16 PM saw the next
    # window's 1:16 AM reset and slept the full hour.)
    if fresh=$(python3 "$P" --reset 2>/dev/null) && [ "$fresh" -gt "$run_at" ] \
        && [ $(( fresh - 18000 )) -lt $(( run_at - 3600 )) ]; then
      if [ -n "$until_at" ] && [ "$fresh" -gt "$until_at" ]; then
        log skipped "reset $(fmt "$fresh") is after until $(fmt "$until_at")"; exit 0
      fi
      cap=$(( run_at + 3600 ))
      [ "$fresh" -gt "$cap" ] && fresh=$cap
      wait_until "$fresh"
    fi
  fi

  local cmd first TM wrap sname
  cmd=(); while IFS= read -r -d '' _w; do cmd+=("$_w"); done < <(python3 "$J" argv "$id")   # no mapfile: macOS ships bash 3.2
  first="scheduled run #$id fired at $(fmt "$(now)"): $shown"
  TM=(tmux); [ -n "$socket" ] && TM=(tmux -S "$socket")
  local gsock="$socket"; [ -n "$gsock" ] || gsock="${TMUX:-}"; gsock="${gsock%%,*}"   # the server tmux will reach
  # $1 banner, $2 shell, $3 agent, $4 exit marker, $5 claude binary ("" = `claude` from PATH), $6 PATH, $7 HOME,
  # then the recorded claude arguments. The marker file carries claude's exit status (127 = not found).
  wrap=(bash -c 'printf "%s\n" "$1"; export SHELL="$2"; [ -n "$6" ] && export PATH="$6"; [ -n "$7" ] && export HOME="$7"
bin="${5:-claude}"
if ! command -v "$bin" >/dev/null 2>&1; then printf "%s: command not found\n" "$bin" >&2; echo 127 > "$4"; exec "$2"; fi
w=(); [ "$3" = worker ] && w=(env CLAUDE_CODE_SUBAGENT_MODEL=sonnet CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1)   # usage-guard R15, see run-agent.sh WORKER_ENV
RUN_AGENT_FROM="$3" "${w[@]}" "$bin" "${@:8}"; echo $? > "$4"; exec "$2"' run-agent "$first" "$env_shell" "$agent" \
    "$state_dir/logs/$id.exit" "$claude_bin" "$env_path" "$env_home" "${cmd[@]:1}")

  # started <pane>: after tmux took the launch, wait up to 30 s for claude under that pane. Logs the outcome.
  started() {
    local p="$1" where="$2" i rc err found=
    for i in $(seq 1 30); do
      if [ -f "$state_dir/logs/$id.exit" ]; then
        rc=$(cat "$state_dir/logs/$id.exit"); [ "$rc" = 0 ] && break
        err=$("${TM[@]}" capture-pane -p -J -t "$p" 2>/dev/null | sed '1d' | grep -v '^$' | head -n1)
        log "failed: claude did not start" "${err:-exit $rc}${where:+, $where}"; return 1
      fi
      if python3 "$HERE/proc.py" claude-under "$("${TM[@]}" display -p -t "$p" '#{pane_pid}' 2>/dev/null)"
      then found=1; break; fi
      sleep 1
    done
    if [ -z "$found" ] && [ ! -f "$state_dir/logs/$id.exit" ]; then
      err=$("${TM[@]}" capture-pane -p -J -t "$p" 2>/dev/null | sed '1d' | grep -v '^$' | head -n1)
      log "failed: claude did not start" "${err:-no claude process after 30 s}${where:+, $where}"; return 1
    fi
    log "$outcome${where:+ $where}"; return 0
  }

  if [ -n "$pane" ] && "${TM[@]}" display -p -t "$pane" '#{pane_id}' >/dev/null 2>&1; then
    if [ -n "$target" ] && [ "$from_agent" != 1 ]; then
      # split/window: a brand-new window after the recorded pane's window; the recorded pane is left alone.
      local newp
      if newp=$(RA_SOCKET="$socket" bash "$HERE/run-agent.sh" --open window "$pane" "$cwd" "$agent: $folder" "${wrap[@]}"); then
        started "$newp" "in new window"; exit $?
      fi
    elif tm_guard respawn-pane "$gsock"; "${TM[@]}" respawn-pane -k -t "$pane" -c "$cwd" "${wrap[@]}"; then
      started "$pane" ""; exit $?
    fi
  fi
  if [ "$from_agent" = 1 ]; then
    # an agent's job never opens a window or session: wait for a human run-agent call on this server
    python3 "$J" set "$id" waiting 1 >/dev/null; python3 "$J" setpid "$id" 0 >/dev/null
    python3 "$J" log "$id" "waiting: no pane" >/dev/null; exit 0
  fi
  sname="$agent: $folder"
  if [ -n "$session" ] && "${TM[@]}" has-session -t "=$session" 2>/dev/null; then
    local newp
    tm_guard new-window "$gsock"
    if newp=$("${TM[@]}" new-window -t "=$session" -n "$sname" -c "$cwd" -P -F '#{pane_id}' "${wrap[@]}"); then started "$newp" "in new window"; exit $?; fi
  fi
  # tmux disallows ':' and '.' in session names
  sname="${sname//:/}"; sname="${sname//./_}"
  tm_guard new-session "$gsock"
  if newp=$("${TM[@]}" new-session -d -s "$sname" -c "$cwd" -P -F '#{pane_id}' "${wrap[@]}"); then started "$newp" "in new session"; exit $?; fi
  log failed "tmux could not start the command"
  exit 1
}

{ main "$@"; exit $?; }
