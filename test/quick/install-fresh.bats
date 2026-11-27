#!/usr/bin/env bats
# Scenario a: an empty .claude folder.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file a; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install,feature:install-check
@test "fresh install: install.sh exits 0 and install.sh --check passes" {
  passed "a: install.sh exits 0"
  passed "a: install.sh --check exits 0"
}

# bats test_tags=feature:install
@test "fresh install: claude doctor exits 0" {
  passed "a: claude doctor exits 0"
}

# bats test_tags=feature:install
@test "fresh install: claude-config.json names this clone" {
  passed "a: claude-config.json names this clone"
}

# bats test_tags=feature:install
@test "fresh install: the status line, CLAUDE.md, the mod dir and the planner agent are in place" {
  passed "a: settings.json has the repo's statusLine"
  passed "a: CLAUDE.md is linked"
  passed "a: env.CLAUDE_CODE_PLUGIN_DIRS is the defer-artifact mod"
  passed "a: planner agent installed"
}

# bats test_tags=feature:install
@test "fresh install: a rerun with no flags reuses the saved choices and lists the mod dir once" {
  passed "a: rerun with no flags exits 0"
  passed "a: rerun with no flags reuses saved choices"
  passed "a: rerun lists the mod dir once"
}

# bats test_tags=feature:install,feature:install-check
@test "fresh install: no .pre-link file is left and --check shows every repo agent installed or kept" {
  passed "a: no .pre-link anywhere under the home"
  passed "a: --check shows every repo agent installed or kept"
}

# bats test_tags=feature:install
@test "a: the whole scenario ran to its end with no failed check" {
  ran_clean
}
