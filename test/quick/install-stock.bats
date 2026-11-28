#!/usr/bin/env bats
# Scenario stock: /bin/bash with the stock PATH; python3 and tmux missing.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file stock; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "python3 and tmux missing: install.sh stops, names both with their install commands, changes nothing" {
  passed "stock: python3 and tmux absent"
  passed "stock: names python3 and its install command"
  passed "stock: names tmux and its install command"
  passed "stock: nothing was changed"
}

# bats test_tags=feature:install
@test "tmux missing with --terminal: install.sh stops, names it, changes nothing" {
  passed "stock: tmux absent with --terminal"
  passed "stock, tmux only: names tmux and its install command"
  passed "stock, tmux only: nothing was changed"
}

# bats test_tags=feature:install
@test "stock PATH: the install works and prints the claude mcp add command while claude is absent" {
  passed "stock: /bin/bash install with the stock PATH exits 0"
  passed "stock: claude absent"
}

# bats test_tags=feature:install
@test "stock PATH: a rerun with claude present works" {
  passed "stock: rerun once claude is on PATH"
}

# bats test_tags=feature:install,feature:install-check
@test "stock PATH: --check passes, the clone is unchanged, no .pre-link file" {
  passed "stock: --check exits 0 and ends 'all checks passed'"
  passed "stock: the clone is unchanged"
  passed "stock: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "stock: the whole scenario ran to its end with no failed check" {
  ran_clean
}
