#!/usr/bin/env bats
# Scenario oldtag: v1.2.1's own install.sh, a pull to this version, the current install.sh.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file oldtag; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "update from v1.2.1: its own installer works and leaves the older layout" {
  passed "oldtag: v1.2.1's install.sh exits 0"
  passed "oldtag: v1.2.1 linked settings.json"
}

# bats test_tags=feature:install
@test "update from v1.2.1: iTerm2 points at the clone until install.sh runs, and not after" {
  [ "$(uname -s)" = Darwin ] || skip "iTerm2 settings are a macOS case"
  if [ "$(uname -s)" = Darwin ]; then passed "oldtag: after the pull, before install.sh"; else skip_if_not_run; fi
  if [ "$(uname -s)" = Darwin ]; then passed "oldtag: iTerm2 no longer loads"; else skip_if_not_run; fi
}

# bats test_tags=feature:install
@test "update from v1.2.1: the current install.sh, no flags, makes hooks and settings.json real" {
  passed "oldtag: the current install.sh"
  passed "oldtag: .claude/hooks is a real folder"
  passed "oldtag: the clone's hooks/usage-guard"
  passed "oldtag: settings.json is a generated file"
}

# bats test_tags=feature:install
@test "update from v1.2.1: --check passes, the clone is unchanged, no .pre-link file" {
  passed "oldtag: --check exits 0 and ends 'all checks passed'"
  passed "oldtag: the clone is unchanged"
  passed "oldtag: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "oldtag: the whole scenario ran to its end with no failed check" {
  ran_clean
}
