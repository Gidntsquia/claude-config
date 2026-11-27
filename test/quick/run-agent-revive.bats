# bats file_tags=feature:run-agent
# A runner that died (--revive), and a sleeping job while the scripts change under it.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_tmux_setup; : > "$RA_OUT"; }
teardown() { ra_teardown; }

# A run 10 minutes ahead, scheduled from a pane of session r, whose runner is then killed. Sets ID.
dead_run() {
  TM new-session -d -s r -c "$T/repo/sub" "$PANE_ENV bash --norc --noprofile"
  ra_ready r
  TARGET=r keys "'$S' worker '.' --at $(( $(date +%s) + 600 )) --at-text 'in 10m' > '$T/sched8.out' 2>&1"
  ra_id "$T/sched8.out"
  ra_asleep "$ID"
  local pid; pid="$(jget "$ID" pid)"
  kill -9 "$pid"
  ra_dead "$pid"
}

# old: revive: --jobs flags the dead runner
@test "--jobs marks a run whose runner died as dead" {
  dead_run
  has "$(ra --jobs)" "^#$ID  .*\[dead\]\$"
}

# old: revive: silent, exit 0 | revive: future run gets a new runner, pid recorded | revive: same tmux server keeps the pane | revive: live runner left alone
@test "--revive silently gives a future run a new runner and leaves a live one alone" {
  dead_run
  local pane pid; pane="$(jget "$ID" pane)"
  run ra --revive
  assert_success
  assert_equal "$output" ""
  pid="$(jget "$ID" pid)"
  kill -0 "$pid"
  assert_equal "$(jget "$ID" pane)" "$pane"
  ra --revive
  assert_equal "$(jget "$ID" pid)" "$pid"
}

# old: revive: new tmux server clears the stale pane id
@test "--revive forgets the pane when the tmux server is a new one" {
  dead_run
  python3 "$J" set "$ID" server_pid 1
  ra --revive
  assert_equal "$(jget "$ID" pane)" ""
}

# old: revive: overdue run skipped and logged | revive: overdue run did not start claude
@test "--revive skips and logs an overdue run without starting claude" {
  dead_run
  : > "$RA_OUT"
  python3 -c "import json,sys,time; p=sys.argv[1]; j=json.load(open(p)); j['run_at']=int(time.time())-60; json.dump(j,open(p,'w'))" "$RUN_AGENT_HOME/jobs/$ID.json"
  run ra --revive
  assert_equal "$output" ""
  assert_file_not_exist "$RUN_AGENT_HOME/jobs/$ID.json"
  fhas "$LOG" "  #$ID  skipped  .*(was due .* ET; its runner stopped)\$"
  has "$(ra --jobs)" '^no scheduled runs$'
  [ ! -s "$RA_OUT" ]
}

# The loop tests run a copy of the scripts, so the repository's files stay untouched.
copy_scripts() { C2="$T/scripts2"; cp -R "$RA_SRC" "$C2"; S="$C2/run-agent.sh"; }
# sched2 <seconds from now> <at text>: schedule from the pane with the copied scripts; sets ID
sched2() {
  keys "'$S' worker '.' --at $(( $(date +%s) + $1 )) --at-text '$2' > '$T/sched.out' 2>&1"
  ra_id "$T/sched.out"
}

# old: loop: --jobs shows sleeping (pid N) | loop: the sleeper is the fixed bash -c loop, named runner.sh
@test "a pending run shows as sleeping and its process is the fixed wait loop" {
  copy_scripts
  sched2 600 'in 10m'
  ra_asleep "$ID"
  local pid; pid="$(jget "$ID" pid)"
  has "$(ra --jobs)" "^#$ID  .*\[sleeping (pid $pid)\]\$"
  has "$(pargs "$pid")" 'exec bash "$r" "$id"'
  assert_equal "$(pargs "$pid" | grep -o 'runner.sh' | head -n 1)" runner.sh
}

# old: loop: job fired after runner.sh was rewritten and restored | loop: claude ran | loop: logs/<id>.log empty (no error)
@test "rewriting runner.sh while a run sleeps does not break it" {
  copy_scripts
  # long enough that the checks below land before the run fires on a loaded machine (5 s was not)
  sched2 20 'in 20s'
  ra_asleep "$ID"
  cp "$C2/runner.sh" "$T/runner.bak"
  cp "$RA_FIX/runner-junk.sh" "$C2/runner.sh"
  kill -0 "$(jget "$ID" pid)"   # still asleep while the file is junk
  { echo '# restored'; cat "$T/runner.bak"; } > "$C2/runner.sh"   # shifted lines: the old incremental-read bug
  logged 45 "  #$ID  fired  "
  claude_ran 'arg=worker: repo'
  [ ! -s "$RUN_AGENT_HOME/logs/$ID.log" ]
}

jobs_has() { ra --jobs | grep -q -- "$1"; }

# old: loop: --jobs shows errored: <last log line> | loop: --health exit 1 with a FAIL line | loop: cancel drops the log
@test "a runner that errors is shown by --jobs and --health, and cancel removes its log" {
  copy_scripts
  # long enough that the swap below lands before the run fires on a loaded machine (4 s was not)
  sched2 15 'in 15s'
  ra_asleep "$ID"
  cp "$RA_FIX/runner-boom.sh" "$C2/runner.sh"
  wait_until 45 jobs_has "^#$ID  .*\[errored: runner.sh: boom\]\$" || { ra --jobs; return 1; }
  run ra --health
  assert_failure 1
  has "$output" "^FAIL  #$ID  errored: runner.sh: boom"
  assert_file_exist "$RUN_AGENT_HOME/logs/$ID.log"
  ra --cancel "$ID" >/dev/null
  assert_file_not_exist "$RUN_AGENT_HOME/logs/$ID.log"
}

# old: loop: woke late (< 1 h) -> fires at once, logged 'fired late' | loop: late run started claude
@test "a run that wakes late by less than an hour fires at once and is logged as late" {
  copy_scripts
  sched2 -120 'in 10m'
  logged 30 "  #$ID  fired late  "
  claude_ran 'arg=worker: repo'
}

@test "a run that wakes more than an hour late is skipped and does not start claude" {
  copy_scripts
  sched2 -7200 'in 10m'
  logged 30 "  #$ID  skipped  .*(woke 1[0-9][0-9] min late"
  [ ! -s "$RA_OUT" ]
}
