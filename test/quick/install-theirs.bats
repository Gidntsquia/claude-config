#!/usr/bin/env bats
# Scenario theirs: the user's own same-name agent, skill, command, hooks folder and settings.json.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file theirs; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "your own files: install.sh succeeds and says it kept your agent and skill" {
  passed "theirs: install.sh exits 0"
  passed "theirs: 'kept yours' printed for the agent"
  passed "theirs: 'kept yours' printed for the skill"
}

# bats test_tags=feature:install
@test "your own files: agent, skill, command, hook and settings.json stay byte-identical" {
  passed "theirs: agent byte-identical"
  passed "theirs: skill byte-identical"
  passed "theirs: command byte-identical"
  passed "theirs: their hook file byte-identical"
  passed "theirs: settings.json byte-identical"
}

# bats test_tags=feature:install
@test "your own files: the repo's other agents and skills are installed next to yours" {
  passed "theirs: the repo's other agents and skills"
}

# bats test_tags=feature:install,escape:1e
@test "your own files: an untracked file with a personal path is a warning naming it, not a failure" {
  passed "theirs: an untracked file with a personal path"
  passed "theirs: ... and no FAIL line"
}

# bats test_tags=feature:install,feature:install-check
@test "your own files: --check passes, the clone is unchanged, no .pre-link file" {
  passed "theirs: --check exits 0 and ends 'all checks passed'"
  passed "theirs: the clone is unchanged"
  passed "theirs: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "theirs: the whole scenario ran to its end with no failed check" {
  ran_clean
}
