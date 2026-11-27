#!/usr/bin/env bats
# Scenario sep22: the layout install.sh made before v1.3.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file sep22; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "updating a pre-v1.3 layout: hooks becomes a real folder of links and the clone keeps its own" {
  passed "sep22: install.sh exits 0"
  passed "sep22: .claude/hooks is now a real folder"
  if on_win_run; then skip_if_not_run; else passed "sep22: .claude/hooks/usage-guard is a link"; fi
  passed "sep22: the clone's hooks/usage-guard is still a real folder"
}

# bats test_tags=feature:install
@test "updating a pre-v1.3 layout: links to things gone from the repo are removed, and it says so" {
  passed "sep22: the commands link"
  passed "sep22: 'removed' printed"
}

# bats test_tags=feature:install
@test "updating a pre-v1.3 layout: settings.json becomes a real file" {
  passed "sep22: settings.json is a generated file"
}

# bats test_tags=feature:install
@test "updating a pre-v1.3 layout: iTerm2 stops loading its preferences from the clone" {
  [ "$(uname -s)" = Darwin ] || skip "iTerm2 settings are a macOS case"
  if [ "$(uname -s)" = Darwin ]; then passed "sep22: iTerm2 no longer loads"; else skip_if_not_run; fi
}

# bats test_tags=feature:install
@test "updating a pre-v1.3 layout: --check passes, the clone is unchanged, no .pre-link file" {
  passed "sep22: --check exits 0 and ends 'all checks passed'"
  passed "sep22: the clone is unchanged"
  passed "sep22: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "updating a pre-v1.3 layout: a second run with no flags passes the same checks" {
  passed "sep22: rerun with no flags exits 0"
  passed "sep22 rerun: --check exits 0 and ends 'all checks passed'"
  passed "sep22 rerun: the clone is unchanged"
  passed "sep22 rerun: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "sep22: the whole scenario ran to its end with no failed check" {
  ran_clean
}
