#!/usr/bin/env bats
# Where a typed /run-agent command would run: --cwd, -C, bare folder names, and what is printed outside tmux.
load ../helpers/common
load ../helpers/run-agent

setup() {
  ra_setup
  load ../fixtures/run-agent/tilde
  # the line to type for a worker carries the subagent caps (usage-guard R15)
  WE="CLAUDE_CODE_SUBAGENT_MODEL=sonnet CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1"
  LAST_USAGE="                         bare name found nowhere, or a path that is a file); creates nothing"
}
teardown() { ra_teardown; }

# bats file_tags=feature:run-agent

# old: a: existing absolute dir
@test "/run-agent planner with an existing absolute folder prints the cd line" {
  ra_check 1 "cd '$T/sibling' && claude --agent planner \"x\" --name \"planner: sibling (fable)\"" planner x --cwd "$T/sibling"
}
# old: a: existing relative dir with /, -C
@test "/run-agent -C takes a relative folder; a worker line carries the subagent caps" {
  ra_check 1 "cd '$T/sibling' && $WE claude --agent worker \".\" --name \"worker: sibling (sonnet)\"" worker -C ../../sibling
}
# old: a: dir with a space, --cwd= form, model
@test "/run-agent --cwd= takes a folder with a space, with a model" {
  ra_check 1 "cd '$T/my project' && $WE claude --agent worker \"go\" --model opus --name \"worker: my project (opus)\"" \
    worker go "--cwd=$T/my project" -- --model opus
}
# old: a: ~ expands to $HOME
@test "/run-agent --cwd tilde means the home folder" {
  ra_check 1 "cd '$TEST_HOME' && $WE claude --agent worker \".\" --name \"worker: $(basename "$TEST_HOME") (sonnet)\"" worker --cwd "$TILDE_ALONE"
}
# old: b: bare name = sibling of the git root
@test "/run-agent a bare folder name means the sibling of the git root" {
  ra_check 1 "cd '$T/sibling' && $WE claude --agent worker \".\" --name \"worker: sibling (sonnet)\"" worker --cwd sibling
}
# old: b: bare name under the cwd wins
@test "/run-agent a folder under the current one wins over the sibling" {
  mkdir -p "$T/repo/sub/sibling"
  ra_check 1 "cd '$T/repo/sub/sibling' && $WE claude --agent worker \".\" --name \"worker: sibling (sonnet)\"" worker --cwd sibling
}
# old: b: bare name found nowhere
@test "/run-agent a bare folder name found nowhere says where it looked" {
  ra_check 2 "no such directory: nope-xyz (looked in $T/repo/sub, $T)" worker --cwd nope-xyz
}
# old: c: missing absolute dir -> exit 2 | c: nothing created
@test "/run-agent a missing absolute folder is refused and not created" {
  ra_check 2 "no such directory: $T/missing" worker --cwd "$T/missing"
  assert_file_not_exist "$T/missing"
}
# old: c: missing ~ dir -> exit 2 | c: nothing created
@test "/run-agent a missing folder under the home folder is refused and not created" {
  ra_check 2 "no such directory: $TEST_HOME/no-such-run-agent-dir-$$" worker --cwd "$TILDE_DIR_MISSING"
  assert_file_not_exist "$TEST_HOME/no-such-run-agent-dir-$$"
}
# old: c: a file -> not a directory
@test "/run-agent a file given as the folder is refused" {
  touch "$T/afile"
  ra_check 2 "not a directory: $T/afile" worker --cwd "$T/afile"
}
# old: d: no dir, name from git root
@test "/run-agent without a folder names the run after the git root" {
  ra_check 1 "$WE claude --agent worker \".\" --name \"worker: repo (sonnet)\"" worker
}
# old: d: no dir, model
@test "/run-agent without a folder, with a model" {
  ra_check 1 "claude --agent planner \"x\" --model opus --name \"planner: repo (opus)\"" planner x -- --model opus
}
# old: d: planner without a prompt -> no prompt argument
@test "/run-agent planner without a prompt passes no prompt" {
  ra_check 1 "claude --agent planner --name \"planner: repo (fable)\"" planner
}
# old: d: planner without a prompt, with a dir
@test "/run-agent planner without a prompt, in another folder" {
  ra_check 1 "cd '$T/sibling' && claude --agent planner --name \"planner: sibling (fable)\"" planner --cwd "$T/sibling"
}
# old: d: extra word -> usage
@test "/run-agent an extra word shows the usage text" {
  ra_check 2 "$LAST_USAGE" worker . extra
}
# old: e: --name wins over the dir name
@test "/run-agent a typed --name wins over the folder name" {
  ra_check 1 "cd '$T/sibling' && $WE claude --agent worker \"x\" --name \"mine\"" worker x --cwd "$T/sibling" -- --name mine
}
# old: two dirs -> usage
@test "/run-agent two folders show the usage text" {
  ra_check 2 "$LAST_USAGE" worker --cwd a -C b
}
# old: resolve: . and .. collapsed
@test "run-agent --resolve collapses . and .. in a folder path" {
  run ra --resolve "$T/repo/./sub/../sub/"
  assert_output "$T/repo/sub	exists"
}
# old: resolve: missing path
@test "run-agent --resolve reports a missing folder" {
  run ra --resolve "$TILDE_DIR_MISSING"
  assert_output "$TEST_HOME/no-such-run-agent-dir-$$	missing"
}
