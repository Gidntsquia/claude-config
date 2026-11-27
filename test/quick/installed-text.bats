#!/usr/bin/env bats
# What installs into ~/.claude carries nothing of the author's own machine or projects.
# From test/owner-text.sh (its pin on the wording of CLAUDE.md line 8 is dropped: it tested prose, not behaviour)
# and the personal-path step of the old CI job.

load ../helpers/common

# bats test_tags=feature:installed-text
@test "no installed file names the author's projects or says to push the config repo" {
  cd "$REPO"
  run grep -rn -e 'push changes there' -e 'descent-of-essence' -e 'Wordbound' CLAUDE.md settings.json agents skills hooks bin
  assert_output ""
  assert_failure 1
}

# bats test_tags=feature:installed-text
@test "settings.json is valid JSON" {
  run python3 -m json.tool "$REPO/settings.json"
  assert_success
}

# bats test_tags=feature:installed-text
@test "no tracked installed file holds a personal home path" {
  run bash "$REPO/bin/find-personal-paths.sh" "$REPO"
  refute_output --regexp '^[^W]'
  assert_success
}
