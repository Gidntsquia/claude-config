# The records (sourced by test/run): the pages a new session reads to learn what exists and where work goes.
#   records        ARCHITECTURE.md and .claude/CLAUDE.md exist, stay under their caps and name only real paths
#   record_full    after `test/run all --report`: keep this system's result and rewrite the README status line

ARCH_DECISIONS_CAP=20
ARCH_NEXT_CAP=10
PROJECT_MEMORY_CAP=60

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
}

records() {
  local out problems
  out="$(record_problems)"
  if [ -n "$out" ]; then
    echo "$out"
    problems=$(($(printf '%s\n' "$out" | wc -l)))
    total=$((total + problems))
    failed=$((failed + problems))
    echo "records: $problems problem(s)"
  else
    echo "records: pages and tree agree"
  fi
}

# ---- the README status line ---------------------------------------------------------------------------------
# test/results/full-<system>.txt holds the last full run on that system, one line: `<date>|<version>|<failed>|<total>|<skipped>|<stamp>`
this_system() { # prints `<system> <version>`; nothing on a system the status line does not name
  local v
  case "$(uname -s)" in
    Darwin) echo "macos $(sw_vers -productVersion 2>/dev/null)" ;;
    MINGW*|MSYS*) echo "windows" ;;
    Linux)
      v="$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${OS_RELEASE:-/etc/os-release}" 2>/dev/null)"
      grep -qx 'ID=ubuntu' "${OS_RELEASE:-/etc/os-release}" 2>/dev/null && echo "ubuntu $v" ;;
  esac
}

# status_line: `Last full run: <date>, macOS <v> / Ubuntu <v> / Windows: all <n> tests passed` when all three
# passed with the same count; otherwise each system says its own result, `not run` included.
status_line() {
  local s name f date v bad n skipped rest newest="" names="" counts="" parts="" same=1 first="" part passed=0 skips_all=0
  for s in macos ubuntu windows; do
    f="$RESULTS/full-$s.txt"
    [ -f "$f" ] || continue
    IFS='|' read -r date rest < "$f"
    [[ "$date" > "$newest" ]] && newest="$date"
  done
  for s in macos ubuntu windows; do
    case "$s" in macos) name=macOS ;; ubuntu) name=Ubuntu ;; windows) name=Windows ;; esac
    f="$RESULTS/full-$s.txt"
    if [ ! -f "$f" ]; then same=0; parts="$parts${parts:+; }$name: not run"; continue; fi
    IFS='|' read -r date v bad n skipped rest < "$f"
    name="$name${v:+ $v}"
    names="$names${names:+ / }$name"
    if [ "$bad" = 0 ]; then part="all $n tests passed"; passed=$((passed + 1))
    else part="$bad of $n tests failed"; same=0; fi
    [ "$skipped" = 0 ] || part="$part ($skipped skipped)"
    [ "$date" = "$newest" ] || { part="$part on $date"; same=0; }
    [ -n "$first" ] || first="$n"
    [ "$n" = "$first" ] || same=0
    skips_all=$((skips_all + skipped))
    parts="$parts${parts:+; }$name: $part"
  done
  if [ "$same" = 1 ] && [ "$passed" = 3 ]; then
    part="all $first tests passed"
    [ "$skips_all" = 0 ] || part="$part ($skips_all skips across the three)"
    echo "Last full run: $newest, $names: $part"
  else
    echo "Last full run: $newest, $parts"
  fi
}

record_full() {
  local sys name v readme="$REPO/README.md" line
  grep -q '^\[Last full run: ' "$readme" 2>/dev/null ||
    { echo "test/run: README.md lacks its \`[Last full run: ...](TESTING.md)\` line" >&2; return 2; }
  sys="$(this_system)"
  if [ -z "$sys" ]; then echo "report: README.md left alone: the status line names macOS, Ubuntu and Windows"; return 0; fi
  name="${sys%% *}"; v=""
  [ "$sys" = "$name" ] || v="${sys#* }"
  mkdir -p "$RESULTS"
  echo "$(TZ=America/New_York date '+%Y-%m-%d')|$v|$failed|$total|$skips|$(stamp)" > "$RESULTS/full-$name.txt"
  line="[$(status_line)](TESTING.md)"
  awk -v line="$line" '/^\[Last full run: / { print line; next } { print }' "$readme" > "$WORK_EXTRA/readme" &&
    cat "$WORK_EXTRA/readme" > "$readme"
  echo "report: README.md says: $line"
}
