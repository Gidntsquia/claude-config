#!/usr/bin/env bash
# run-agent.sh: replace this tmux pane's claude session with `claude --agent <agent> "<prompt>" [flags]`.
# Usage: run-agent.sh <agent> [prompt] [-- claude flags...]   |   --list   |   --help
# The new session is named `--name "<agent>: <repo folder>"` (plus ` (<model>)` when --model is given)
# unless the flags already carry --name/-n. <repo folder> = basename of the git root, else of $PWD.
set -euo pipefail

USAGE='usage: run-agent.sh <agent> [prompt] [-- claude flags...] | --list | --help
  adds --name "<agent>: <repo folder> (<model>)" to the claude command unless --name/-n is among the flags'
# Built-in subagents that `claude --agent` accepts (checked 2026-10-14; Bash and claude-code-guide are refused).
BUILTINS=(claude general-purpose Explore Plan statusline-setup)

list_agents() {
  local d f
  for d in "$HOME/.claude/agents" "$PWD/.claude/agents"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.md; do [ -f "$f" ] && basename "$f" .md; done
  done
  printf '%s\n' "${BUILTINS[@]}"
}

case "${1:-}" in
  --help|-h) echo "$USAGE"; exit 0 ;;
  --list) list_agents | awk '!seen[$0]++'; exit 0 ;;
  ""|--*) echo "$USAGE" >&2; exit 2 ;;
esac

agent="$1"; shift
if ! list_agents | grep -xF -- "$agent" >/dev/null; then  # no -q: grep -q + pipefail trips on SIGPIPE
  { echo "unknown agent: $agent"; echo "valid agents:"; list_agents | awk '!seen[$0]++' | sed 's/^/  /'; } >&2
  exit 2
fi

prompt=""
if [ $# -gt 0 ] && [ "$1" != "--" ]; then prompt="$1"; shift; fi
if [ $# -gt 0 ]; then
  [ "$1" = "--" ] || { echo "$USAGE" >&2; exit 2; }
  shift
fi
flags=("$@")

if [ -z "$prompt" ]; then
  case "$agent" in
    worker|evaluator|helper) prompt="." ;;
    *) echo "$agent needs a prompt" >&2; exit 2 ;;
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
  folder=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
  name="$agent: $folder"
  [ -n "$model" ] && name="$name ($model)"
  flags+=(--name "$name")
fi

cmd=(claude --agent "$agent" "$prompt")
[ ${#flags[@]} -gt 0 ] && cmd+=("${flags[@]}")
shown="claude --agent $agent \"$prompt\""
prev=""
for f in "${flags[@]}"; do
  if [ "$prev" = "--name" ] || [ "$prev" = "-n" ]; then shown+=" \"$f\""; else shown+=" $f"; fi
  prev="$f"
done

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  echo "not inside tmux; run:"
  echo "$shown"
  exit 1
fi

echo "running: $shown"
# Only this pane is touched. The wrapper runs claude with its arguments passed verbatim (no shell
# re-evaluation), then keeps an interactive shell in the pane so it does not close.
tmux respawn-pane -k -t "$TMUX_PANE" -c "$PWD" \
  bash -c 'printf "running: %s\n" "$1"; "${@:3}"; exec "$2"' run-agent "$shown" "${SHELL:-bash}" "${cmd[@]}"
