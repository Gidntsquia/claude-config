#!/usr/bin/env bats
# mods/defer-artifact: its hooks module, loaded through hooks.json by a stand-in host under node.

load ../helpers/common

MOD="$REPO/mods/defer-artifact"

setup() { temp_home; }

# describe <JSON list of cases> : run them through the mod; leaves the host's JSON answer in $output
describe() {
  command -v node >/dev/null 2>&1 || skip "node missing"
  run node "$REPO/test/fixtures/defer-artifact/host.mjs" "$MOD" "$1"
}

# bats test_tags=feature:defer-artifact
@test "the Artifact tool is described as deferred and keeps the rest of its description" {
  describe '[{"tool":"Artifact","description":"Publish a page"}]'
  assert_success
  assert_output --partial '"results":[{"description":"Publish a page","inputSchema":{"type":"object"},"isDeferred":true}]'
}

# bats test_tags=feature:defer-artifact
@test "other tools are left as they were" {
  describe '[{"tool":"Bash","description":"Run a command"},{"tool":"Read","description":"Read a file"}]'
  assert_success
  assert_output --partial '"results":[{"description":"Run a command","inputSchema":{"type":"object"}},{"description":"Read a file","inputSchema":{"type":"object"}}]'
}

# bats test_tags=feature:defer-artifact
@test "the mod hooks only the description of the Artifact tool" {
  describe '[]'
  assert_success
  assert_output '{"registered":[["tool.describe",{"tool":"Artifact"}]],"results":[]}'
}

# bats test_tags=feature:defer-artifact
@test "if describing Artifact fails once, the mod falls back to the normal description" {
  describe '[{"tool":"Artifact","description":"Publish a page","failFirst":true}]'
  assert_success
  assert_output --partial '"results":[{"description":"Publish a page","inputSchema":{"type":"object"}}]'
}

# bats test_tags=feature:defer-artifact
@test "the mod has the manifest the installer looks for" {
  run python3 -c 'import json,sys; sys.stdout.reconfigure(newline="\n"); m=json.load(open(sys.argv[1], encoding="utf-8")); sys.stdout.write(m["name"] + "\n" + m["version"])' "$MOD/.claude-plugin/plugin.json"
  assert_success
  assert_output --regexp '^defer-artifact
[0-9]+\.[0-9]+\.[0-9]+$'
}
