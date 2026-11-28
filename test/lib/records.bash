# The records (sourced by test/run): the pages a new session reads to learn what exists and where work goes.
#   records        ARCHITECTURE.md and .claude/CLAUDE.md exist, stay under their caps and name only real paths
#                  and TESTING.md stays one page (the README status line: bin/release/trust-report)

ARCH_DECISIONS_CAP=20
ARCH_NEXT_CAP=10
PROJECT_MEMORY_CAP=60
TESTING_CAP=80

# named_paths <markdown file>: `<line> <path>` for each path the page names, in backticks, as a link target or as
# an `@` import. A backticked word is a path when it holds a / or ends in a file suffix; commands (spaces),
# placeholders (<id>) and paths outside the repo (~, /, $) are not.
named_paths() {
  awk '
    function path(s) {
      if (s ~ /[ <>$()|=:]/ || s ~ /^[~\/-]/) return
      if (s ~ /^\.[a-z]+$/) return   # a bare suffix (`.md`)
      if (s ~ /\// || s ~ /\.(md|sh|py|json|txt|bats|bash|mjs|toml|yml)$/) print NR " " s
    }
    { sub(/\r$/, "") }
    /^@/ { print NR " " substr($0, 2); next }
    {
      n = split($0, part, "`")
      for (i = 2; i <= n; i += 2) path(part[i])
      rest = $0
      while (match(rest, /\]\([^)]*\)/)) {
        t = substr(rest, RSTART + 2, RLENGTH - 3); rest = substr(rest, RSTART + RLENGTH)
        sub(/#.*/, "", t)
        if (t != "" && t !~ /^[a-z]+:/) print NR " " t
      }
    }' "$1"
}

# missing_paths <page> <folder its relative paths start in> [<second folder>]
missing_paths() {
  local page="$1" line p base found
  while read -r line p; do
    found=""
    for base in "$2" ${3:+"$3"}; do
      # a pattern (skills/*/tests) must match something
      if compgen -G "$base/$p" >/dev/null 2>&1; then found=1; break; fi
    done
    # a gitignored path (plans/, wiki/) is made on the machine and is absent from a fresh clone
    [ -n "$found" ] || git -C "$REPO" check-ignore -q "$p" 2>/dev/null || echo "records: ${page#$REPO/}:$line: names $p, which does not exist"
  done < <(named_paths "$page")
}

# section_lines <file> <heading>: the non-blank lines under `## <heading>`; nothing printed when it is absent
section_lines() {
  awk -v want="## $2" '
    { sub(/\r$/, "") }
    /^##? / { if (on) on = 0; if ($0 == want) { on = 1; seen = 1 } ; next }
    on && !/^[ \t]*$/ { n++ }
    END { if (seen) print n + 0 }' "$1"
}

record_problems() {
  local arch="$REPO/ARCHITECTURE.md" memory="$REPO/.claude/CLAUDE.md" pair name cap n
  if [ ! -f "$arch" ]; then
    echo "records: ARCHITECTURE.md is missing"
  else
    for pair in "Decisions:$ARCH_DECISIONS_CAP" "Next:$ARCH_NEXT_CAP"; do
      name="${pair%:*}"; cap="${pair#*:}"
      n="$(section_lines "$arch" "$name")"
      if [ -z "$n" ]; then echo "records: ARCHITECTURE.md has no ## $name section"
      elif [ "$n" -gt "$cap" ]; then echo "records: ARCHITECTURE.md ## $name has $n lines, at most $cap: rewrite or delete one"
      fi
    done
    missing_paths "$arch" "$REPO"
  fi
  if [ ! -f "$memory" ]; then
    echo "records: .claude/CLAUDE.md is missing"
  else
    n="$(grep -c '' "$memory")"
    [ "$n" -le "$PROJECT_MEMORY_CAP" ] || echo "records: .claude/CLAUDE.md has $n lines, at most $PROJECT_MEMORY_CAP"
    missing_paths "$memory" "$REPO/.claude" "$REPO"
  fi
  if [ -f "$REPO/TESTING.md" ]; then
    n="$(grep -c '' "$REPO/TESTING.md")"
    [ "$n" -le "$TESTING_CAP" ] || echo "records: TESTING.md has $n lines, at most $TESTING_CAP: it is the one page about the tests"
  fi
}

records() {
  local out problems
  out="$(record_problems)"
  if [ -n "$out" ]; then
    echo "$out"
    fail_lines <<<"$out"
    problems=$(($(printf '%s\n' "$out" | wc -l)))
    total=$((total + problems))
    failed=$((failed + problems))
    echo "records: $problems problem(s)"
  else
    echo "records: pages and tree agree"
  fi
}
