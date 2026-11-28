#!/usr/bin/env bats
# The helper and assistant MCP servers with the real `mcp` package, spoken to over stdio as Claude Code does.
# The quick tier imports them with the stand-in in test/fixtures/mcp-stub.

load ../helpers/common

setup() {
  command -v uv >/dev/null 2>&1 || skip "uv missing"
  CACHE="$(uv cache dir)"
  temp_home
  export UV_CACHE_DIR="$CACHE" PYTHONDONTWRITEBYTECODE=1
  mkdir -p "$TEST_HOME/.claude/skills"
  ln -s "$REPO/skills/run-agent" "$TEST_HOME/.claude/skills/run-agent"
}

# tools <server.py>: print the names tools/list answers with
tools() {
  run python3 "$REPO/test/fixtures/mcp-list-tools.py" uv run --script --quiet "$1"
}

# bats test_tags=feature:helper,standin:mcp
@test "the real helper server starts and lists its five tools" {
  tools "$REPO/helper-mcp/server.py"
  assert_success
  assert_line "agent_read wiki_list wiki_read wiki_search workflow_status"
}

# bats test_tags=feature:assistant,standin:mcp
@test "the real assistant server starts and lists its seven tools" {
  tools "$REPO/assistant/mcp/server.py"
  assert_success
  assert_line "assistant_jobs assistant_launch assistant_layout assistant_panes assistant_projects assistant_schedule assistant_send"
}
