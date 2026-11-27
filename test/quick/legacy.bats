#!/usr/bin/env bats
# The three large old scripts, each run whole from one test until its checks are split into @test cases.
# They use the real home (install-scenarios.sh finds the Claude Code install there and makes its own
# throwaway homes; none writes to it), so no test here calls temp_home.

load ../helpers/common

# bats test_tags=feature:run-agent
@test "run-agent: every parse, schedule, handoff and jobs case passes on a private tmux server" {
  if on_windows; then skip "run-agent needs tmux, which Windows Git Bash lacks"; fi
  run_legacy "$REPO/skills/run-agent/scripts/test.sh"
  refute_output --regexp '^ *([0-9]+s )?FAIL '
  assert_success
}

# bats test_tags=feature:evaluator-tools
@test "evaluator tools: layout, syntax, a whole evshow run and the macOS tools against stand-ins" {
  if on_windows; then skip "the evaluator tools need tmux, which Windows Git Bash lacks"; fi
  run_legacy "$REPO/test/evaluator-tools.sh"
  refute_output --regexp '^FAIL '
  assert_output --partial "all checks passed"
  assert_success
}

# bats test_tags=feature:install
@test "install.sh: every install and update scenario passes in a throwaway home" {
  flag=--terminal
  if on_windows || [ -n "${WSL_DISTRO_NAME:-}" ]; then flag=--no-terminal; fi
  # In CI a checkout without the old tags is a failure, not a skip.
  if [ -n "${CI:-}" ]; then export SCN_NEED_OLDTAG=1; fi
  run_legacy "$REPO/test/install-scenarios.sh" "$flag"
  refute_output --regexp '^FAIL '
  assert_output --partial "all install scenarios passed"
  assert_success
}
