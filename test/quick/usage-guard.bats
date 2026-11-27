#!/usr/bin/env bats
# The usage guard: its own suite from one wrapper (that file is run as it is), the same rules asked on every OS
# the way Claude Code asks them, and every hook in settings.json with the script it calls missing.

load ../helpers/common

setup() {
  temp_home
  P="$BATS_TEST_TMPDIR/project"
  mkdir -p "$P/.git" "$TEST_HOME/bin"
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SUBAGENT_MODEL
}

on_windows() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac; return 1; }

# ask <agent type or -> <shell command>: one PreToolUse Bash hook call
ask() {
  python3 -c '
import json, sys
agent, cwd, cmd = sys.argv[1:]
d = {"hook_event_name": "PreToolUse", "session_id": "s1", "cwd": cwd, "tool_name": "Bash",
     "tool_input": {"command": cmd}, "tool_use_id": "toolu_1"}
if agent != "-":
    d["agent_type"] = agent
print(json.dumps(d))' "$1" "$P" "$2" > "$BATS_TEST_TMPDIR/hook.json"
  run bash -c 'python3 "$1" < "$2"' _ "$REPO/hooks/usage-guard/usage_guard.py" "$BATS_TEST_TMPDIR/hook.json"
}

# bats test_tags=feature:usage-guard
@test "usage-guard: its own suite passes" {
  [ "$(uname -s)" = Linux ] || skip "hooks/usage-guard/test.sh needs bash 4 and GNU date: it runs on Linux"
  # The account's own home, as in a terminal: under any other HOME five of its "refuses inside a Claude session"
  # cases fail. The suite makes its own scratch folders.
  run env -i PATH="$PATH" HOME="$REAL_HOME" LANG=C.UTF-8 bash "$REPO/hooks/usage-guard/test.sh"
  assert_success
  assert_a_line_matches '^[0-9]+ passed, 0 failed$'
}

# bats test_tags=feature:usage-guard
@test "usage-guard: a worker's headless launch with no budget flags is blocked and says which to add" {
  on_windows && skip "the guard is not run on Windows Git Bash"
  ask worker "claude -p 'say hi'"
  assert_failure 2
  assert_output --partial "blocked by usage-guard: headless claude launch lacks"
  assert_output --partial "--max-turns"
}

# bats test_tags=feature:usage-guard
@test "usage-guard: a worker's launch with both flags is allowed and told the day's count" {
  on_windows && skip "the guard is not run on Windows Git Bash"
  ask worker "claude -p 'say hi' --max-budget-usd 0.50 --max-turns 5"
  assert_success
  assert_output --partial "1/30 used today, 29 left"
}

# bats test_tags=feature:usage-guard
@test "usage-guard: a command that only mentions claude -p is not a launch" {
  on_windows && skip "the guard is not run on Windows Git Bash"
  ask worker "grep -rn 'claude -p' ."
  assert_success
  assert_output ""
}

# bats test_tags=feature:usage-guard
@test "usage-guard: your own sessions and other agents are left alone" {
  on_windows && skip "the guard is not run on Windows Git Bash"
  for who in - planner evaluator; do
    ask "$who" "claude -p 'say hi'"
    assert_success
    assert_output ""
  done
}

# hooks: one line per hook in settings.json, `<event><TAB><command>`
hooks() {
  python3 -c '
import json, sys
for event, groups in json.load(open(sys.argv[1]))["hooks"].items():
    for g in groups:
        for h in g["hooks"]:
            print(event + "\t" + h["command"].replace("\n", " "))' "$REPO/settings.json"
}

# with_nothing_installed <event>: run that event's commands in a home that holds none of the scripts
with_nothing_installed() {
  local event cmd n=0
  while IFS="$(printf '\t')" read -r event cmd; do
    [ "$event" = "$1" ] || continue
    n=$((n + 1))
    printf '{"session_id":"gone-%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "$n" |
      env HOME="$TEST_HOME" TMPDIR="$BATS_TEST_TMPDIR" /bin/sh -c "$cmd" >> "$BATS_TEST_TMPDIR/said" || return 1
  done <<EOF
$(hooks)
EOF
  [ "$n" -gt 0 ]
}

# bats test_tags=feature:usage-guard
@test "hooks: settings.json hooks only the events the tests below cover" {
  assert_equal "$(hooks | cut -f1 | sort | uniq -c | awk '{print $2 "=" $1}' | tr '\n' ' ')" \
    "PostToolUse=1 PreToolUse=3 SessionStart=1 SubagentStart=1 SubagentStop=1 UserPromptExpansion=1 "
}

# bats test_tags=feature:usage-guard
@test "hooks: UserPromptExpansion with the run-agent script missing exits 0 and says nothing" {
  with_nothing_installed UserPromptExpansion
  assert_equal "$(cat "$BATS_TEST_TMPDIR/said")" ""
}

# bats test_tags=feature:usage-guard
@test "hooks: PreToolUse with the guard missing blocks nothing and says once per session that it is off" {
  with_nothing_installed PreToolUse
  with_nothing_installed PreToolUse
  assert_equal "$(grep -o 'guard is off' "$BATS_TEST_TMPDIR/said" | wc -l | tr -d ' ')" 3
}

# bats test_tags=feature:usage-guard
@test "hooks: PostToolUse with the guard missing exits 0 and says it is off" {
  with_nothing_installed PostToolUse
  grep -q 'guard is off' "$BATS_TEST_TMPDIR/said"
}

# bats test_tags=feature:usage-guard
@test "hooks: SessionStart with the guard missing exits 0 and says it is off" {
  with_nothing_installed SessionStart
  grep -q 'guard is off' "$BATS_TEST_TMPDIR/said"
}

# bats test_tags=feature:usage-guard
@test "hooks: SubagentStart with the guard missing exits 0 and says it is off" {
  with_nothing_installed SubagentStart
  grep -q 'guard is off' "$BATS_TEST_TMPDIR/said"
}

# bats test_tags=feature:usage-guard
@test "hooks: SubagentStop with the guard missing exits 0 and says it is off" {
  with_nothing_installed SubagentStop
  grep -q 'guard is off' "$BATS_TEST_TMPDIR/said"
}
