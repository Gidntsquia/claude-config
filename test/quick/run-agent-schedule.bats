# bats file_tags=feature:run-agent
# Scheduled runs: scheduling, listing, cancelling, firing at the stored time, and the fallbacks.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_tmux_setup; : > "$RA_OUT"; }
teardown() { ra_teardown; }

no_jobs() { assert_equal "$(ra --jobs)" "no scheduled runs"; }
in_tmux() { export TMUX="$(TM display -p '#{socket_path}'),0,0" TMUX_PANE="$(TM display -p -t t '#{pane_id}')"; }
sched_id() { grep -o '^scheduled #[0-9]*' <<<"$1" | tr -dc 0-9; }

# old: sched: scheduled line | sched: job file written | sched: job fields | sched: --jobs lists it
# bats test_tags=escape:1f
@test "scheduling prints one line, writes the job and --jobs lists it" {
  local R; R=$(( $(date +%s) + 6 )); usage_at "$R"
  keys "'$S' worker '.' --at $R --at-text 'after window' --window -- --model fable > '$T/sched.out' 2>&1; '$S' --jobs > '$T/jobs1.out'"
  wait_until 20 test -s "$T/jobs1.out"
  fhas "$T/sched.out" "^scheduled #1: $SHOWN at .* ET live (after window, in 0m)\$"
  assert_file_exist "$RUN_AGENT_HOME/jobs/1.json"
  python3 -c "import json,sys; j=json.load(open(sys.argv[1])); assert j['run_at']==int(sys.argv[2]) and j['at_text']=='after window' and j['window']==1 and j['source']=='live' and j['pane'].startswith('%') and j['session']=='t' and j['argv'][:3]==['claude','--agent','worker'] and j['cwd']==sys.argv[3], j" "$RUN_AGENT_HOME/jobs/1.json" "$R" "$T/repo/sub"
  fhas "$T/jobs1.out" "^#1  $SHOWN  at .* ET live (after window, in 0m)  \[sleeping (pid [0-9]*)\]\$"
}

# old: sched: fired into the pane (claude ran) | sched: first pane line | sched: jobs.log fired | sched: jobs.log carries the due time to the second and its source (live) | sched: job moved to done/ | sched: --jobs after = no scheduled runs
@test "a scheduled run fires into its pane, is logged with its due time and leaves the list" {
  local R; R=$(( $(date +%s) + 4 )); usage_at "$R"
  keys "'$S' worker '.' --at $R --at-text 'after window' --window -- --model fable > '$T/sched.out' 2>&1"
  logged 40 "  #1  fired  $SHOWN"   # scheduling itself took over 15 s on a loaded machine
  claude_ran 'arg=worker: repo (fable)'
  has "$(TM capture-pane -p -J -t t -S -)" "^scheduled run #1 fired at .* ET: $SHOWN"
  fhas "$LOG" "  #1  fired  $SHOWN  (due $(python3 "$RA_SRC/parse.py" --fmt-s "$R") live, woke 1\{0,1\}[0-9] s after)\$"
  assert_file_exist "$RUN_AGENT_HOME/done/1.json"
  assert_file_not_exist "$RUN_AGENT_HOME/jobs/1.json"
  no_jobs
}

# old: sched: --cancel one pending | sched: runner killed | sched: cancelled logged | sched: --cancel with nothing pending
@test "--cancel removes the only pending run, stops its runner and logs it" {
  ra worker '.' --at $(( $(date +%s) + 600 )) --at-text 'in 10m' >/dev/null 2>&1
  ra_asleep 1
  local pid; pid="$(jget 1 pid)"
  run ra --cancel
  has "$output" "  #1  cancelled  "
  ra_dead "$pid"
  assert_file_not_exist "$RUN_AGENT_HOME/jobs/1.json"
  fhas "$LOG" "  #1  cancelled  "
  assert_equal "$(ra --cancel 2>&1)" "no scheduled runs"
}

# old: sched: --cancel with two pending asks for an id | sched: --cancel <id> twice
@test "with two runs pending --cancel asks which, and --cancel <id> removes each" {
  local R; R=$(( $(date +%s) + 600 ))
  ra worker '.' --at "$R" --at-text 'in 10m' >/dev/null 2>&1
  ra worker '.' --at $(( R + 60 )) --at-text 'in 11m' >/dev/null 2>&1
  run ra --cancel
  has "$output" "several scheduled runs"
  ra --cancel 1 >/dev/null
  ra --cancel '#2' >/dev/null
  no_jobs
}

