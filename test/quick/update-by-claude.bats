#!/usr/bin/env bats
# UPDATING.md's own commands, read out of the page and run on an older install that has the user's edits.
# What this does not show is Claude following the page: bin/release/rehearsal.sh does that (a real login).

load ../helpers/common

# step <n>: the lines of step <n> under "## Steps"
step() {
  awk -v n="$1" '/^## /{ on = ($0 == "## Steps"); in_step = 0; next }
    on && /^[0-9]+\. /{ in_step = (index($0, n ". ") == 1) }
    on && in_step' "$REPO/UPDATING.md"
}
# command_in <n> <start of command>: the first `code span` of step <n> that starts so; a page without it fails
command_in() {
  local span
  span="$(step "$1" | grep -oE '`[^`]+`' | sed 's/^`//; s/`$//' | awk -v s="$2" 'index($0, s) == 1' | head -1)"
  [ -n "$span" ] || { echo "UPDATING.md step $1 gives no command starting: $2" >&2; return 1; }
  printf '%s\n' "$span"
}

git_as() { git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }
release() { git -C "$ORIGIN" add -A && git_as -C "$ORIGIN" commit -qm "$1" && git -C "$ORIGIN" tag "$1"; }

# An origin holding this working tree as v9.0.0, then v9.1.0 (a new skill) and a pre-release; a clone installed at
# v9.0.0 into the test's home, with an edited CLAUDE.md and a file of the user's own.
setup() {
  temp_home
  mkdir -p "$TEST_HOME/bin"
  printf '#!/bin/sh\nexit 0\n' > "$TEST_HOME/bin/claude"
  [ "$(uname -s)" != Darwin ] || cp "$REPO/test/fixtures/install/defaults" "$TEST_HOME/bin/defaults"
  chmod +x "$TEST_HOME/bin/"*
  export PATH="$TEST_HOME/bin:$PATH"
  ORIGIN="$BATS_TEST_TMPDIR/Gidntsquia/claude-config"
  mkdir -p "$ORIGIN"
  ( cd "$REPO" && git ls-files -z --cached --others --exclude-standard |
      while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done |
      tar --null -T - -cf - ) | tar -xf - -C "$ORIGIN"
  git -C "$ORIGIN" init -q
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  release v9.0.0
  export REPO_UNDER_UPDATE="$TEST_HOME/claude-config"
  git clone -q "$ORIGIN" "$REPO_UNDER_UPDATE"
  ( cd "$REPO_UNDER_UPDATE" && ./install.sh --projects "$TEST_HOME/files" --no-terminal --statusline squid \
      --settings merge --agent-clash replace ) > "$BATS_TEST_TMPDIR/install.log" 2>&1
  mkdir -p "$ORIGIN/skills/zz-new-in-release"
  printf -- '---\nname: zz-new-in-release\ndescription: new in 9.1\n---\n' > "$ORIGIN/skills/zz-new-in-release/SKILL.md"
  release v9.1.0
  echo "beta only" > "$ORIGIN/BETA.txt"
  release v9.2.0-beta.1
  echo "my own rule" >> "$REPO_UNDER_UPDATE/CLAUDE.md"
  echo "my own notes" > "$REPO_UNDER_UPDATE/my-notes.txt"
}

# Steps 3 to 8 as the page gives them (without gh).
update_as_documented() {
  local find look keep move pop relink
  find="$(command_in 3 'git -C "$REPO" ls-remote')" || return 1
  look="$(command_in 4 'git -C "$REPO" fetch')" || return 1
  keep="$(step 5 | grep -oE '`git -C "\$REPO" [^`]+`' | sed 's/^`//; s/`$//' | sed -n 2p)"
  move="$(command_in 6 'git -C "$REPO" merge --ff-only')" || return 1
  pop="$(command_in 7 'git -C "$REPO" stash pop')" || return 1
  relink="$(command_in 8 'cd "$REPO" && ./install.sh')" || return 1
  local REPO="$REPO_UNDER_UPDATE" TAG
  TAG="$(eval "$find")" && eval "$look" && eval "$keep" && eval "$move" || return 1
  case "$keep" in *"stash push"*) eval "$pop" || return 1 ;; esac
  ( eval "$relink" )
}

# bats test_tags=feature:update-by-claude
@test "update: UPDATING.md's commands move the install to the latest release, not a pre-release" {
  run update_as_documented
  assert_success
  run git -C "$REPO_UNDER_UPDATE" describe --tags --exact-match
  assert_output "v9.1.0"
}

# bats test_tags=feature:update-by-claude
@test "update: the user's edits and own files are still there afterwards" {
  run update_as_documented
  assert_success
  run grep -x "my own rule" "$TEST_HOME/.claude/CLAUDE.md"
  assert_success
  run cat "$REPO_UNDER_UPDATE/my-notes.txt"
  assert_output "my own notes"
  run git -C "$REPO_UNDER_UPDATE" stash list
  assert_output ""
}

# bats test_tags=feature:update-by-claude
@test "update: what the release added is linked and install.sh --check finds every link" {
  run update_as_documented
  assert_success
  assert_file_exist "$TEST_HOME/.claude/skills/zz-new-in-release/SKILL.md"
  cd "$REPO_UNDER_UPDATE"
  run ./install.sh --check
  assert_output --partial "PASS skill zz-new-in-release"
  # the one FAIL allowed: claude is a no-op here, so nothing registers the MCP server
  run bash -c './install.sh --check | grep "^FAIL" | grep -v "FAIL run-agent MCP server not registered"'
  assert_output ""
}
