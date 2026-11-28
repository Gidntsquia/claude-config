#!/usr/bin/env bats
# The records a new session reads (ARCHITECTURE.md, .claude/CLAUDE.md, the README status line) and the checks
# test/run holds them to. The runner cases use a copy of test/run in a scratch repo, as test-run.bats does.

# bats file_tags=feature:test-runner

load ../helpers/common

setup() {
  temp_home
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/test/quick" "$R/test/helpers" "$R/.claude" "$R/test/results"
  UNDER="${TEST_RUNNER_UNDER_TEST:-$REPO/test}"
  cp "$UNDER/run" "$R/test/run"
  cp -R "$UNDER/lib" "$R/test/lib"
  mkdir -p "$R/bin/release"
  cp "$UNDER/../bin/release/trust-report" "$R/bin/release/"
  printf '# bats file_%s=feature:x\n@%s "case" {\n  true\n}\n' tags test >"$R/test/quick/a.bats"
  echo "x | the scratch feature" >"$R/test/features.txt"
  arch "One part lives in \`test/\`."
  echo "scratch" >"$R/.claude/CLAUDE.md"
}

# arch <body line> [<decision lines> [<next lines>]]
arch() {
  local i
  {
    printf '# Architecture\n\n%s\n\n## Decisions\n\n' "$1"
    i=0; while [ "$i" -lt "${2:-1}" ]; do i=$((i + 1)); echo "- decision $i"; done
    printf '\n## Next\n\n'
    i=0; while [ "$i" -lt "${3:-1}" ]; do i=$((i + 1)); echo "- next $i"; done
  } >"$R/ARCHITECTURE.md"
}

suite() {
  local bats
  bats="$REPO/test/vendor/bats-core/bin/bats"
  [ -f "$bats" ] || bats="$(PATH="${PATH#"$BATS_LIBEXEC:"}" command -v bats)"
  run env -i PATH="$(dirname "$bats"):/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$BATS_TEST_TMPDIR" HOME="$TEST_HOME" bash "$R/${TOOL:-test/run}" "$@"
}

last_line() { printf '%s\n' "$output" | tail -n 1; }

@test "test/run: pages that match the tree and sit at their caps pass" {
  arch "Tests in \`test/quick/\`, [the list](test/features.txt), \`test/quick/*.bats\`, \`~/.claude/x\`, \`test/run <tier>\`, any \`.md\` file." 20 10
  i=0; : >"$R/.claude/CLAUDE.md"; while [ "$i" -lt 60 ]; do i=$((i + 1)); echo "line $i" >>"$R/.claude/CLAUDE.md"; done
  suite
  assert_success
  assert_line "records: pages and tree agree"
  assert_equal "$(last_line)" "PASS 1 tests"
}

@test "test/run: ARCHITECTURE.md naming a missing path fails the run and names the line" {
  arch "The tool is in \`bin/gone.sh\`; see [notes](docs/none.md)."
  suite
  assert_failure 1
  assert_line "records: ARCHITECTURE.md:3: names bin/gone.sh, which does not exist"
  assert_line "records: ARCHITECTURE.md:3: names docs/none.md, which does not exist"
}

@test "test/run: a Decisions section over 20 lines or a Next section over 10 fails the run" {
  arch "x" 21 11
  suite
  assert_failure 1
  assert_a_line_matches '## Decisions has 21 lines, at most 20'
  assert_a_line_matches '## Next has 11 lines, at most 10'
}

@test "test/run: a missing section, a missing page and a long project CLAUDE.md each fail the run" {
  printf '## Next\n' >"$R/ARCHITECTURE.md"
  i=0; : >"$R/.claude/CLAUDE.md"; while [ "$i" -lt 61 ]; do i=$((i + 1)); echo "line $i" >>"$R/.claude/CLAUDE.md"; done
  suite
  assert_failure 1
  assert_line "records: ARCHITECTURE.md has no ## Decisions section"
  assert_line "records: .claude/CLAUDE.md has 61 lines, at most 60"
  rm "$R/ARCHITECTURE.md" "$R/.claude/CLAUDE.md"
  suite
  assert_failure 1
  assert_line "records: ARCHITECTURE.md is missing"
  assert_line "records: .claude/CLAUDE.md is missing"
}

@test "test/run: a project CLAUDE.md importing a file that is not there fails the run" {
  echo "@../AGENTS.md" >"$R/.claude/CLAUDE.md"
  suite
  assert_failure 1
  assert_line "records: .claude/CLAUDE.md:1: names ../AGENTS.md, which does not exist"
}

# status <system> <date|version|failed|total|skipped>: a recorded full run
status() { echo "$2|by hand" >"$R/test/results/full-$1.txt"; }
status_line_of() {
  run bash -c 'RESULTS="$1/test/results"; . "$1/test/lib/status.bash"; status_line' _ "$R"
}

@test "README status line: three systems passing the same tests read as one result" {
  status macos "2026-01-02|27.0|0|9|0"
  status ubuntu "2026-01-02|24.04|0|9|0"
  status windows "2026-01-02||0|9|0"
  status_line_of
  assert_output "Last full run: 2026-01-02, macOS 27.0 / Ubuntu 24.04 / Windows: all 9 tests passed"
}

@test "README status line: a system not run, failing, skipping or older says so" {
  status macos "2026-01-02|27.0|0|9|3"
  status ubuntu "2026-01-01|24.04|2|9|0"
  status_line_of
  assert_output "Last full run: 2026-01-02, macOS 27.0: all 9 tests passed (3 skipped); Ubuntu 24.04: 2 of 9 tests failed on 2026-01-01; Windows: not run"
}

@test "bin/release/trust-report all: runs every tier, records this system's result and rewrites the README status line" {
  case "$(uname -s)" in Darwin|MINGW*|MSYS*) ;; Linux) grep -qx 'ID=ubuntu' /etc/os-release || skip "status line names Ubuntu only" ;; esac
  printf '<!-- trust-report:start -->\n<!-- trust-report:end -->\n' >"$R/TESTING.md"
  printf '# title\n\n[Last full run: never](TESTING.md)\n\nrest\n' >"$R/README.md"
  TOOL=bin/release/trust-report suite all
  assert_success
  assert_line "PASS 1 tests"
  run cat "$R/README.md"
  assert_a_line_matches '^\[Last full run: 20[0-9-]+, .*all 1 tests passed.*\]\(TESTING\.md\)$'
  assert_line "rest"
  refute_output --partial "never"
  assert_a_line_matches '^# title$'
}

