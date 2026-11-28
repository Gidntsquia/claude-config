#!/usr/bin/env bats
# Scenario b: a .claude that already has the user's settings.json, CLAUDE.md and agents/planner.md.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats
load ../helpers/bare-install

setup_file() { install_setup_file b; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install,feature:install-check
@test "existing settings: install.sh exits 0 and install.sh --check passes" {
  passed "b: install.sh exits 0"
  passed "b: install.sh --check exits 0"
}

# bats test_tags=feature:install
@test "existing settings: claude doctor exits 0" {
  passed "b: claude doctor exits 0"
}

# bats test_tags=feature:install
@test "existing settings: claude-config.json names this clone" {
  passed "b: claude-config.json names this clone"
}

# bats test_tags=feature:install,feature:user-settings
@test "existing settings: your model, status line and deny list stay, and the repo's keys are added" {
  passed "b: model unchanged"
  passed "b: statusLine unchanged"
  passed "b: deny list kept and unioned"
  passed "b: repo keys added"
}

# bats test_tags=feature:install,feature:user-settings
@test "existing settings: your plugin dirs and hooks stay, with the repo's added after them" {
  passed "b: your CLAUDE_CODE_PLUGIN_DIRS kept"
  passed "b: your hooks key kept"
}

# bats test_tags=feature:install,feature:user-settings
@test "existing settings: CLAUDE.md stays byte-identical and --agent-clash replace installs the repo's planner" {
  passed "b: CLAUDE.md byte-identical"
  passed "b: planner.md is now the repo's"
}

# bats test_tags=feature:install
@test "existing settings: a rerun with no flags reuses the saved choices and lists the mod dir once" {
  passed "b: rerun with no flags exits 0"
  passed "b: rerun with no flags reuses saved choices"
  passed "b: rerun lists the mod dir once"
}

# bats test_tags=feature:install,feature:install-check
@test "existing settings: no .pre-link file is left and --check shows every repo agent installed or kept" {
  passed "b: no .pre-link anywhere under the home"
  passed "b: --check shows every repo agent installed or kept"
}

# bats test_tags=feature:install
@test "b: the whole scenario ran to its end with no failed check" {
  ran_clean
}

# bats test_tags=feature:user-settings
@test "a skill of yours with the same name stays as it is when --agent-clash is not given" {
  bare_home
  mine="$TEST_HOME/.claude/skills/run-agent"
  mkdir -p "$mine"
  printf -- '---\nname: run-agent\n---\nmy own skill\n' > "$mine/SKILL.md"
  cp "$mine/SKILL.md" "$BATS_TEST_TMPDIR/before.md"
  run bash "$REPO/install.sh" --projects "$TEST_HOME/files" --no-terminal
  assert_success
  assert_output --partial "kept yours: $mine (repo's not installed)"
  run cmp "$mine/SKILL.md" "$BATS_TEST_TMPDIR/before.md"
  assert_success
}

# bats test_tags=feature:install-check
@test "--check names a leftover .pre-link backup inside skills and agents" {
  bare_home
  c="$TEST_HOME/.claude"
  mkdir -p "$c/skills/old.pre-link" "$c/agents"
  : > "$c/agents/planner.md.pre-link"
  run bash "$REPO/install.sh" --check
  # --check fails here (nothing is installed); the leftovers are listed either way
  assert_output --partial "WARN leftover from an older install, safe to delete: $c/skills/old.pre-link"
  assert_output --partial "WARN leftover from an older install, safe to delete: $c/agents/planner.md.pre-link"
}
