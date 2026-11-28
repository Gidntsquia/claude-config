#!/usr/bin/env bats
# The agent files: their frontmatter, and the repo files, scripts, tools and agents they send a session to.

load ../helpers/common

AGENTS="planner worker evaluator researcher report-checker report-writer helper"

setup() {
  temp_home
  MD=()
  local a
  for a in $AGENTS; do MD+=("$REPO/agents/$a.md"); done
}

# field <file> <key>: the value of a one-line key in the frontmatter that opens the file.
field() {
  awk -v k="$2" 'NR==1 { if ($0 != "---") exit; next } /^---$/ { exit }
    index($0, k ": ") == 1 { print substr($0, length(k) + 3) }' "$1"
}

# in_tools <script>: it ships to macOS and to WSL (common/, or one copy in each system's folder), executable.
in_tools() {
  local t="$REPO/local-tools"
  if [ -e "$t/common/$1" ]; then
    test -x "$t/common/$1" || { echo "not executable: local-tools/common/$1"; return 1; }
    return 0
  fi
  test -x "$t/macos/$1" || { echo "missing or not executable: local-tools/macos/$1"; return 1; }
  test -x "$t/wsl/$1" || { echo "missing or not executable: local-tools/wsl/$1"; return 1; }
}

# verbs <script>: every command word the agent files put after that script's name.
verbs() {
  grep -ohE "${1%.sh}\.sh [a-z][a-z|-]*" "${MD[@]}" | awk '{ print $2 }' | tr '|' '\n' | sort -u
}

# labels <shell file>: the words its case statements dispatch on.
labels() {
  sed -nE 's/^ *([a-z][a-z|-]*)\).*/\1/p' "$1" | tr '|' '\n' | sort -u
}

# bats test_tags=feature:agent-prompts
@test "each agent's frontmatter carries the file's name and a description" {
  local a f desc
  for a in $AGENTS; do
    f="$REPO/agents/$a.md"
    assert_file_exist "$f"
    assert_equal "$(head -n 1 "$f")" "---"
    assert_equal "$(field "$f" name)" "$a"
    desc="$(field "$f" description)"
    echo "$a: $desc"
    test "${#desc}" -gt 40
    # install.sh picks an agent up by a name: line among the first five
    head -n 5 "$f" | grep -qx "name: $a"
  done
}

# bats test_tags=feature:agent-prompts
@test "every file an agent reads from the claude-config folder is in the repo" {
  local p n=0
  # claude-config.json is written by the installer; wiki/ is a separate clone
  for p in $(grep -ohE '\$(CFG|REPO)/[A-Za-z0-9_./-]+' "${MD[@]}" | sed -E 's/^\$(CFG|REPO)\///; s/[.]+$//' |
    grep -vE '^(claude-config\.json$|wiki/)' | sort -u); do
    [ -e "$REPO/$p" ]
    n=$((n + 1))
  done
  test "$n" -ge 7
}

# bats test_tags=feature:agent-prompts
@test "every repo file an agent names by a relative path is there" {
  local p n=0
  for p in $(grep -ohE '`(docs|skills|agents|local-tools|helper-mcp)/[A-Za-z0-9_./-]+\.(md|sh|py|mjs|json|jsonl)' "${MD[@]}" |
    tr -d '`' | sort -u); do
    [ -e "$REPO/$p" ]
    n=$((n + 1))
  done
  test "$n" -ge 2
}

