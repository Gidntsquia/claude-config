#!/usr/bin/env bash
# run-agent.sh: replace this tmux pane's claude session with `claude --agent <agent> ["<prompt>"] [flags]`.
# No prompt: worker/evaluator/helper get "."; planner and built-ins start with no prompt argument.
# Usage: run-agent.sh <agent> [prompt] [--cwd|-C <dir>] [-- claude flags...] | --resolve <dir> | --list | --help
# The new session is named `--name "<agent>: <folder>"` (plus ` (<model>)` when --model is given)
# unless the flags already carry --name/-n. <folder> = basename of --cwd's dir when given, else of the git
# root, else of $PWD. With --cwd the pane (shell and claude) restarts in <dir>; the dir must already exist
# (this script never creates directories). <dir> resolution: ~ -> $HOME, absolute as is, a path with / ->
# relative to $PWD, a bare name -> $PWD/<name> if it exists, else a sibling of the current git root
# (outside a repo: of $PWD). `.`/`..` segments are collapsed; symlinks are left as given.
set -euo pipefail

USAGE='usage: run-agent.sh <agent> [prompt] [--cwd|-C <dir>] [-- claude flags...] | --resolve <dir> | --list | --help
  adds --name "<agent>: <folder> (<model>)" to the claude command unless --name/-n is among the flags
  --cwd <dir>, -C <dir>  start the new session in <dir> (must exist; <folder> = its basename);
                         outside tmux the printed command starts with cd '\''<dir>'\'' &&
  --resolve <dir>        print "<absolute dir><TAB>exists|missing" by the --cwd rules (exit 2 on a
                         bare name found nowhere, or a path that is a file); creates nothing'
# Built-in subagents that `claude --agent` accepts (checked 2026-10-14; Bash and claude-code-guide are refused).
BUILTINS=(claude general-purpose Explore Plan statusline-setup)

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

case "${1:-}" in
  --help|-h) echo "$USAGE"; exit 0 ;;
  --list) list_agents | awk '!seen[$0]++'; exit 0 ;;
  --resolve) [ $# -eq 2 ] || { echo "$USAGE" >&2; exit 2; }
    resolve "$2"; printf '%s\t%s\n' "$RESOLVED" "$RES_STATE"; exit 0 ;;
  ""|--*) echo "$USAGE" >&2; exit 2 ;;
esac

agent="$1"; shift

# Arguments after the agent: [prompt] and [--cwd|-C <dir>] in any order, then [-- flags...].
prompt=""; have_prompt=0; dir=""; have_dir=0
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
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
if [ "$has_name" = 0 ]; then
  if [ -n "$dir" ]; then folder=$(basename "$dir")
  else folder=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
  fi
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

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  echo "not inside tmux; run:"
  echo "$shown"
  exit 1
fi

echo "running: $shown"
# Only this pane is touched. The wrapper runs claude with its arguments passed verbatim (no shell
# re-evaluation), then keeps an interactive shell in the pane so it does not close.
tmux respawn-pane -k -t "$TMUX_PANE" -c "${dir:-$PWD}" \
  bash -c 'printf "running: %s\n" "$1"; "${@:3}"; exec "$2"' run-agent "$shown" "${SHELL:-bash}" "${cmd[@]}"
