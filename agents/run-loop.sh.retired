#!/usr/bin/env bash
# Automates the worker <-> evaluator half of planner/worker/evaluator.
# Run from a project root that already has plans/PLAN.md (written by
# `claude --agent planner` interactively -- that stage is not automated here
# because it needs AskUserQuestion).
#
# Usage: ~/.claude/agents/run-loop.sh [max_rounds]
#
# Loops: worker -> evaluator -> read plans/EVAL.md flags -> repeat.
# Stops when EVAL.md says satisfied, or when it says plan_gap/stalled/in_loop
# (those need a human to run `claude --agent planner` and re-approve a plan --
# AskUserQuestion can't run headless), or after max_rounds.
#
# Headless runs get the default sandbox: filesystem access limited to the
# project directory, and anything needing dangerouslyDisableSandbox or a
# directory outside the repo (e.g. reaching /mnt/c from WSL, spawning a
# platform-specific binary) has no one to answer that permission prompt, so
# it blocks immediately with zero commits. If a project's plan needs that,
# set these env vars before running (not hardcoded here -- each project opts
# in for itself):
#   RUN_LOOP_WORKER_ARGS   extra `claude` flags for the worker call, e.g.
#                          RUN_LOOP_WORKER_ARGS='--add-dir /mnt/c/Users/you --dangerously-skip-permissions'
#   RUN_LOOP_EVAL_ARGS     same, for the evaluator call
# --dangerously-skip-permissions bypasses ALL permission checks for that
# call -- only set it for a project/round where you'd have approved every
# prompt anyway.

set -euo pipefail

MAX_ROUNDS="${1:-6}"
PLAN_DIR="plans"
EVAL_FILE="$PLAN_DIR/EVAL.md"
NOTES_FILE="$PLAN_DIR/WORKER_NOTES.md"
RUN_LOOP_WORKER_ARGS="${RUN_LOOP_WORKER_ARGS:-}"
RUN_LOOP_EVAL_ARGS="${RUN_LOOP_EVAL_ARGS:-}"

if [[ ! -f "$PLAN_DIR/PLAN.md" ]]; then
  echo "No $PLAN_DIR/PLAN.md found. Run 'claude --agent planner' first." >&2
  exit 1
fi

get_flag() {
  # get_flag NAME  ->  yes|no, read from the flags line of EVAL.md
  local name="$1"
  grep -m1 -oE "${name}: *(yes|no)" "$EVAL_FILE" | awk '{print $2}'
}

for ((round = 1; round <= MAX_ROUNDS; round++)); do
  echo "=== round $round: worker ===" >&2
  head_before="$(git rev-parse HEAD 2>/dev/null || true)"
  # shellcheck disable=SC2086
  claude --agent worker -p "Execute plans/PLAN.md. If plans/EVAL.md exists, fix every FAIL/PARTIAL and regression first. Work until the plan's Ask is met or you can show why this plan cannot meet it." \
    --permission-mode acceptEdits $RUN_LOOP_WORKER_ARGS
  head_after="$(git rev-parse HEAD 2>/dev/null || true)"

  if [[ "$head_before" == "$head_after" ]] \
    && grep -qiE "sandbox|blocked before any item|not reachable|outside the (sandbox|working director)" "$NOTES_FILE" 2>/dev/null; then
    echo "Worker made no commits and its notes describe an environment/sandbox block, not a plan problem:" >&2
    tail -n 15 "$NOTES_FILE" >&2
    echo >&2
    echo "This needs wider access for this project's headless run, not another round. Re-run with" >&2
    echo "RUN_LOOP_WORKER_ARGS (and RUN_LOOP_EVAL_ARGS if the evaluator needs it too) set to the" >&2
    echo "directories/flags this plan requires -- see the header of this script." >&2
    exit 4
  fi

  echo "=== round $round: evaluator ===" >&2
  # shellcheck disable=SC2086
  claude --agent evaluator -p "Grade the worker's latest commits against plans/PLAN.md. Write plans/EVAL.md." $RUN_LOOP_EVAL_ARGS

  if [[ ! -f "$EVAL_FILE" ]]; then
    echo "evaluator did not write $EVAL_FILE -- stopping." >&2
    exit 1
  fi

  satisfied="$(get_flag satisfied || true)"
  plan_gap="$(get_flag plan_gap || true)"
  stalled="$(get_flag stalled || true)"
  in_loop="$(get_flag in_loop || true)"

  echo "round $round flags: satisfied=$satisfied plan_gap=$plan_gap stalled=$stalled in_loop=$in_loop" >&2

  if [[ "$satisfied" == "yes" ]]; then
    echo "Satisfied after round $round. Review $EVAL_FILE and ship." >&2
    exit 0
  fi

  if [[ "$plan_gap" == "yes" || "$stalled" == "yes" ]]; then
    echo "Plan problem flagged (plan_gap=$plan_gap stalled=$stalled) after round $round." >&2
    echo "Run 'claude --agent planner' with the Notes for the planner in $EVAL_FILE, then rerun this script." >&2
    exit 2
  fi

  # in_loop alone (without stalled) keeps retrying -- evaluator's own
  # stalled rule already escalates after 2 in_loop rounds.
done

echo "Hit max rounds ($MAX_ROUNDS) without satisfied/plan_gap/stalled. Check $EVAL_FILE by hand." >&2
exit 3
