#!/usr/bin/env bash
# run-agent.sh: replace this tmux pane's claude session with `claude --agent <agent> ["<prompt>"] [flags]`.
# No prompt: worker/evaluator/helper get "."; planner and built-ins start with no prompt argument.
# Usage: run-agent.sh <agent> [prompt] [--cwd|-C <dir>] [--target split|window] [--at <epoch> [--at-text <text>] [--window] [--until <epoch>]]
#        [-- claude flags...] | --parse '<raw $ARGUMENTS>' | --dry-run <same as a run> | --jobs | --cancel [id]
#        | --handoff <agent> [prompt] [-- claude flags...] | --revive | --resolve <dir> | --list | --help
#        | --relaunch '<raw>' (the /run-agent skill) | --step [--here] '<raw>' | --cli <words...> (bin/run-agent)
#        | --next <agent> [prompt] | --open <target> <pane> <dir> <name> <cmd...>
# --relaunch does what needs no question at once (jobs, cancel, errors, dry, force runs) and otherwise hands the
# confirmation to a haiku session (launch.py): the calling pane is respawned into it, or with split/window a new
# tmux window opens with it, and that session replaces its own pane on Yes. --target split|window: open the
# claude command in a brand-new tmux window instead of replacing this pane (never a pane in an existing window).
# Several runs joined by a lone `+` (or `;`) in one /run-agent call open together in one new window, tiled
# (four = 2x2): --group [--here] '<raw>' launches them (launch.py), into:<pane> adds each pane after the first.
# --handoff is the worker's usage-limit handoff in one call: schedules the relaunch after the window, appends a
# `## Stopped at usage limit` section (stdin = Done / In progress / Next) to plans/WORKER_NOTES.md, makes the WIP commit.
# --parse hands the raw argument string to parse.py (loose phone typing -> one JSON block). --at schedules:
# a job file under ~/.claude/run-agent/jobs/ and a detached runner (runner.sh) that respawns this pane into
# the command at that time (pane gone -> new window; server gone -> new session). --jobs / --cancel manage them.
# A reboot or WSL restart kills the runners; --revive (run-agent-revive.service, at WSL start) restarts them.
# The new session is named `--name "<agent>: <folder>"` (plus ` (<model>)` when --model is given)
# unless the flags already carry --name/-n. <folder> = basename of --cwd's dir when given, else of the git
# root, else of $PWD. With --cwd the pane (shell and claude) restarts in <dir>; the dir must already exist
# (this script never creates directories). <dir> resolution: ~ -> $HOME, absolute as is, a path with / ->
# relative to $PWD, a bare name -> $PWD/<name> if it exists, else a sibling of the current git root
# (outside a repo: of $PWD). `.`/`..` segments are collapsed; symlinks are left as given.
set -euo pipefail

