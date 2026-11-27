#!/usr/bin/env bats
# Scenario plist: a September install, updated as UPDATING.md says, keeps iTerm2's plist.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file plist; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "update from September: iTerm2's own write shows as a local change in the clone" {
  passed "plist: the September commit tracks"
  passed "plist: git sees iTerm2's write"
}

# bats test_tags=feature:install
@test "update from September: the plist iTerm2 uses is in place after the pull, byte for byte" {
  passed "plist: after the pull the plist"
  passed "plist: ... and is what iTerm2 last saved"
  passed "plist: the copy outside the clone"
}

# bats test_tags=feature:install
@test "update from September: install.sh leaves the plist alone and stops iTerm2 loading from the clone" {
  passed "plist: the current install.sh exits 0"
  passed "plist: install.sh left the plist alone"
  if [ "$(uname -s)" = Darwin ]; then passed "plist: iTerm2 no longer loads"; else skip_if_not_run; fi
}

# bats test_tags=feature:install
@test "update from September: --check passes, only the kept plist is new in the clone, no .pre-link file" {
  passed "plist: --check exits 0"
  passed "plist: the kept plist is the only thing"
  passed "plist: no .pre-link"
}

# bats test_tags=feature:install
@test "plist: the whole scenario ran to its end with no failed check" {
  ran_clean
}
