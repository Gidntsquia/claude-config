#!/usr/bin/env bats
# The helper agent's read-only wiki server (helper-mcp/server.py), run from a scratch clone layout.
# The `mcp` package is the stand-in in test/fixtures/mcp-stub; test/machine/mcp-servers.bats uses the real one.

load ../helpers/common

setup() {
  temp_home
  C="$BATS_TEST_TMPDIR/clone"
  mkdir -p "$C/helper-mcp" "$C/wiki" "$C/agents"
  cp "$REPO/helper-mcp/server.py" "$C/helper-mcp/"
  for a in planner worker evaluator; do echo "I am the $a" > "$C/agents/$a.md"; done
  echo "usage text" > "$C/agents/USAGE.txt"
  printf '# Start\nInstall with ./install.sh\n' > "$C/wiki/Getting-Started.md"
  printf '# Workflow\nThe planner writes the plan.\n' > "$C/wiki/Workflow.md"
}

# call <python expression using the server module as s>
call() {
  run env PYTHONPATH="$REPO/test/fixtures/mcp-stub" PYTHONDONTWRITEBYTECODE=1 python3 -c '
import importlib.util, sys
sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # Windows Python prints CRLF otherwise
spec = importlib.util.spec_from_file_location("helper_server", sys.argv[1])
s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
print(eval(sys.argv[2]))' "$C/helper-mcp/server.py" "$1"
}

stamp() {
  call '",".join(n + "=" + i["hash"] for n, i in s.agent_hashes().items())'
  printf '<!-- Last synced: 2026-11-01 | %s -->\n' "$output" >> "$C/wiki/Workflow.md"
}

# bats test_tags=feature:helper
@test "helper server: it offers exactly the five read-only wiki tools" {
  call '" ".join(sorted(s.mcp.tools))'
  assert_success
  assert_output "agent_read wiki_list wiki_read wiki_search workflow_status"
}

# bats test_tags=feature:helper
@test "helper server: wiki_list names the pages and wiki_read gives one by title, with spaces or dashes" {
  call 's.wiki_list()'
  assert_output "$(printf 'Getting-Started\nWorkflow')"
  call 's.wiki_read("Getting Started")'
  assert_output "$(printf '# file: wiki/Getting-Started.md\n# Start\nInstall with ./install.sh')"
}

# bats test_tags=feature:helper
@test "helper server: asking for a page that does not exist names the pages that do" {
  call 's.wiki_read("Nope")'
  assert_failure
  assert_output --partial "No wiki page 'Nope'. Pages: Getting-Started, Workflow"
}

# bats test_tags=feature:helper
@test "helper server: wiki_search finds a line whatever its case and says so when nothing matches" {
  call 's.wiki_search("INSTALL.SH")'
  assert_output "Getting-Started:2: Install with ./install.sh"
  call 's.wiki_search("zebra")'
  assert_output "No lines match 'zebra' in the wiki."
}

# bats test_tags=feature:helper
@test "helper server: agent_read gives the agent files and refuses any other name" {
  call 's.agent_read("Worker")'
  assert_output "$(printf '# file: agents/worker.md\nI am the worker')"
  call 's.agent_read("usage.txt")'
  assert_output --partial "usage text"
  call 's.agent_read("researcher")'
  assert_failure
  assert_output --partial "Unknown agent 'researcher'. Choose from: planner, worker, evaluator, USAGE"
}

# bats test_tags=feature:helper
@test "helper server: a wiki stamped with today's agent files is reported in step" {
  stamp
  call '(s.status()["stale"], s.status()["summary"])'
  assert_output "(False, 'Wiki is in step with the agent files.')"
}

# bats test_tags=feature:helper
@test "helper server: an agent file changed after the stamp is named as ahead of the guide" {
  stamp
  echo "new rule" >> "$C/agents/worker.md"
  call 's.status()["differing"]'
  assert_output "['worker']"
  call 's.status()["summary"]'
  assert_output --partial "Guide may be behind the agents: worker changed"
  assert_output --partial "guide stamped 2026-11-01"
}

# bats test_tags=feature:helper
@test "helper server: an agent file edited but not committed is said to have uncommitted edits" {
  git -C "$C" init -q
  git -C "$C" add .
  git -C "$C" -c user.name=t -c user.email=t@example.com commit -q -m start
  stamp
  echo "new rule" >> "$C/agents/worker.md"
  call 's.status()["summary"]'
  assert_success
  assert_output --regexp 'worker changed [0-9-]+ \(uncommitted edits\)'
}

# bats test_tags=feature:helper
@test "helper server: an agent file the stamp does not list is named as ahead of the guide" {
  call 's.agent_hashes()["planner"]["hash"]'
  printf '<!-- Last synced: 2026-11-01 | planner=%s -->\n' "$output" >> "$C/wiki/Workflow.md"
  call '(s.status()["stale"], sorted(s.status()["differing"]))'
  assert_output "(True, ['USAGE', 'evaluator', 'worker'])"
}

# bats test_tags=feature:helper
@test "helper server: a wiki with no stamp counts every agent as ahead of it" {
  call '(s.status()["stale"], len(s.status()["differing"]), s.status()["wiki_stamp"])'
  assert_output "(True, 4, None)"
}

# bats test_tags=feature:helper
@test "helper server: workflow_status answers as JSON that names the changed files" {
  stamp
  echo "new rule" >> "$C/agents/worker.md"
  call 's.workflow_status()'
  assert_success
  run python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["stale"], d["differing"])' "$output"
  assert_output "True ['worker']"
}

# bats test_tags=feature:helper
@test "stamp-wiki writes a stamp the server reads as in step, and replaces an old one" {
  cp "$REPO/helper-mcp/stamp-wiki" "$C/helper-mcp/"
  run bash "$C/helper-mcp/stamp-wiki"
  assert_success
  call '(s.status()["stale"], s.status()["differing"])'
  assert_output "(False, [])"
  echo "new rule" >> "$C/agents/worker.md"
  run bash "$C/helper-mcp/stamp-wiki"
  assert_success
  call '(s.status()["stale"], s.status()["differing"])'
  assert_output "(False, [])"
  assert_equal "$(grep -c '^<!-- Last synced:' "$C/wiki/Workflow.md" | tr -d ' ')" "1"
  run grep -x 'The planner writes the plan.' "$C/wiki/Workflow.md"
  assert_success
}
