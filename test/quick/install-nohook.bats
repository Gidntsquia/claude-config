#!/usr/bin/env bats
# Scenario nohook: every hook command of the installed settings file with the file it runs missing.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file nohook; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "a hook's script missing: the install works and has at least 8 hook commands" {
  passed "nohook: install.sh exits 0"
  passed "nohook: the installed settings file has at least 8"
}

# bats test_tags=feature:install
@test "a hook's script missing: every installed hook command still exits 0" {
  skip_if_not_run
  passed -n "$(cat "$SCN_OUT/hooks")" "nohook: hook "
}

# bats test_tags=feature:install,feature:install-check
@test "a hook's script missing: --check passes, the clone is unchanged, no .pre-link file" {
  passed "nohook: --check exits 0 and ends 'all checks passed'"
  passed "nohook: the clone is unchanged"
  passed "nohook: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "nohook: the whole scenario ran to its end with no failed check" {
  ran_clean
}
