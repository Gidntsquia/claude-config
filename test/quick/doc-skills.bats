#!/usr/bin/env bats
# The three documentation skills (write-readme, write-report, review-skill): what can be checked offline.

load ../helpers/common

setup() {
  temp_home
  README_SKILL="$REPO/skills/write-readme/SKILL.md"
  REPORT_SKILL="$REPO/skills/write-report/SKILL.md"
  REVIEW_SKILL="$REPO/skills/review-skill/SKILL.md"
  WRITER="$REPO/agents/report-writer.md"
}

# field <file> <key>: the value of a one-line key in the frontmatter that opens the file.
field() {
  awk -v k="$2" 'NR==1 { if ($0 != "---") exit; next } /^---$/ { exit }
    index($0, k ": ") == 1 { print substr($0, length(k) + 3) }' "$1"
}

# needs <file> <text>...: each text is in the file; names the first one that is not.
needs() {
  local f="$1" t
  shift
  for t in "$@"; do
    grep -qF -- "$t" "$f" || { echo "${f#"$REPO"/} does not hold: $t"; return 1; }
  done
}

# says <file> <sentence>: the file holds the sentence, wherever its lines wrap.
says() {
  tr '\n' ' ' < "$1" | tr -s ' ' | grep -qF -- "$2" || { echo "${1#"$REPO"/} does not say: $2"; return 1; }
}

# bats test_tags=feature:doc-skills
@test "each documentation skill is named after its folder and says when to use it" {
  local s f desc
  for s in write-readme write-report review-skill; do
    f="$REPO/skills/$s/SKILL.md"
    assert_file_exist "$f"
    assert_equal "$(field "$f" name)" "$s"
    desc="$(field "$f" description)"
    echo "$s: $desc"
    test "${#desc}" -gt 60
    printf '%s\n' "$desc" | grep -qiE 'use |load '
    # the frontmatter is closed, so the skill has a body
    test "$(grep -c '^---$' "$f")" -ge 2
  done
}

# bats test_tags=feature:doc-skills
@test "every reference file a documentation skill names is in that skill's folder" {
  local s ref n=0
  for s in write-readme write-report review-skill; do
    for ref in $(grep -oE 'references/[A-Za-z0-9_-]+\.[a-z]+' "$REPO/skills/$s/SKILL.md" | sort -u); do
      assert_file_exist "$REPO/skills/$s/$ref"
      n=$((n + 1))
    done
  done
  test "$n" -ge 1
}

# bats test_tags=feature:doc-skills
@test "the README style file holds the template, voice rules and rejected sentences write-readme promises" {
  local style="$REPO/skills/write-readme/references/style.md"
  needs "$README_SKILL" 'references/style.md' 'it has the template, voice rules and the sentences the user rejected' \
    'Always include the License section'
  run grep -E '^## ' "$style"
  assert_success
  assert_output --partial "## Template"
  assert_output --partial "## Quickstart"
  assert_output --partial "## License"
  assert_output --partial "## Voice"
  assert_output --partial "## Sentences the user flagged"
}

# bats test_tags=feature:doc-skills
@test "every git command write-readme names is a command git has" {
  local sub list n=0
  list="$(git --list-cmds=main)"
  for sub in $(grep -oE '`git (-C wiki )?[a-z][a-z-]*|&& git -C wiki [a-z][a-z-]*' "$README_SKILL" |
    awk '{ print $NF }' | sort -u); do
    echo "git $sub"
    printf '%s\n' "$list" | grep -qx -- "$sub"
    n=$((n + 1))
  done
  test "$n" -ge 4
}

# bats test_tags=feature:doc-skills
@test "write-report starts an agent that exists, with the options that agent reads" {
  needs "$REPORT_SKILL" 'claude -p --agent report-writer ". — <question> --out <dir>"' '--no-checker' 'PLAYWRIGHT_DIR' 'ASK.md'
  assert_equal "$(field "$WRITER" name)" "report-writer"
  needs "$WRITER" '--out <dir>' '--no-checker' 'PLAYWRIGHT_DIR' 'ASK.md'
  needs "$REPO/agents/report-writer/build.py" '--no-checker'
  needs "$REPO/agents/report-writer/cards.mjs" 'process.env.PLAYWRIGHT_DIR'
}

# bats test_tags=feature:doc-skills
@test "the report check write-report asks for is one check.py offers" {
  needs "$REPORT_SKILL" 'check.py --prose'
  run python3 -I "$REPO/agents/evals/report-writer/check.py"
  assert_failure
  assert_output --partial "check.py <outdir> --prose"
}

# bats test_tags=feature:doc-skills
@test "every send-back and failure ending write-report acts on is one the report-writer can end with" {
  local t
  for t in 'send-back: needs data' 'NEEDS-DATA.md' 'ci_includes_zero' 'n_below_two' 'arm_not_run' '## Collect' \
    '## Checker' 'check.py:' 'blocked:'; do
    needs "$REPORT_SKILL" "$t"
    needs "$WRITER" "$t"
  done
}

# bats test_tags=feature:doc-skills
@test "review-skill runs the six passes its description lists, in order" {
  local desc listed titles
  desc="$(field "$REVIEW_SKILL" description | tr '[:upper:]' '[:lower:]')"
  run grep -cE '^## Pass [0-9]+ ' "$REVIEW_SKILL"
  assert_output "6"
  assert_equal "$(grep -oE '^## Pass [0-9]+' "$REVIEW_SKILL" | awk '{ printf "%s", $3 }')" "123456"
  # the list after "(skill.md):" up to the first full stop outside brackets, one name per line
  listed="$(printf '%s\n' "$desc" | sed -e 's/^[^:]*: *//' -e 's/ ([^)]*)//g' -e 's/\..*//' | tr ',' '\n' | sed -e 's/^ *//' -e 's/^and //')"
  titles="$(sed -n 's/^## Pass [1-6] [^A-Za-z]*//p' "$REVIEW_SKILL" | tr '[:upper:]' '[:lower:]')"
  assert_equal "$(printf '%s\n' "$titles" | grep -c '[a-z]')" "6"
  assert_equal "$titles" "$listed"
}

# bats test_tags=feature:doc-skills
@test "review-skill takes the skill to review as its argument and waits before editing" {
  test -n "$(field "$REVIEW_SKILL" argument-hint)"
  needs "$REVIEW_SKILL" 'Resolve `$ARGUMENTS` to a SKILL.md path' 'if empty, ask which skill' \
    '**Wait for approval before editing**'
}

# bats test_tags=feature:doc-skills
@test "write-report does not deliver a report with an open high checker finding" {
  says "$REPORT_SKILL" 'An open `high` finding is treated like `check.py: FAIL`.'
  says "$REPORT_SKILL" 'the report is not written'
}

# bats test_tags=feature:doc-skills
@test "write-readme asks before it creates a GitHub repo" {
  says "$README_SKILL" 'ask with AskUserQuestion before creating anything'
  says "$README_SKILL" 'On approval: `gh repo create'
}