# old: sched: until earlier than reset -> skipped | sched: skipped logged | sched: nothing scheduled after skip
@test "a reset later than 'until' is skipped, logged and nothing is scheduled" {
  local R; R=$(( $(date +%s) + 7200 )); usage_at "$R"
  run ra worker '.' --at "$R" --at-text 'after window' --window --until $(( R - 3600 ))
  has "$output" "^skipped: reset .* ET is after until .* ET\$"
  fhas "$LOG" "skipped: reset"
  assert_equal "$(ls "$RUN_AGENT_HOME/jobs" 2>/dev/null)" ""
}

# old: runner: no usage API / parse.py --reset call at fire time
@test "the runner never asks for the reset time when it fires" {
  run grep -n 'reset' "$RA_SRC/runner.sh"
  refute_output --regexp 'parse\.py|\$P|--reset'
}

# A window run's time is fixed when it is scheduled. When a window ends the API already reports the next window's
# reset (run_at + 18000); the runner must not ask, wait or skip.
window_run_fires_at_its_time() {  # <seconds from run_at to "until">
  local u="$1" R fired
  R=$(( $(date +%s) + 7 )); usage_at "$R"
  keys "'$S' worker '.' --at $R --at-text 'after window' --window --until $(( R + u )) -- --model fable > '$T/sched.out' 2>&1"
  ra_id "$T/sched.out"
  ra_asleep "$ID"
  assert_equal "$(jget "$ID" run_at)" "$R"
  usage_at $(( R + 18000 ))
  assert_file_exist "$RUN_AGENT_HOME/jobs/$ID.json"   # still pending: the API moved before the run fired
  logged 30 "  #$ID  "
  fired=$(date +%s)
  # 'woke N s after' allows up to 19 s here and 15 s from the clock below: a loaded runner has woken 10 s late; the
  # fault guarded against is a skip or an hour's sleep
  fhas "$LOG" "  #$ID  fired  $SHOWN  (due $(python3 "$RA_SRC/parse.py" --fmt-s "$R") live, woke 1\{0,1\}[0-9] s after)\$"
  [ $(( fired - R )) -le 15 ]
  no grep -q "  #$ID  \(skipped\|fired late\)" "$LOG"
  claude_ran 'arg=worker: repo (fable)'
  assert_equal "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['run_at'])" "$RUN_AGENT_HOME/done/$ID.json")" "$R"
}

# old: sched: API moved to run_at + 18000 before firing, until +60 s -> fired at run_at, no wait, no skip (4 s after due) | sched: #n scheduled at the live reset | sched: #n ran claude in the pane | sched: #5 run_at unchanged by the later API answer
# bats test_tags=escape:3
@test "a window run fires at its stored time although the API moved on, until 60 s later" {
  window_run_fires_at_its_time 60
}

# old: sched: API moved to run_at + 18000 before firing, until +21600 s -> fired at run_at, no wait, no skip (4 s after due) | sched: #6 run_at unchanged by the later API answer | sched: window run fires at its stored run_at (until +21600 s)
@test "a window run fires at its stored time although the API moved on, until 6 h later" {
  window_run_fires_at_its_time 21600
}

