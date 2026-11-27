# bats file_tags=feature:run-agent
# What a scheduled run needs at fire time: a stripped environment, a claude that fails, and old job files.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_tmux_setup; : > "$RA_OUT"; }
teardown() { ra_teardown; }

# Schedule with only HOME and the tmux ids in the environment; the claude to find is $FH/.local/bin/claude. Sets ID, OUT.
stripped_job() {  # <seconds from now>
  FH="$T/fakehome2"; mkdir -p "$FH/.local/bin"; cp "$T/bin/claude" "$FH/.local/bin/claude"
  local pane sock
  pane="$(TM display -p -t t:0 '#{pane_id}')"; sock="$(TM display -p '#{socket_path}')"
  OUT=$(ra_nofds env -i HOME="$FH" TMUX="$sock,0,0" TMUX_PANE="$pane" RUN_AGENT_HOME="$RUN_AGENT_HOME" RUN_AGENT_USAGE_FILE="$RUN_AGENT_USAGE_FILE" \
        RUN_AGENT_TZ=America/New_York RUN_AGENT_AGENTS_DIR="$T/agents" /bin/bash "$S" worker '.' --at $(( $(date +%s) + $1 )) --at-text 'in 10s' 2>&1)
  ID="$(sed -n 's/^scheduled #\([0-9]*\):.*/\1/p' <<<"$OUT")"
  [ -n "$ID" ] || { echo "$OUT"; return 1; }
}

# old: env: scheduled line names the default model: (sonnet, default) | env: --jobs shows (sonnet, default)
@test "the scheduled line and --jobs name the agent's default model" {
  stripped_job 600
  has "$OUT" "^scheduled #$ID: claude --agent worker \".\" --name \"worker: repo (sonnet)\" (sonnet, default) at .* ET (in 10s, in "
  has "$(ra --jobs)" "^#$ID  .*  (sonnet, default)  at "
}

# old: env: job records claude_bin (HOME/.local/bin/claude when none on PATH), env.HOME, model_default | env: job from a stripped env fired | env: the recorded claude binary ran | env caps: a scheduled worker gets them too
@test "a run scheduled from a stripped environment still starts the claude it recorded, with worker limits" {
  stripped_job 6
  assert_equal "$(jget "$ID" claude_bin)" "$FH/.local/bin/claude"
  assert_equal "$(jget "$ID" env.HOME)" "$FH"
  assert_equal "$(jget "$ID" model_default)" sonnet
  logged 30 "  #$ID  fired  "
  claude_ran 'arg=worker: repo (sonnet)'
  claude_ran '^subenv=sonnet//3/1$'
}

# Schedule a run whose claude exits 127, and wait until the runner has reported it. Sets ID.
broken_claude_job() {
  mkdir -p "$T/bin127"; cp "$RA_FIX/claude-127" "$T/bin127/claude"
  keys "PATH='$T/bin127:$PATH' '$S' worker '.' --at $(( $(date +%s) + 4 )) --at-text 'in 4s' > '$T/sched127.out' 2>&1"
  ra_id "$T/sched127.out"
  assert_equal "$(jget "$ID" claude_bin)" "$T/bin127/claude"
  logged 45 "  #$ID  failed: claude did not start  "
}

# old: start: job records the claude found on PATH at creation | start: claude exit 127 -> jobs.log 'failed: claude did not start' | start: the first stderr line is in the log line | start: done/<id>.json outcome failed | start: the error stays on screen in the pane
@test "a claude that fails to start is logged with its error, which stays on screen" {
  broken_claude_job
  fhas "$LOG" "  #$ID  failed: claude did not start  .*  (claude: no such model zork)\$"
  assert_equal "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['outcome'])" "$RUN_AGENT_HOME/done/$ID.json")" "failed: claude did not start"
  has "$(TM capture-pane -p -t t:0 -S -)" "claude: no such model zork"
}

# old: failures: the next human --jobs prints the failed run with time and reason | failures: printed once, then marked seen
@test "--jobs reports a failed run once" {
  broken_claude_job
  run ra --jobs
  has "$output" "^20[0-9-]* [0-9:]* [AP]M ET  #$ID  failed: claude did not start (claude: no such model zork)  claude --agent worker"
  run ra --jobs
  assert_success
  refute_output --partial "#$ID  failed"
}

# A job file as written before v1.3.1 has no claude_bin, env or model_default.
strip_new() { python3 -c "import json,sys; p=sys.argv[1]; j=json.load(open(p)); [j.pop(k,None) for k in ('claude_bin','env','model_default')]; json.dump(j,open(p,'w'))" "$RUN_AGENT_HOME/jobs/$1.json"; }
old_job() {  # <seconds from now> <at text>
  keys "'$S' worker '.' --at $(( $(date +%s) + $1 )) --at-text '$2' > '$T/schedold.out' 2>&1"
  ra_id "$T/schedold.out"
  ra_asleep "$ID"
  strip_new "$ID"
}

# old: old job: --jobs lists a pre-1.3.1 job file (no default-model note)
@test "--jobs lists a job file from an older version" {
  old_job 600 'in 10m'
  has "$(ra --jobs)" "^#$ID  claude --agent worker \".\" --name \"worker: repo (sonnet)\"  at .* ET (in 10m, in [0-9]*m)  \[sleeping (pid [0-9]*)\]\$"
}

# old: old job: a pre-1.3.1 job file fires | old job: claude ran (PATH's claude, today's behaviour)
@test "a job file from an older version still fires" {
  old_job 6 'in 6s'
  logged 30 "  #$ID  fired  "
  claude_ran 'arg=worker: repo (sonnet)'
}
