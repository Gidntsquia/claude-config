#!/usr/bin/env bash
# Runs under argv[0] "claude" in a tmux pane, like a live session: as its children, the four hook inputs with
# env -u TMUX -u TMUX_PANE, the bare `worker` one last. argv: out prefix, flag (1 = test mode), run-agent.sh, test dir.
out="$1"; flag="$2"; S="$3"; T="$4"; cd "$T/repo/sub"
if [ "$flag" = 1 ]; then export RUN_AGENT_TEST=1 RUN_AGENT_TEST_DIR="$T"; fi
printf '{"command_name":"run-agent","command_args":"worker \\"x\\" in %s dry","prompt":"/run-agent worker"}' "$T/sibling" | env -u TMUX -u TMUX_PANE "$S" --hook > "$out.1" 2>&1
printf '{"command_args":"jobs"}' | env -u TMUX -u TMUX_PANE "$S" --hook > "$out.2" 2>&1
printf '{"command_args":"planner \\"x\\" in %s split dry"}' "$T/sibling" | env -u TMUX -u TMUX_PANE -u RUN_AGENT_HUMAN -u RUN_AGENT_FROM "$S" --hook > "$out.3" 2>&1
printf '{"command_args":"worker"}' | env -u TMUX -u TMUX_PANE "$S" --hook > "$out.4" 2>&1
touch "$out.done"; sleep 300
