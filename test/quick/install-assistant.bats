#!/usr/bin/env bats
# Scenario assistant: --agent-clash keep, and the assistant agent linked into a project.
# setup_file runs it once (test/helpers/install-run.bash); it needs an installed Claude Code (no login is used).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file assistant; }
teardown_file() { install_teardown_file; }

# bats test_tags=feature:install
@test "--agent-clash keep: the clashing agent gets a renamed copy and the assistant is not installed globally" {
  passed "assistant: install.sh --agent-clash keep"
  passed "assistant: keep made the renamed copy"
  passed "assistant: no assistant file or copy"
}

# bats test_tags=feature:install
@test "assistant linked into a project: it finds its MCP server and guard hook in the clone" {
  passed "assistant: both frontmatter commands"
  passed "assistant: the MCP server resolves"
  passed "assistant: the guard hook resolves"
}

# bats test_tags=feature:install
@test "--agent-clash keep: --check passes the assistant, the clone is unchanged, no .pre-link file" {
  passed "assistant: --check has a PASS line"
  passed "assistant: --check exits 0 and ends 'all checks passed'"
  passed "assistant: the clone is unchanged"
  passed "assistant: no .pre-link anywhere under the home"
}

# bats test_tags=feature:install
@test "assistant: the whole scenario ran to its end with no failed check" {
  ran_clean
}
