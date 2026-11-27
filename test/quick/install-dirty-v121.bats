#!/usr/bin/env bats
# Scenario dirty from v1.2.1: an install with the user's own commits and edits, updated as UPDATING.md says.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file dirty-v121; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: the starting install is as described" {
  passed "dirty: the install.sh of v1.2.1 exits 0"
  passed "dirty: the clone is clean after that install"
  passed "dirty: his settings file is his own copy"
  passed "dirty: main has two commits the release lacks"
  passed "dirty: .claude/skills/review-skill is a link before"
}

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: the merge, the settings conflict and install.sh keeping your skill happen" {
  passed "update: the current install.sh, no flags, exits 0"
  passed "dirty from v1.2.1: step 6 was a merge"
  passed "dirty from v1.2.1: the stash pop did stop"
  passed "dirty from v1.2.1: install.sh said it kept his skill"
}

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: your commits, your files in them and your branch are still there" {
  passed "dirty: the clone holds the release"
  passed "dirty: his two commits are still in main's history"
  passed "dirty: 'my backup script' and"
  passed "dirty: his committed file"
  passed "dirty: his committed line is still in agents/planner.md"
  passed "dirty: .claude/agents/planner.md shows his committed line"
  passed "dirty: his branch my-experiments"
}

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: session files, history and plugins are byte-identical" {
  passed "dirty: his session files, history.jsonl"
  passed "dirty: there were 5 such files"
}

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: your settings file stays yours, with your keys and your edit" {
  passed "dirty: .claude's settings file is still his own copy"
  passed "dirty: his settings keys remain"
  passed "dirty: .claude's settings file holds his edit"
  passed "dirty: .claude's settings file parses as JSON"
}

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: your uncommitted lines and notes file are back and the stash is empty" {
  passed "dirty: his line is still in CLAUDE.md"
  passed "dirty: his line is still in agents/helper.md"
  passed "dirty: his untracked notes file"
  passed "dirty: git stash list is empty"
  passed "dirty: .claude/CLAUDE.md shows his line too"
}

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: the clone's settings file keeps your edit, takes the release's values, no conflict markers" {
  passed "dirty: his edit is still in the clone's settings file"
  passed "dirty: no conflict markers"
  passed "dirty: the settings file parses as JSON and holds"
}

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: your own skill folder is untouched and everything else links into the clone" {
  passed "dirty: his real folder"
  passed "dirty: ... and is still a real folder"
  passed "dirty: every other skill is a link"
  passed "dirty: the agents resolve into the clone"
  passed "dirty: every link under .claude points into the clone"
}

# bats test_tags=feature:install
@test "update from v1.2.1 with your edits: --check passes, no new .pre-link copy, git status lists only your four files" {
  passed "dirty: --check exits 0"
  passed "dirty: the update made no .pre-link copy"
  passed "dirty: git status lists his four files"
}

# bats test_tags=feature:install
@test "dirty-v121: the whole scenario ran to its end with no failed check" {
  ran_clean
}
