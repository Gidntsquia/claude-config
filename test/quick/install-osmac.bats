#!/usr/bin/env bats
# Scenario osmac: CLAUDE_CONFIG_INSTALL_OS=macos, then the same home as plain Linux.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file osmac; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "install as a Mac: the common and macOS tools are linked, no WSL tool and no .ps1" {
  passed "osmac: install.sh as a Mac exits 0"
  passed "osmac: local-tools holds exactly"
  passed "osmac: every tool is a link into"
  passed "osmac: no tool of local-tools/wsl"
  passed "osmac: no .ps1 is installed"
}

# bats test_tags=feature:install
@test "install as a Mac: --check passes and lists win.sh and evshow.sh" {
  passed "osmac: --check exits 0"
  passed "osmac: --check prints a PASS line"
}

# bats test_tags=feature:install
@test "install as a Mac: --check says whether Firefox is installed, and a missing one is only a warning" {
  passed "osmac: --check with Firefox present"
  passed "osmac: --check without Firefox"
  passed "osmac: ... and still exits 0"
}

# bats test_tags=feature:install
@test "rerun as plain Linux: only the common tools remain" {
  passed "osmac: a rerun as plain Linux"
}

# bats test_tags=feature:install
@test "install as a Mac: the clone is unchanged" {
  passed "osmac: the clone is unchanged"
}

# bats test_tags=feature:install
@test "osmac: the whole scenario ran to its end with no failed check" {
  ran_clean
}