# bats test_tags=feature:agent-prompts
@test "every installed script an agent runs comes from the repo" {
  local p n=0 tilde
  tilde="$(printf '\176')"
  for p in $(grep -ohE "$tilde/\.claude/(local-tools|skills)/[A-Za-z0-9_./-]+\.(sh|py|mjs)" "${MD[@]}" |
    sed 's/^.*\.claude\///' | sort -u); do
    echo "$p"
    case "$p" in
      local-tools/*) in_tools "${p#local-tools/}" ;;
      *) test -x "$REPO/$p" ;;
    esac
    n=$((n + 1))
  done
  test "$n" -ge 4
}

# bats test_tags=feature:agent-prompts
@test "every shell script an agent names ships for both macOS and WSL" {
  local s n=0
  for s in $(grep -ohE '[A-Za-z0-9_-]+\.sh' "${MD[@]}" | sort -u); do
    echo "$s"
    if [ -e "$REPO/skills/run-agent/scripts/$s" ]; then
      test -x "$REPO/skills/run-agent/scripts/$s"
    else
      in_tools "$s"
    fi
    n=$((n + 1))
  done
  test "$n" -ge 8
}

# bats test_tags=feature:agent-prompts
@test "every window command an agent calls is one the macOS window script handles" {
  local v have n=0
  have="$(labels "$REPO/local-tools/macos/win.sh")"
  for v in $(verbs win.sh); do
    echo "win.sh $v"
    printf '%s\n' "$have" | grep -qx -- "$v"
    n=$((n + 1))
  done
  test "$n" -ge 8
}

# bats test_tags=feature:agent-prompts
@test "the window commands an agent calls are handled on WSL" {
  local v n=0
  # geom is left out: only the macOS script has it (reported as a product bug)
  for v in $(verbs win.sh | grep -vx geom); do
    echo "win.sh $v"
    if [ "$v" = me ]; then
      grep -qF '[ "${1:-}" = me ]' "$REPO/local-tools/wsl/win.sh"
    else
      grep -qE "^ *'$v' *\{" "$REPO/local-tools/wsl/winctl.ps1"
    fi
    n=$((n + 1))
  done
  test "$n" -ge 8
}

# bats test_tags=feature:agent-prompts
@test "every show command the evaluator calls is one evshow.sh handles" {
  local v have n=0
  have="$(labels "$REPO/local-tools/common/evshow.sh")"
  for v in $(verbs evshow.sh); do
    echo "evshow.sh $v"
    printf '%s\n' "$have" | grep -qx -- "$v"
    n=$((n + 1))
  done
  test "$n" -ge 6
}

# bats test_tags=feature:agent-prompts
@test "every run-agent option an agent uses is one the script dispatches" {
  local o have n=0
  have="$(sed -n '/^case "\${1:-}" in$/,/^esac$/p' "$REPO/skills/run-agent/scripts/run-agent.sh" |
    sed -nE 's/^ *(--[a-z|-]+)[|)].*/\1/p' | tr '|' '\n')"
  for o in $(grep -ohE 'run-agent\.sh --[a-z-]+' "${MD[@]}" | awk '{ print $2 }' | sort -u); do
    echo "run-agent.sh $o"
    printf '%s\n' "$have" | grep -qx -- "$o"
    n=$((n + 1))
  done
  test "$n" -ge 2
}

# bats test_tags=feature:agent-prompts
@test "every MCP tool an agent names is one its server offers" {
  local ref server tool file n=0
  for ref in $(grep -ohE 'mcp__(run-agent|helper-wiki)__[a-z_]+' "${MD[@]}" | sort -u); do
    server="${ref#mcp__}"
    server="${server%%__*}"
    tool="${ref##*__}"
    case "$server" in
      run-agent) file="$REPO/skills/run-agent/mcp/server.py" ;;
      *) file="$REPO/helper-mcp/server.py" ;;
    esac
    run python3 -I "$REPO/test/fixtures/agent-prompts/mcp_tools.py" "$file"
    assert_success
    echo "$ref"
    printf '%s\n' "$output" | grep -qx -- "$tool"
    n=$((n + 1))
  done
  test "$n" -ge 6
}

# bats test_tags=feature:agent-prompts
@test "the helper's wiki server path leads from its own file to the server" {
  local rel
  rel="$(grep -oE '/\.\./[A-Za-z0-9_./-]+server\.py' "$REPO/agents/helper.md")"
  assert_equal "$rel" "/../helper-mcp/server.py"
  [ -e "$REPO/agents$rel" ]
}

# bats test_tags=feature:agent-prompts
@test "every agent that another agent starts exists" {
  local a n=0
  for a in $( {
    grep -ohE -- '--agent [a-z][a-z-]+' "${MD[@]}" | awk '{ print $2 }'
    sed -n 's/^tools:.*Agent(\([^)]*\)).*/\1/p' "${MD[@]}" | tr -d ' ' | tr ',' '\n'
  } | sort -u); do
    echo "$a"
    assert_equal "$(field "$REPO/agents/$a.md" name)" "$a"
    n=$((n + 1))
  done
  test "$n" -ge 5
  grep -qF '`researcher` subagent' "$REPO/agents/planner.md"
  grep -qF '`subagent_type` `report-checker`' "$REPO/agents/report-writer.md"
  assert_equal "$(field "$REPO/agents/researcher.md" name)" "researcher"
  assert_equal "$(field "$REPO/agents/report-checker.md" name)" "report-checker"
}

# bats test_tags=feature:agent-prompts
@test "the planner can start the researcher it is told to use" {
  local f="$REPO/agents/planner.md"
  grep -q '`researcher` subagent' "$f"
  field "$f" tools | tr -d ' ' | tr ',' '\n' | grep -qE '^Agent(\(.*researcher.*\))?$'
}