USAGE='usage: run-agent.sh <agent> [prompt] [--cwd|-C <dir>] [--target split|window] [--at <epoch> [--at-text <text>] [--window] [--until <epoch>]] [-- claude flags...]
       run-agent.sh --parse '\''<raw arguments>'\'' | --dry-run <run args> | --jobs | --cancel [id] | --resolve <dir> | --list | --help
       run-agent.sh --handoff <agent> [prompt] [-- claude flags...]  < "Done / In progress / Next" text
  adds --name "<agent>: <folder> (<model>)" to the claude command unless --name/-n is among the flags
  --parse <raw>          parse a loosely typed /run-agent argument string into one JSON block (parse.py)
  --at <epoch>           do not run now: write ~/.claude/run-agent/jobs/<id>.json and start a detached runner
                         that respawns this pane into the command at that time; --at-text keeps the words typed,
                         --window marks a usage-window run (re-fetched at fire time), --until <epoch> skips the
                         run when the window reset is later than that; --need-tmux refuses to schedule outside
                         tmux (exit 1, "not scheduled — not in tmux") and ends every outcome with a ready-made
                         "Relaunch: ..." line; used by the worker at the usage limit
  --target split|window  open in a brand-new tmux window instead of replacing this pane (both words do the same)
  --group [--here] '\''<raw>'\''  start runs joined by a lone + or ; in one new tmux window, tiled (no confirm)
  --relaunch '\''<raw>'\''     the /run-agent skill: answers jobs/cancel/dry/errors itself, runs force runs, and
                         hands every confirmation to a haiku session (launch.py)
  --cli <words...>       bin/run-agent: the same, confirming with read -p (or a tmux popup)
  --next <agent> [prompt] print an agent'\''s closing next step: a sentence, the /run-agent line, a labelled claude line
  --dry-run ...          print the command, directory and run time; run and schedule nothing
  --handoff ...          usage-limit handoff in one call: schedule after the window (--need-tmux path), append a
                         "## Stopped at usage limit — <time> ET" section (stdin text, Uncommitted, Relaunch) to
                         plans/WORKER_NOTES.md, commit project files as "WIP: stopped at usage limit — ...",
                         print "Note: / Commit: / Relaunch:" lines; exit 0 whether or not scheduling worked
  --jobs, --cancel [id]  list pending scheduled runs / cancel one (the only one when no id is given)
  --revive               restart the runner of each pending run whose runner is gone (reboot, WSL restart);
                         skip (and log) the ones already overdue. Prints nothing
  --cwd <dir>, -C <dir>  start the new session in <dir> (must exist; <folder> = its basename);
                         outside tmux the printed command starts with cd '\''<dir>'\'' &&
  --resolve <dir>        print "<absolute dir><TAB>exists|missing" by the --cwd rules (exit 2 on a
                         bare name found nowhere, or a path that is a file); creates nothing'
# Built-in subagents that `claude --agent` accepts (checked 2026-10-14; Bash and claude-code-guide are refused).
BUILTINS=(claude general-purpose Explore Plan statusline-setup)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="${RUN_AGENT_HOME:-$HOME/.claude/run-agent}"

# Collapse `.`/`..` and repeated slashes in an absolute path, textually (no symlink lookups).
normalize() {
  local IFS=/ part out=()
  for part in $1; do
    case "$part" in
      ""|.) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  [ ${#out[@]} -eq 0 ] && { echo /; return; }
  printf '/%s' "${out[@]}"; echo
}

# resolve <token>: sets RESOLVED (absolute) and RES_STATE (exists|missing), or prints the error and exits 2.
resolve() {
  local t="$1" p base sib
  [ -n "$t" ] || { echo "$USAGE" >&2; exit 2; }
  case "$t" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${t#\~/}" ;;
    /*) p="$t" ;;
    */*) p="$PWD/$t" ;;
    *)
      base=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
      sib="$(normalize "$base/..")"
      if [ -d "$PWD/$t" ]; then p="$PWD/$t"
      elif [ -d "$sib/$t" ]; then p="$sib/$t"
      else echo "no such directory: $t (looked in $PWD, $sib)" >&2; exit 2
      fi ;;
  esac
  RESOLVED=$(normalize "$p")
  if [ -d "$RESOLVED" ]; then RES_STATE=exists
  elif [ -e "$RESOLVED" ]; then echo "not a directory: $RESOLVED" >&2; exit 2
  else RES_STATE=missing
  fi
}

