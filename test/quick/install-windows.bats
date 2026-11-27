#!/usr/bin/env bats
# Scenario windows: CLAUDE_CONFIG_INSTALL_OS=windows with symlinks refused. It is what install.sh does when told it
# is on Windows without WSL; the real Git Bash run of the install tests is on the Windows CI runner.

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file windows; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:windows-install
@test "windows: install.sh succeeds and copies what it cannot link" {
  passed "windows: install.sh exits 0"
  passed "windows: it says it copied"
  passed "windows: the planner agent is a real file"
}

# bats test_tags=feature:windows-install
@test "windows: status line, tmux setup and run-agent are skipped and named" {
  passed "windows: it names what is skipped"
  passed "windows: no status line"
  passed "windows: no tmux setup"
}

# bats test_tags=feature:windows-install,feature:install-check
@test "windows: --check accepts the copies" {
  passed "windows: --check exits 0"
}

# bats test_tags=feature:windows-install
@test "windows: a rerun succeeds and the clone is unchanged" {
  passed "windows: a rerun replaces"
  passed "windows: the clone is unchanged"
}

# bats test_tags=feature:windows-install
@test "windows: the whole scenario ran to its end with no failed check" {
  ran_clean
}
