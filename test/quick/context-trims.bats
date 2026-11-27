#!/usr/bin/env bats
# The context trims (skill overrides, denied tools and servers, switched-off features) through bin/merge-settings.py,
# the merge an install runs, on made-up repo and user files.

load ../helpers/common

FX="$REPO/test/fixtures/context-trims"

setup() {
  temp_home
  OUT="$BATS_TEST_TMPDIR/out.json"
}

# merge <user file> : merge the fixture repo file into it, writing $OUT
merge() { python3 "$REPO/bin/merge-settings.py" "$FX/repo.json" "$1" "$OUT"; }

# value <python expression over m> : print it as JSON for the merged file
value() { python3 -c 'import json,sys; m=json.load(open(sys.argv[1], encoding="utf-8")); print(json.dumps(eval(sys.argv[2]), sort_keys=True))' "$OUT" "$1" | tr -d '\r'; }

# bats test_tags=feature:context-trims
@test "a new user gets every trim exactly as the repo has it" {
  run merge "$BATS_TEST_TMPDIR/absent.json"
  assert_success
  assert_output --partial "settings merge: kept 0 of your keys, added 7"
  run python3 -c 'import json,sys; a,b=(json.load(open(p, encoding="utf-8")) for p in sys.argv[1:]); sys.stdout.write(str(a == b))' "$OUT" "$FX/repo.json"
  assert_output "True"
}

# bats test_tags=feature:context-trims
@test "a user's own skill overrides win and the repo's others are added" {
  run merge "$FX/user.json"
  assert_success
  run value 'm["skillOverrides"]'
  assert_output '{"alpha": "user-invocable-only", "beta": "on", "delta": "on", "gamma": "name-only", "mine": "off"}'
}

# bats test_tags=feature:context-trims
@test "denied tools and denied servers are added beside the user's own, without doubles" {
  run merge "$FX/user.json"
  assert_success
  run value 'm["permissions"]["deny"]'
  assert_output '["Bash(rm:*)", "Workflow", "ReportFindings", "Agent(statusline-setup)"]'
  run value 'm["deniedMcpServers"]'
  assert_output '[{"serverName": "user-denied"}, {"serverName": "repo-denied"}]'
}

# bats test_tags=feature:context-trims
@test "features the user switched on stay on and untouched ones are switched off" {
  run merge "$FX/user.json"
  assert_success
  run value '[m["enableWorkflows"], m["workflowKeywordTriggerEnabled"], m["enabledPlugins"], m["env"]]'
  assert_output '[true, false, {"kept@market": true, "trimmed@market": true}, {"ENABLE_CLAUDEAI_MCP_SERVERS": "false", "MINE": "1"}]'
}

# bats test_tags=feature:context-trims
@test "installing again keeps the trims unchanged" {
  run merge "$FX/user.json"
  assert_success
  cp "$OUT" "$BATS_TEST_TMPDIR/first.json"
  run merge "$BATS_TEST_TMPDIR/first.json"
  assert_success
  run cmp "$OUT" "$BATS_TEST_TMPDIR/first.json"
  assert_success
}