list_agents() {
  local d f
  for d in "$HOME/.claude/agents" "$PWD/.claude/agents" ${dir:+"$dir/.claude/agents"}; do
    [ -d "$d" ] || continue
    for f in "$d"/*.md; do [ -f "$f" ] && basename "$f" .md; done
  done
  printf '%s\n' "${BUILTINS[@]}"
}

# open_target <split|window|into:<pane>> <pane> <dir> <window name> <cmd...>: start <cmd> and print the new pane id.
# split and window both open a brand-new tmux window after <pane>'s window: a launch never adds a pane to the
# caller's window or any other existing window. into:<p> is for a multi-run (launch.py group) only: it splits the
# largest pane of <p>'s window, which the group itself opened, and re-tiles that window so its panes stay equal
# (four panes = 2x2). Uses $RA_SOCKET when set (the runner's recorded server). Exit 1 when tmux refuses.
open_target() {
  local tgt="$1" pane="$2" d="$3" wname="$4" best="" area=0 w h a id flag new
  shift 4
  local TM=(tmux); [ -n "${RA_SOCKET:-}" ] && TM=(tmux -S "$RA_SOCKET")
  case "$tgt" in
    into:*)
      pane="${tgt#into:}"
      while read -r id w h; do
        a=$((w * h)); [ "$a" -gt "$area" ] && { area=$a; best="$id $w $h"; }
      done < <("${TM[@]}" list-panes -t "$pane" -F '#{pane_id} #{pane_width} #{pane_height}' 2>/dev/null)
      [ -n "$best" ] || return 1
      read -r id w h <<<"$best"
      if [ "$w" -ge $((h * 2)) ]; then flag=-h; else flag=-v; fi
      new=$("${TM[@]}" split-window "$flag" -t "$id" -c "$d" -P -F '#{pane_id}' "$@") || return 1
      "${TM[@]}" select-layout -t "$pane" tiled >/dev/null 2>&1 || true
      echo "$new" ;;
    *) w=$("${TM[@]}" display -p -t "$pane" '#{session_id}:#{window_id}') || return 1
       "${TM[@]}" new-window -a -t "$w" -n "$wname" -c "$d" -P -F '#{pane_id}' "$@" ;;
  esac
}

# revive: silent, for a WSL-start service (run-agent-revive.service). Every pending job whose runner is gone gets
# a new runner if it is still ahead; an overdue one is skipped (jobs.log: skipped). A changed tmux server pid
# means the recorded pane id may now name someone else's pane, so it is cleared (the run opens a new window).
# flock keeps two revives from starting two runners for one job.
revive() {
  local line id state socket spid cur TM stale
  mkdir -p "$STATE"
  if command -v flock >/dev/null 2>&1; then exec 9>"$STATE/revive.lock"; flock -n 9 || return 0; fi
  mapfile -t stale < <(python3 "$HERE/jobs.py" stale)
  for line in ${stale[@]+"${stale[@]}"}; do
    IFS=$'\t' read -r id state <<<"$line"
    if [ "$state" = overdue ]; then
      python3 "$HERE/jobs.py" done "$id" skipped \
        "was due $(python3 "$HERE/parse.py" --fmt "$(python3 "$HERE/jobs.py" get "$id" run_at)"); its runner stopped" >/dev/null
      continue
    fi
    socket=$(python3 "$HERE/jobs.py" get "$id" socket); spid=$(python3 "$HERE/jobs.py" get "$id" server_pid)
    TM=(tmux); [ -n "$socket" ] && TM=(tmux -S "$socket")
    cur=$("${TM[@]}" display -p '#{pid}' 2>/dev/null || true)
    [ -n "$spid" ] && [ "$spid" = "$cur" ] || python3 "$HERE/jobs.py" set "$id" pane ""
    start_runner "$id" "$(python3 "$HERE/jobs.py" get "$id" run_at)"   # pid recorded at once (a second revive sees it)
  done
}

# start_runner <id> <run_at>: the detached sleeper behind a scheduled run. A fixed 5-line `bash -c` loop sleeps to
# run_at (never a negative sleep) and then execs the repo's runner.sh as it is at fire time, so editing or committing
# anything under skills/run-agent while jobs sleep changes nothing until they fire. $0 is "runner.sh" so jobs.py's
# alive() recognises it; its output goes to logs/<id>.log (empty unless it errored). Records the pid.
start_runner() {
  mkdir -p "$STATE/logs"
  setsid nohup bash -c 'id=$1; at=$2; r=$3
while :; do t=$(( at - $(date +%s) )); [ "$t" -le 0 ] && break; sleep "$t"; done
exec bash "$r" "$id"' runner.sh "$1" "$2" "$HERE/runner.sh" >> "$STATE/logs/$1.log" 2>&1 < /dev/null 9>&- &
  python3 "$HERE/jobs.py" setpid "$1" "$!"
  disown
}

# Was this script called from an agent session (worker, evaluator, planner, helper)? Set by the launch wrapper
# (RUN_AGENT_FROM=<agent>) or read from the parent claude process's --agent flag. Prints the agent name or nothing.
from_agent() {
  [ -n "${RUN_AGENT_HUMAN:-}" ] && return 0   # the hook: a typed /run-agent is the human's, even in an agent session
  if [ -n "${RUN_AGENT_FROM:-}" ]; then echo "$RUN_AGENT_FROM"; return; fi
  python3 - <<'PY' 2>/dev/null
import os
pid = os.getppid()
while pid > 1:
    try:
        argv = [a.decode(errors="replace") for a in open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0") if a]
        if argv and os.path.basename(argv[0]) == "claude":
            if "--agent" in argv[:-1]:
                print(argv[argv.index("--agent") + 1])
            break
        pid = int(open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        break
PY
}

# fire_waiting: an agent's scheduled job whose pane was gone at fire time waits (jobs.log `waiting: no pane`) for a
# human run-agent call on the same tmux server; that call opens it in a brand-new window (the human may open windows).
fire_waiting() {
  local id cwd agent folder shown socket cmd wrap first
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  [ -z "$(from_agent)" ] || return 0
  socket="${TMUX%%,*}"
  for id in $(python3 "$HERE/jobs.py" waiting "$socket" 2>/dev/null); do
    cwd=$(python3 "$HERE/jobs.py" get "$id" cwd); agent=$(python3 "$HERE/jobs.py" get "$id" agent)
    folder=$(python3 "$HERE/jobs.py" get "$id" folder); shown=$(python3 "$HERE/jobs.py" get "$id" shown)
    [ -d "$cwd" ] || cwd="$PWD"
    mapfile -d '' -t cmd < <(python3 "$HERE/jobs.py" argv "$id")
    first="scheduled run #$id fired at $(python3 "$HERE/parse.py" --fmt "$(date +%s)") (was waiting: no pane): $shown"
    wrap=(bash -c 'printf "%s\n" "$1"; RUN_AGENT_FROM="$3" "${@:4}"; exec "$2"' run-agent "$first" "${SHELL:-bash}" "$agent" "${cmd[@]}")
    if open_target window "$TMUX_PANE" "$cwd" "$agent: $folder" "${wrap[@]}" >/dev/null 2>&1; then
      python3 "$HERE/jobs.py" done "$id" "fired in new window" "was waiting: no pane" >/dev/null
      echo "waiting job #$id started in a new window: $shown"
    fi
  done
}

case "${1:-}" in
  --help|-h) echo "$USAGE"; exit 0 ;;
  --list) list_agents | awk '!seen[$0]++'; exit 0 ;;
  --resolve) [ $# -eq 2 ] || { echo "$USAGE" >&2; exit 2; }
    resolve "$2"; printf '%s\t%s\n' "$RESOLVED" "$RES_STATE"; exit 0 ;;
  --parse) shift; exec python3 "$HERE/parse.py" "$@" ;;
  --relaunch|--cli|--group) fire_waiting; mode="${1#--}"; shift; exec python3 "$HERE/launch.py" "$mode" "$@" ;;
  --step|--next|--hook) mode="${1#--}"; shift; exec python3 "$HERE/launch.py" "$mode" "$@" ;;
  --from-agent) from_agent; exit 0 ;;
  --reset-shown) r=$(python3 "$HERE/parse.py" --reset 2>/dev/null) && python3 "$HERE/parse.py" --fmt "$r"; exit 0 ;;
  --fire-waiting) fire_waiting; exit 0 ;;
  --open) shift; open_target "$@"; exit $? ;;
  --jobs) fire_waiting; exec python3 "$HERE/jobs.py" list ;;
  --health) exec python3 "$HERE/jobs.py" health ;;
  --cancel) shift; exec python3 "$HERE/jobs.py" cancel "$@" ;;
  --revive) revive; exit 0 ;;
  --dry-run) shift; dry=1 ;;
  --handoff) shift; handoff=1 ;;
  ""|--*) echo "$USAGE" >&2; exit 2 ;;
esac
dry="${dry:-0}"; handoff="${handoff:-0}"

agent="$1"; shift

# Arguments after the agent: [prompt] and [--cwd|-C <dir>] in any order, then [-- flags...].
prompt=""; have_prompt=0; dir=""; have_dir=0; target=""; at=""; at_text=""; at_shown=""; window=0; until_at=""; need_tmux=0
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    --at|--at-text|--at-shown|--until)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      case "$1" in --at) at="$2" ;; --at-text) at_text="$2" ;; --at-shown) at_shown="$2" ;; --until) until_at="$2" ;; esac
      shift 2 ;;
    --window) window=1; shift ;;
    --target)
      [ $# -ge 2 ] && case "$2" in split|window|into:%*|"") true ;; *) false ;; esac || { echo "$USAGE" >&2; exit 2; }
      target="$2"; shift 2 ;;
    --need-tmux) need_tmux=1; shift ;;
    --dry-run) dry=1; shift ;;
    --cwd|-C|--cwd=*)
      [ "$have_dir" = 0 ] || { echo "$USAGE" >&2; exit 2; }
      if [ "$1" = "--cwd" ] || [ "$1" = "-C" ]; then
        [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
        dir="$2"; shift 2
      else dir="${1#--cwd=}"; shift
      fi
      have_dir=1 ;;
    *)
      [ "$have_prompt" = 0 ] || { echo "$USAGE" >&2; exit 2; }
      prompt="$1"; have_prompt=1; shift ;;
  esac
done
flags=("$@")

# An agent session (worker/evaluator/planner) never opens a tmux window: split/window are ignored, its run replaces
# its own pane, and its scheduled job is marked from_agent (the runner then never opens a window or session either).
caller_agent=$(from_agent)
[ -z "$caller_agent" ] && [ "$dry" = 0 ] && fire_waiting
if [ -n "$caller_agent" ] && [ -n "$target" ]; then
  echo "ignored: agents replace their own pane"
  target=""
fi

if [ "$have_dir" = 1 ]; then
  resolve "$dir"
  dir="$RESOLVED"
  [ "$RES_STATE" = exists ] || { echo "no such directory: $dir" >&2; exit 2; }
fi

if ! list_agents | grep -xF -- "$agent" >/dev/null; then  # no -q: grep -q + pipefail trips on SIGPIPE
  { echo "unknown agent: $agent"; echo "valid agents:"; list_agents | awk '!seen[$0]++' | sed 's/^/  /'; } >&2
  exit 2
fi

# Default prompt "." for worker/evaluator/helper; every other agent (planner, built-ins) starts with no
# prompt argument when none is given (an empty input box).
if [ -z "$prompt" ]; then
  case "$agent" in
    worker|evaluator|helper) prompt="." ;;
  esac
fi

# --handoff: schedule (same path as --at 0 --window --need-tmux, in a child so a failure there cannot stop the
# note and commit), append the handoff section to plans/WORKER_NOTES.md, commit, print the three lines.
if [ "$handoff" = 1 ]; then
  HINT="; run /run-agent worker after window to schedule it by hand"
  args=("$agent"); [ -n "$prompt" ] && args+=("$prompt"); [ -n "$dir" ] && args+=(--cwd "$dir")
  sched=$("$BASH_SOURCE" "${args[@]}" --at 0 --at-text 'after window' --window --need-tmux -- "${flags[@]}" 2>&1) || true
  relaunch=$(grep -m1 '^Relaunch: ' <<<"$sched" || true)
  [ -n "$relaunch" ] || relaunch="Relaunch: not scheduled — $(tail -n1 <<<"${sched:-no output from the scheduler}")$HINT"
  text=""; [ -t 0 ] || text=$(cat)
  cd "${dir:-$PWD}"
  in_git=0; top=$(git rev-parse --show-toplevel 2>/dev/null) && in_git=1 && cd "$top"
  dirty=""
  [ "$in_git" = 1 ] && dirty=$(git status --porcelain -- . ':!plans' | cut -c4- | paste -sd, - | sed 's/,/, /g')
  mkdir -p plans
  {
    echo; echo "## Stopped at usage limit — $(TZ=America/New_York date '+%Y-%m-%d %-I:%M %p') ET"
    [ -n "$text" ] && printf '%s\n' "$text"
    echo "Uncommitted/dirty: ${dirty:-none}"
    echo "$relaunch"
  } >> plans/WORKER_NOTES.md
  echo "Note: plans/WORKER_NOTES.md"
  if [ "$in_git" = 0 ]; then echo "Commit: no git"
  elif [ -z "$dirty" ]; then echo "Commit: nothing to commit"
  else
    what=$(awk 'f && NF {sub(/^[-*] */,""); print; exit} /^In progress:/ {r=$0; sub(/^In progress: */,"",r); if (r!="") {print r; exit}; f=1}' <<<"$text")
    title="WIP: stopped at usage limit — ${what:-see WORKER_NOTES.md}"
    git add -A -- . && { git reset -q -- plans 2>/dev/null || true; }   # plans/ stays out even when not ignored
    git commit -q -m "$title" -m "Handoff written by run-agent.sh --handoff; plans/WORKER_NOTES.md has Done / In progress / Next.

