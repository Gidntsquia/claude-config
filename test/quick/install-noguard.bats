#!/usr/bin/env bats
# Scenario noguard: the usage-guard script is missing.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file noguard; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "usage-guard script missing: the install works and leaves 7 usage-guard hook commands" {
  passed "noguard: install.sh exits 0"
  passed "noguard: the guard script is absent"
  passed "noguard: the installed settings.json has 7"
}

# bats test_tags=feature:install,escape:1b
@test "usage-guard script missing: each of the 7 hook commands exits 0" {
  passed -n 7 "noguard: hook command "
}

# bats test_tags=feature:install
@test "usage-guard script missing: you are told once per session that the guard is off" {
  passed "noguard: the first call says the guard is off"
  passed -n 6 "noguard: call "
}

# bats test_tags=feature:install,feature:install-check
@test "usage-guard script missing: a rerun and --check pass, the clone is unchanged, no .pre-link file" {
  passed "noguard: rerun exits 0"
  passed "noguard: --check exits 0 and ends 'all checks passed'"
  passed "noguard: the clone is unchanged"
  passed "noguard: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "noguard: the whole scenario ran to its end with no failed check" {
  ran_clean
}
