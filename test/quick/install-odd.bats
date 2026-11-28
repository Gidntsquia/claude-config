#!/usr/bin/env bats
# Scenario odd: clone and projects folder with spaces in their paths.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file odd; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "paths with spaces: install.sh works and creates the projects folder" {
  passed "odd: install.sh exits 0"
  passed "odd: the projects folder with a space exists"
}

# bats test_tags=feature:install
@test "paths with spaces: claude-config.json keeps both paths whole" {
  passed "odd: claude-config.json keeps both paths whole"
}

# bats test_tags=feature:install,feature:install-check
@test "paths with spaces: --check passes, the clone is unchanged, no .pre-link file" {
  passed "odd: --check exits 0 and ends 'all checks passed'"
  passed "odd: the clone is unchanged"
  passed "odd: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "paths with spaces: a rerun passes the same checks" {
  passed "odd: rerun with no flags exits 0"
  passed "odd rerun: --check exits 0 and ends 'all checks passed'"
  passed "odd rerun: the clone is unchanged"
  passed "odd rerun: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "odd: the whole scenario ran to its end with no failed check" {
  ran_clean
}