# old: sched: (4) setup, the stale cache is in place | sched: API unreachable -> scheduled, shown as assumed (now + 5 h) | sched: no API answer -> run_at = scheduling time + 5 h, source assumed; stale cache (+10 min) and session estimate (+4 h) not used | sched: --jobs shows assumed (now + 5 h) beside the due time
@test "with the usage API unreachable a window run is set 5 h ahead and shown as assumed" {
  python3 -c "import json,sys,time; json.dump({'reset': int(time.time())+600, 'saved': int(time.time())-17400}, open(sys.argv[1],'w'))" "$RUN_AGENT_HOME/usage-reset.json"
  mkdir -p "$T/proj-live/x"
  printf '{"type":"x","timestamp":"%s"}\n' "$(python3 -c 'import datetime,time; print(datetime.datetime.fromtimestamp(time.time()-3600, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')" > "$T/proj-live/x/a.jsonl"
  export RUN_AGENT_PROJECTS="$T/proj-live" RUN_AGENT_USAGE_FILE="$T/none.json"
  has "$(python3 "$RA_SRC/parse.py" --reset-shown)" '(cached)'   # setup: the stale cache is in place
  local t0 t1 at
  t0=$(date +%s)
  run ra worker '.' --at 0 --at-text 'after window' --window
  t1=$(date +%s)
  assert_success
  has "$output" "^scheduled #1: .* ET assumed (now + 5 h) (after window, in 5h 0m)\$"
  refute_output --regexp 'at_error|unavailable'
  at="$(jget 1 run_at)"
  [ "$at" -ge $(( t0 + 18000 )) ]
  [ "$at" -le $(( t1 + 18001 )) ]
  assert_equal "$(jget 1 source)" "assumed (now + 5 h)"
  has "$(ra --jobs)" "^#1  .*  at .* ET assumed (now + 5 h) (after window, in 5h 0m)  \["
}

# old: sched: --need-tmux outside tmux -> exit 1 | sched: --need-tmux Relaunch line (no tmux)
@test "--need-tmux outside tmux schedules nothing and says how to do it by hand" {
  run ra worker '.' --at 0 --at-text 'after window' --window --need-tmux
  assert_failure 1
  assert_equal "$(line 1 "$output")" "not scheduled — not in tmux"
  assert_equal "$(printf '%s\n' "$output" | tail -n 1)" "Relaunch: not scheduled — not in tmux; run /run-agent worker after window to schedule it by hand"
  no_jobs
}

# old: sched: --need-tmux with the API down -> scheduled at now + 5 h
@test "--need-tmux with the usage API down still schedules the run" {
  in_tmux
  RUN_AGENT_USAGE_FILE="$T/none.json" run ra worker '.' --at 0 --at-text 'after window' --window --need-tmux
  assert_success
  has "$output" "^Relaunch: .* ET (job #[0-9]*)\$"
}

# old: sched: --need-tmux Relaunch line (scheduled)
@test "--need-tmux ends with the Relaunch line when it schedules" {
  in_tmux
  local R; R=$(( $(date +%s) + 600 )); usage_at "$R"
  run ra worker '.' --at "$R" --at-text 'after window' --window --need-tmux
  assert_success
  has "$(printf '%s\n' "$output" | tail -n 1)" "^Relaunch: .* ET (job #[0-9]*)\$"
}

# old: sched: --dry-run prints command, dir, time, reset | sched: --dry-run scheduled nothing
@test "--dry-run shows command, folder, time and reset and schedules nothing" {
  local R; R=$(( $(date +%s) + 3600 )); usage_at "$R"
  run ra --dry-run worker '.' --at "$R" --at-text 'in 1h' -- --model fable
  has "$output" "^command: $SHOWN\$"
  has "$output" "^dir: $T/repo/sub\$"
  has "$output" "^run at: .* ET (in 1h, in 1h 0m)\$"
  has "$output" "^usage reset: .* ET\$"
  no_jobs
}

# old: sched: pane gone -> fired in new window | sched: new window named 'worker: repo' | sched: claude ran in the new window
@test "a run whose pane is gone fires in a new window" {
  TM new-window -t t: -n second -c "$T/repo/sub" "$PANE_ENV bash --norc --noprofile"
  ra_ready t:second
  TARGET=t:second keys "'$S' worker '.' --at $(( $(date +%s) + 4 )) --at-text 'in 4s' > '$T/sched6.out' 2>&1"
  ra_id "$T/sched6.out"
  TM kill-window -t t:second
  logged 20 "  #$ID  fired in new window  "
  claude_ran 'arg=worker: repo'
  TM list-windows -t t -F '#{window_name}' | grep -qx 'worker: repo'
}

# old: sched: server gone -> fired in new session | sched: new session 'worker repo' | sched: claude ran in the new session
@test "a run whose tmux server is gone fires in a new session" {
  keys "'$S' worker '.' --at $(( $(date +%s) + 4 )) --at-text 'in 4s' > '$T/sched7.out' 2>&1"
  ra_id "$T/sched7.out"
  TM kill-server
  logged 20 "  #$ID  fired in new session  "
  claude_ran 'arg=worker: repo'
  TM list-sessions -F '#{session_name}' | grep -qx 'worker repo'
}
