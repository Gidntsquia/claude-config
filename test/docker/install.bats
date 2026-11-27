#!/usr/bin/env bats
# The install scenarios in a fresh ubuntu:24.04 container: no runner image, only git, curl, python3, tmux
# and Claude Code.

load ../helpers/common

# bats test_tags=feature:install
@test "docker: every install scenario passes in a fresh ubuntu:24.04 container" {
  command -v docker >/dev/null 2>&1 || skip "docker missing"
  docker info >/dev/null 2>&1 || skip "docker is installed but its daemon is not running"
  if [ -n "${CI:-}" ]; then export SCN_NEED_OLDTAG=1; fi
  run bash "$REPO/bin/release/docker-image.sh"
  refute_a_line_matches '^not ok '
  assert_success
}
