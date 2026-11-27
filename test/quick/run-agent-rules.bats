# bats file_tags=feature:run-agent
# Permission rules for run-agent, cleaning the state folder, groups on paper, and the job-store safety rules.
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_clock; export RUN_AGENT_NO_RETRY=1; }
teardown() { ra_teardown; }

rules() { python3 "$RA_FIX/rules.py" "$REPO" "$1"; }

# old: rules: pogo incident 1 (clone path run-agent.sh ... | tail) is allowed
@test "scheduling with the clone's path, piped to tail, needs no permission" { assert_equal "$(rules pogo1)" ok; }

# old: rules: pogo incident 2 (cd; ~/.claude run-agent.sh ...; --jobs | tail) is allowed
@test "cd, then scheduling and listing through the installed script, needs no permission" { assert_equal "$(rules pogo2)" ok; }

# old: rules: slay-the-spire incident: run-agent parts allowed, only 'export PATH' and 'dotnet test' are not (its own rules)
@test "in a mixed command only the parts that are not run-agent's ask for permission" {
  assert_equal "$(rules slay)" 'blocked: export PATH=$HO''ME/.dotnet:$PATH / dotnet test src/Advisor.Tests 2>&1'
}

# old: rules: bash <scripts>/test.sh, run-agent jobs, ~/.local/bin/run-agent are allowed
@test "bash on a run-agent script and both forms of the shell command need no permission" {
  assert_equal "$(rules other)" "$(printf 'ok\nok\nok\nok')"
}

# old: rules: a prefix before the program is not covered (no * before the program)
@test "something put in front of run-agent still asks for permission" {
  has "$(rules envprefix)" '^blocked: env X=1 .*run-agent\.sh --jobs$'
}

# old: rules: settings.json holds the six rules
@test "settings.json holds the six run-agent rules and none that starts with a wildcard" { assert_equal "$(rules six)" ok; }

# old: clean: removes done/logs files older than 30 days, keeps newer
@test "--clean removes files older than 30 days and keeps newer ones" {
  local H="$RUN_AGENT_HOME"
  mkdir -p "$H/done" "$H/logs"
  echo '{}' > "$H/done/900.json"
  mtime "$(( $(date +%s) - 40*86400 ))" "$H/done/900.json" "$H/logs/900.log"
  echo '{}' > "$H/done/901.json"
  unset RUN_AGENT_NOW
  run ra --clean
  assert_file_not_exist "$H/done/900.json"
  assert_file_not_exist "$H/logs/900.log"
  assert_file_exist "$H/done/901.json"
  has "$output" '^removed 2 file(s) older than 30 days'
}

# old: size: --jobs warns when the state dir passes 50 MB
@test "--jobs warns when the state folder passes 50 MB" {
  mkdir -p "$RUN_AGENT_HOME/logs"
  truncate -s 60M "$RUN_AGENT_HOME/logs/big.log"
  has "$(ra --jobs 2>&1)" '^state dir 60 MB, trim with run-agent clean$'
}