@test "bin/release/trust-report: any argument but all is refused" {
  TOOL=bin/release/trust-report suite quick
  assert_failure 2
  assert_output "usage: bin/release/trust-report [all]"
}

@test "test/run: a TESTING.md over 80 lines fails the run; 80 passes" {
  i=0; : >"$R/TESTING.md"; while [ "$i" -lt 80 ]; do i=$((i + 1)); echo "line $i" >>"$R/TESTING.md"; done
  suite
  assert_success
  echo "one more" >>"$R/TESTING.md"
  suite
  assert_failure 1
  assert_line "records: TESTING.md has 81 lines, at most 80: it is the one page about the tests"
  assert_line "FAILED records: TESTING.md has 81 lines, at most 80: it is the one page about the tests"
}

@test "TESTING.md: the tables follow the title, then four sections, each a command and at most one sentence" {
  run python3 - "$REPO/TESTING.md" <<'EOF'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
assert lines[0] == "# Testing" and lines[1] == "<!-- trust-report:start -->", lines[:2]
end = lines.index("<!-- trust-report:end -->")
assert not [l for l in lines[:end] if l.startswith("## ")], "a heading before the tables"
rest = "\n".join(lines[end + 1:])
parts = re.split(r"(?m)^## (.*)$", rest)
names = parts[1::2]
assert names == ["Run the tests", "Read a failure", "Add a test", "What a pass means"], names
for name, body in zip(names, parts[2::2]):
    assert body.count("```") == 2, name + ": one code block"
    prose = re.sub(r"(?s)```.*?```", "", body)
    ends = len(re.findall(r"[.?!:](?=\s|$)", prose.strip()))
    assert ends <= 1, "%s: %d sentences" % (name, ends)
    assert prose.strip(), name + ": no sentence"
print("shape ok")
EOF
  assert_output "shape ok"
}

@test "the project CLAUDE.md points a session at the records and the one test command" {
  run cat "$REPO/.claude/CLAUDE.md"
  for want in "test/run" "ARCHITECTURE.md" "test/features.txt" "TESTING.md" "agents/USAGE.txt" "planner" "worker" "evaluator"; do
    assert_output --partial "$want"
  done
  assert_line "@../AGENTS.md"
}

@test "the README's status line links to TESTING.md" {
  run grep -c '^\[Last full run: .*\](TESTING\.md)$' "$REPO/README.md"
  assert_output "1"
}

@test "ARCHITECTURE.md: every part says its folder and where new work goes" {
  run awk -F'|' '/^\|/ && !/^\|[-| ]*$/ { n++; for (i = 2; i <= 4; i++) if (!match($i, /[^ \t\r]/)) print "empty cell:" $0 }
    END { print n " rows" }' "$REPO/ARCHITECTURE.md"
  assert_a_line_matches '^[1-9][0-9]+ rows$'
  refute_output --partial "empty cell"
}

@test "ARCHITECTURE.md: every folder in the repo is on the page" {
  local d folders missing=""
  folders="$(git -C "$REPO" ls-files | sed -n 's|/.*||p' | sort -u)"
  [ -n "$folders" ]
  for d in $folders; do
    grep -qF "\`$d/" "$REPO/ARCHITECTURE.md" || missing="$missing $d"
  done
  assert_equal "$missing" ""
}