Co-Authored-By: Claude <noreply@anthropic.com>"
    echo "Commit: $(git rev-parse --short HEAD) $title"
  fi
  echo "$relaunch"
  exit 0
fi

# Session name: "<agent>: <folder>" or "<agent>: <folder> (<model>)", unless --name/-n was passed.
has_name=0; model=""; i=0
while [ $i -lt ${#flags[@]} ]; do
  case "${flags[$i]}" in
    --name|-n|--name=*|-n=*) has_name=1 ;;
    --model|-m) model="${flags[$((i+1))]:-}" ;;
    --model=*) model="${flags[$i]#--model=}" ;;
    -m=*) model="${flags[$i]#-m=}" ;;
  esac
  i=$((i+1))
done
if [ -n "$dir" ]; then folder=$(basename "$dir")
else folder=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
fi
if [ "$has_name" = 0 ]; then
  name="$agent: $folder"
  [ -n "$model" ] && name="$name ($model)"
  flags+=(--name "$name")
fi

cmd=(claude --agent "$agent")
shown="claude --agent $agent"
[ -n "$prompt" ] && { cmd+=("$prompt"); shown+=" \"$prompt\""; }
[ ${#flags[@]} -gt 0 ] && cmd+=("${flags[@]}")
prev=""
for f in "${flags[@]}"; do
  if [ "$prev" = "--name" ] || [ "$prev" = "-n" ]; then shown+=" \"$f\""; else shown+=" $f"; fi
  prev="$f"
done
# With a directory, the shown command starts with cd '<dir>' && (single quotes escaped as '\'').
[ -n "$dir" ] && shown="cd '${dir//\'/\'\\\'\'}' && $shown"

fmt() { python3 "$HERE/parse.py" --fmt "$1"; }
in_from_now() {  # "in 3h 12m"
  local m=$(( ($1 - $(date +%s) + 30) / 60 )); [ "$m" -lt 0 ] && m=0
  if [ $((m / 60)) -gt 0 ]; then echo "in $((m / 60))h $((m % 60))m"; else echo "in ${m}m"; fi
}

if [ "$dry" = 1 ]; then
  echo "command: $shown"
  echo "dir: ${dir:-$PWD}"
  if [ -n "$at" ]; then
    echo "run at: ${at_shown:-$(fmt "$at") (${at_text:-at $(fmt "$at")}, $(in_from_now "$at"))}"
    [ -n "$until_at" ] && echo "until: $(fmt "$until_at")"
  else
    echo "run at: now"
  fi
  if reset=$(python3 "$HERE/parse.py" --reset 2>&1); then echo "usage reset: $(fmt "$reset")"
  else echo "usage reset: unavailable ($reset)"; fi
  echo "dry run: nothing scheduled, nothing replaced"
  exit 0
fi

if [ -n "$at" ]; then
  HINT="; run /run-agent worker after window to schedule it by hand"
  if [ "$need_tmux" = 1 ] && [ -z "${TMUX:-}" ]; then
    echo "not scheduled — not in tmux" >&2
    echo "Relaunch: not scheduled — not in tmux$HINT" >&2
    exit 1
  fi
  [ -n "$at_text" ] || at_text="at $(fmt "$at")"
  if [ "$window" = 1 ]; then
    if ! reset=$(python3 "$HERE/parse.py" --reset 2>&1); then
      echo "at_error: usage API: ${reset#error: }; open any claude session to refresh the token" >&2
      [ "$need_tmux" = 1 ] && echo "Relaunch: not scheduled — no reset time (${reset#error: })$HINT" >&2
      exit 2
    fi
    [ "$reset" -gt "$at" ] && at="$reset"
    if [ -n "$until_at" ] && [ "$reset" -gt "$until_at" ]; then
      line="skipped: reset $(fmt "$reset") is after until $(fmt "$until_at")"
      echo "$line"
      mkdir -p "$STATE"; printf '%s  #-  %s  %s\n' "$(date '+%Y-%m-%d %I:%M %p ET')" "$line" "$shown" >> "$STATE/jobs.log"
      exit 0
    fi
  fi
  pane="${TMUX_PANE:-}"; session=""; socket=""; server_pid=""
  if [ -n "${TMUX:-}" ]; then
    socket="${TMUX%%,*}"; session=$(tmux display -p '#{session_name}' 2>/dev/null || true)
    server_pid=$(tmux display -p '#{pid}' 2>/dev/null || true)
  fi
  mkdir -p "$STATE"
  IFS=$'\t' read -r id jobfile < <(python3 "$HERE/jobs.py" write --run-at "$at" --at-text "$at_text" --window "$window" \
    ${until_at:+--until "$until_at"} --cwd "${dir:-$PWD}" --target "$target" --pane "$pane" --session "$session" --socket "$socket" \
    --server-pid "$server_pid" --from-agent "$([ -n "$caller_agent" ] && echo 1 || echo 0)" \
    --shown "$shown" --agent "$agent" --folder "$folder" -- "${cmd[@]}")
  start_runner "$id" "$at"
  echo "scheduled #$id: $shown at ${at_shown:-$(fmt "$at") ($at_text, $(in_from_now "$at"))}"
  [ "$need_tmux" = 1 ] && echo "Relaunch: $(fmt "$at") (job #$id)"
  exit 0
fi

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  echo "not inside tmux; run:"
  echo "$shown"
  exit 1
fi

wrap=(bash -c 'printf "running: %s\n" "$1"; RUN_AGENT_FROM="$3" "${@:4}"; exec "$2"' run-agent "$shown" "${SHELL:-bash}" "$agent" "${cmd[@]}")
if [ -n "$target" ]; then
  new=$(open_target "$target" "$TMUX_PANE" "${dir:-$PWD}" "$agent: $folder" "${wrap[@]}") || { echo "tmux could not open a $target" >&2; exit 2; }
  where=$(tmux display -p -t "$new" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || echo "$new")
  echo "opened $where ($new): $shown"
  exit 0
fi
echo "running: $shown"
# Only this pane is touched. The wrapper runs claude with its arguments passed verbatim (no shell
# re-evaluation), then keeps an interactive shell in the pane so it does not close.
tmux respawn-pane -k -t "$TMUX_PANE" -c "${dir:-$PWD}" "${wrap[@]}"
