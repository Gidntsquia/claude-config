#!/usr/bin/env bats
# Scenario moved: install, move the clone, plain ./install.sh from the new path.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats
load ../helpers/bare-install

setup_file() { install_setup_file moved; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install,feature:updates
@test "moved clone: the first install works" {
  passed "moved: first install exits 0"
}

# bats test_tags=feature:install,feature:updates,escape:1c
@test "moved clone: plain ./install.sh from the new path relinks everything and calls nothing yours" {
  passed "moved: plain ./install.sh from the new path exits 0"
  passed "moved: it says what it relinked"
  passed "moved: no clash and no 'kept yours'"
  passed "moved: no link under .claude is broken"
}

# bats test_tags=feature:install,feature:updates
@test "moved clone: settings.json names the new path only" {
  passed "moved: settings.json names the new path only"
}

# bats test_tags=feature:install,feature:updates,feature:install-check
@test "moved clone: --check passes, the clone is unchanged, no .pre-link file" {
  passed "moved: --check exits 0 and ends 'all checks passed'"
  passed "moved: the clone is unchanged"
  passed "moved: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install,feature:updates
@test "moved clone without claude-config.json: plain ./install.sh relinks everything and calls nothing yours" {
  passed "moved, no claude-config.json: plain ./install.sh exits 0"
  passed "moved, no claude-config.json: it says what it relinked"
  passed "moved, no claude-config.json: no clash and no 'kept yours'"
  passed "moved, no claude-config.json: no link under .claude is broken"
}

# bats test_tags=feature:install,feature:updates
@test "moved clone without claude-config.json: the status line and the terminal setup stay installed" {
  passed "moved, no claude-config.json: the status line is still the repo's"
  if terminal_run; then passed "moved, no claude-config.json: the terminal setup is still installed"; else skip_if_not_run; fi
}

# bats test_tags=feature:install,feature:updates,feature:install-check
@test "moved clone without claude-config.json: --check passes, the clone is unchanged, no .pre-link file" {
  passed "moved, no claude-config.json: --check exits 0 and ends 'all checks passed'"
  passed "moved, no claude-config.json: the clone is unchanged"
  passed "moved, no claude-config.json: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install,feature:updates
@test "moved: the whole scenario ran to its end with no failed check" {
  ran_clean
}

# bats test_tags=feature:updates
@test "plain ./install.sh keeps every choice made at the first install" {
  bare_home
  cfg="$TEST_HOME/.claude/claude-config.json"
  run bash "$REPO/install.sh" --projects "$TEST_HOME/work" --no-terminal --agent-clash skip --statusline keep --settings keep
  assert_success
  cp "$cfg" "$BATS_TEST_TMPDIR/first.json"
  run bash "$REPO/install.sh"
  assert_success
  run diff "$BATS_TEST_TMPDIR/first.json" "$cfg"
  assert_output ""
  assert_success
}
