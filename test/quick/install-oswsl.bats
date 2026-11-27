#!/usr/bin/env bats
# Scenario oswsl: CLAUDE_CONFIG_INSTALL_OS=wsl, then the same home as a Mac.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file oswsl; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "install as WSL: the common and WSL tools are linked and no macOS tool" {
  passed "oswsl: install.sh as WSL exits 0"
  passed "oswsl: local-tools holds exactly"
  passed "oswsl: every tool is a link into"
  passed "oswsl: no tool of local-tools/macos"
  passed "oswsl: winctl.ps1 and screen-capture.ps1"
}

# bats test_tags=feature:install,feature:install-check
@test "install as WSL: --check passes and lists win.sh and evshow.sh" {
  passed "oswsl: --check as WSL exits 0"
  passed "oswsl: --check prints a PASS line"
}

# bats test_tags=feature:install,feature:install-check
@test "--check as a Mac on a WSL install fails and names the WSL tools" {
  passed "oswsl: --check as a Mac FAILs"
  passed "oswsl: ... and names winctl.ps1"
}

# bats test_tags=feature:install
@test "rerun as a Mac: the WSL tools are swapped for the macOS ones" {
  passed "oswsl: a rerun as a Mac exits 0"
  passed "oswsl rerun as mac: local-tools holds exactly"
  passed "oswsl rerun as mac: every tool is a link into"
  passed "oswsl rerun as mac: no tool of local-tools/wsl"
}

# bats test_tags=feature:install
@test "install as WSL: the clone is unchanged" {
  passed "oswsl: the clone is unchanged"
}

# bats test_tags=feature:install
@test "oswsl: the whole scenario ran to its end with no failed check" {
  ran_clean
}