# old: runner.log: gone and nothing writes it
@test "there is no runner.log and nothing writes one" {
  ra worker '.' --at $(( RUN_AGENT_NOW + 600 )) --at-text 'in 10m' >/dev/null 2>&1
  assert_file_not_exist "$TEST_HOME/.claude/run-agent/runner.log"
  assert_file_not_exist "$RUN_AGENT_HOME/runner.log"
  run grep -n 'runner\.log' "$RA_SRC/run-agent.sh" "$RA_SRC/runner.sh" "$RA_SRC"/*.py
  assert_failure 1
}

# old: group: dry lists each run and the one window
@test "a dry run of two launches lists both and the one window they share" {
  run ra --relaunch "planner \"Plan A\" in $T + planner \"Plan B\" in $T dry"
  assert_equal "$(grep -c '^run [12]:' <<<"$output")" 2
  has "$output" '^opens in: one new tmux window, 2 panes tiled'
}

# old: group: scheduled group refused
@test "several launches at once cannot be scheduled" {
  run ra --relaunch "planner \"Plan A\" in $T + planner \"Plan B\" in $T at 9pm"
  assert_failure 2
  has "$output" 'start now; schedule each run on its own'
}

# old: group: + inside quotes is not a separator
@test "a + inside a quoted prompt does not split the launch" {
  run ra --relaunch 'planner "Plan A + B" in /tmp dry'
  has "$output" '^command: claude --agent planner "Plan A + B"'
}

# old: jobs: 12 schedulers at once -> 12 ids, each job file holds its own caller's pane and command, no tmp file left
@test "twelve runs scheduled at the same instant each get their own id and job" {
  local R="$T/race" i id at; mkdir -p "$R"; : > "$R.err"
  at=$(( $(date +%s) + 600 ))
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    RUN_AGENT_HOME="$R" python3 "$RA_SRC/jobs.py" write --run-at "$at" --pane "%$i" -- claude --name "lane $i" > "$R.$i" 2>> "$R.err" 3>&- &
  done
  wait
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    id="$(cut -f1 "$R.$i")"
    assert_equal "$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j["id"], j["pane"], j["argv"][-1])' "$R/jobs/$id.json")" "$id %$i lane $i"
  done
  assert_equal "$(ls "$R/jobs" | grep -c '\.json$')" 12
  assert_equal "$(ls "$R/jobs" | grep -vc '\.json$')" 0
  [ ! -s "$R.err" ]
}

# store_refused <run-agent arguments...>: with no RUN_AGENT_HOME (and a fake HOME) the action is refused, no file made
store_refused() {
  local H="$T/fh3"; mkdir -p "$H"
  HOME="$H" RUN_AGENT_HOME= run ra_nofds env -u RUN_AGENT_HOME "$S" "$@"
  assert_failure 2
  assert_equal "$(printf '%s\n' "$output" | tail -n 1)" "test mode: refusing the real job store"
  assert_equal "$(ls -A "$H")" ""
}

# old: guard: job store, RUN_AGENT_HOME unset: '--jobs' refused, exit 2, no file
@test "in test mode --jobs refuses the real job store" { store_refused --jobs; }
# old: guard: job store, RUN_AGENT_HOME unset: '--health' refused, exit 2, no file
@test "in test mode --health refuses the real job store" { store_refused --health; }
# old: guard: job store, RUN_AGENT_HOME unset: '--cancel' refused, exit 2, no file
@test "in test mode --cancel refuses the real job store" { store_refused --cancel; }
# old: guard: job store, RUN_AGENT_HOME unset: '--revive' refused, exit 2, no file
@test "in test mode --revive refuses the real job store" { store_refused --revive; }
# old: guard: job store, RUN_AGENT_HOME unset: '--clean' refused, exit 2, no file
@test "in test mode --clean refuses the real job store" { store_refused --clean; }
# old: guard: job store, RUN_AGENT_HOME unset: 'worker .' refused, exit 2, no file
@test "in test mode scheduling refuses the real job store" { store_refused worker . --at $(( RUN_AGENT_NOW + 600 )); }

# old: guard: job store, RUN_AGENT_HOME under ~/.claude is refused too
@test "in test mode a job store under the home .claude folder is refused" {
  local H="$T/fh3"; mkdir -p "$H"
  HOME="$H" RUN_AGENT_HOME="$H/.claude/run-agent" run ra --jobs
  assert_failure 2
  assert_output "test mode: refusing the real job store"
  # Library: Apple's /usr/bin/python3 keeps its bytecode cache in ~/Library/Caches, whatever the script does
  assert_equal "$(ls -A "$H" | grep -v '^Library$')" ""
}

# old: guard: with the flag claude_environ() is {} and claude_argv() finds no parent
@test "in test mode the scripts cannot see a parent claude process" {
  assert_equal "$(python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import launch; print(launch.claude_environ(), launch.claude_argv())" "$RA_SRC")" "{} []"
}
