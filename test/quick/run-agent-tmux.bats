# bats file_tags=feature:run-agent
# A launch from inside tmux: the pane is replaced by claude in the right folder (private tmux server, fake claude).
load ../helpers/common
load ../helpers/run-agent

setup() { ra_setup; ra_tmux_setup; : > "$RA_OUT"; }
teardown() { ra_teardown; }

planner_in_my_project() {
  keys "'$S' planner 'fetch it' --cwd '$T/my project'"
  claude_ran '^subenv='
}

# old: tmux: claude started in the dir | tmux: pane_current_path is the dir
@test "a launch from tmux starts claude in the chosen folder, spaces and all" {
  planner_in_my_project
  fhas "$RA_OUT" "^pwd=$T/my project\$"
  assert_equal "$(TM display -p -t t '#{pane_current_path}')" "$T/my project"
}

# old: tmux: --name "planner: my project (fable)" is one argument
@test "the session name reaches claude as one argument" {
  planner_in_my_project
  fhas "$RA_OUT" '^arg=planner: my project (fable)$'
}

# old: tmux: shell left in the pane
@test "when claude exits a shell is left in the pane" {
  planner_in_my_project
  ra_ready t
  assert_equal "$(TM display -p -t t '#{pane_dead}')" 0
}

# old: env caps: a planner launch carries no subagent caps
@test "a planner launch carries no subagent limits" {
  planner_in_my_project
  fhas "$RA_OUT" '^subenv=///$'
}

# old: env caps: a worker launch carries sonnet subagents, 3 at a time, depth 1, and no MODEL_FORCE | env caps: the shell left in the pane does not keep them
@test "a worker launch carries sonnet subagents, 3 at a time, depth 1, and the shell left behind does not keep them" {
  keys "'$S' worker '.' --cwd '$T/my project'"
  claude_ran '^subenv='
  fhas "$RA_OUT" '^subenv=sonnet//3/1$'
  ra_ready t
  keys "echo \"left=\${CLAUDE_CODE_SUBAGENT_MODEL:-none}\" > '$T/left.out'"
  wait_until 15 grep -q '^left=' "$T/left.out"
  fhas "$T/left.out" '^left=none$'
}

# old: env caps: the no-tmux line to type carries them
@test "outside tmux the worker line to type carries the subagent limits" {
  run ra worker .
  has "$output" '^CLAUDE_CODE_SUBAGENT_MODEL=sonnet CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 claude --agent worker'
}
