# bats file_tags=feature:run-agent
# Calls from an agent session: they only ever replace their own pane.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_tmux_setup; : > "$RA_OUT"; AG="env -u RUN_AGENT_HUMAN RUN_AGENT_FROM=worker"; }
teardown() { ra_teardown; }

as_agent() { RUN_AGENT_FROM=worker RUN_AGENT_HUMAN= run ra "$@"; }
windows() { TM list-windows -t t | wc -l; }

# old: agent: split from an agent -> ignored line, then the dry text (own pane)
@test "an agent asking for a split is told it is ignored and gets its own pane" {
  as_agent --relaunch "planner \"x\" in $T/sibling split dry"
  assert_equal "$(line 1 "$output")" "ignored: agents replace their own pane"
  has "$output" '^command: claude --agent planner'
  refute_a_line_matches '^opens in'
}

# old: agent: + group from an agent -> ignored, exit 2
@test "an agent asking for several launches at once is refused" {
  mkdir -p "$T/ga" "$T/gb"
  as_agent --relaunch "planner \"A\" in $T/ga + planner \"B\" in $T/gb"
  assert_failure 2
  assert_equal "$output" "ignored: agents replace their own pane"
}

# old: agent: caller detected from the parent claude --agent flag
@test "a caller under claude --agent is recognised as that agent" {
  local out
  out=$( (exec -a claude bash -c "env -u RUN_AGENT_HUMAN -u RUN_AGENT_FROM '$S' --from-agent; true" _ --agent evaluator --model opus) )
  assert_equal "$out" evaluator
}

# old: agent: RUN_AGENT_HUMAN=1 means a human caller
@test "a caller marked as human is not taken for an agent" {
  assert_equal "$(ra --from-agent)" ""
}

# old: agent: split in tmux -> own pane replaced, no new window or pane
@test "an agent's split launch in tmux replaces its pane, with no new window or pane" {
  local n; n="$(windows)"
  keys "$AG '$S' worker '.' --target split > '$T/ag1.out' 2>&1"
  claude_ran 'arg=worker: repo'
  fhas "$T/ag1.out" '^ignored: agents replace their own pane$'
  assert_equal "$(windows)" "$n"
  assert_equal "$(TM list-panes -t t:0 | wc -l)" 1
}

# An agent schedules from window "agentwin", which is then closed; wait until its runner has given up. Sets ID.
waiting_job() {
  TM new-window -t t: -n agentwin -c "$T/repo/sub" "$PANE_ENV bash --norc --noprofile"
  ra_ready t:agentwin
  TARGET=t:agentwin keys "$AG '$S' worker '.' --at $(( $(date +%s) + 5 )) --at-text 'in 5s' --target split > '$T/ag2.out' 2>&1"
  ra_id "$T/ag2.out"
  ra_asleep "$ID"
  local pid; pid="$(jget "$ID" pid)"
  TM kill-window -t t:agentwin
  # 60 s: a loaded macOS runner took over 20 s from the kill to this line (the runner starts python some 20 times)
  logged 60 "  #$ID  waiting: no pane  "
  ra_dead "$pid"
}

# old: agent: scheduled run from an agent is marked from_agent, target dropped
@test "a run scheduled by an agent is marked as such and loses its split target" {
  TARGET=t keys "$AG '$S' worker '.' --at $(( $(date +%s) + 600 )) --at-text 'in 10m' --target split > '$T/ag2.out' 2>&1"
  ra_id "$T/ag2.out"
  fhas "$T/ag2.out" '^ignored: agents replace their own pane$'
  assert_equal "$(jget "$ID" from_agent)" 1
  assert_equal "$(jget "$ID" target)" ""
}

# old: agent: pane gone at fire time -> jobs.log 'waiting: no pane' | agent: waiting job stays pending, --jobs shows it | agent: no window, session or claude for the waiting job
@test "an agent's run with no pane left waits, opening no window, session or claude" {
  local n s; n="$(windows)"; s="$(TM list-sessions | wc -l)"
  waiting_job
  assert_file_exist "$RUN_AGENT_HOME/jobs/$ID.json"
  has "$(RUN_AGENT_FROM=worker RUN_AGENT_HUMAN= ra --jobs)" "^#$ID  .*\[waiting: no pane\]\$"
  assert_equal "$(windows)" "$n"
  assert_equal "$(TM list-sessions | wc -l)" "$s"
  [ ! -s "$RA_OUT" ]
}

# old: agent: --health treats waiting as ok | agent: --revive leaves a waiting job alone | agent: an agent's call never fires waiting jobs
@test "a waiting run passes --health, and neither --revive nor an agent's call starts it" {
  waiting_job
  run ra --health
  assert_success
  assert_equal "$(ra --revive 2>&1)" ""
  as_agent --fire-waiting
  assert_equal "$output" ""
  assert_file_exist "$RUN_AGENT_HOME/jobs/$ID.json"
  [ ! -s "$RA_OUT" ]
}

# old: agent: a human run-agent call fires the waiting job in a new window | agent: waiting job's claude ran in the new window, caller window unchanged
@test "the next run-agent call by a person starts the waiting run in a new window" {
  waiting_job
  local n; n="$(windows)"
  keys "'$S' --jobs > '$T/ag3.out' 2>&1"
  logged 20 "  #$ID  fired in new window  "
  claude_ran 'arg=worker: repo'
  # the call prints this line after the fake claude has started: wait for it
  wait_until 15 grep -q "^waiting job #$ID started in a new window: " "$T/ag3.out"
  fhas "$T/ag3.out" "^waiting job #$ID started in a new window: "
  assert_equal "$(windows)" $(( n + 1 ))
  assert_equal "$(TM list-panes -t t:0 | wc -l)" 1
}
