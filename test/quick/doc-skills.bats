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
  needs "$REPO/agents/report-writer/build.py" '--no-checker' 'PLAYWRIGHT_DIR'
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
  local desc title n=0
  desc="$(field "$REVIEW_SKILL" description | tr '[:upper:]' '[:lower:]')"
  run grep -cE '^## Pass [0-9]+ ' "$REVIEW_SKILL"
  assert_output "6"
  assert_equal "$(grep -oE '^## Pass [0-9]+' "$REVIEW_SKILL" | awk '{ printf "%s", $3 }')" "123456"
  while IFS= read -r title; do
    echo "pass: $title"
    printf '%s\n' "$desc" | grep -qF -- "$title"
    n=$((n + 1))
  done < <(sed -n 's/^## Pass [1-6] [^A-Za-z]*//p' "$REVIEW_SKILL" | tr '[:upper:]' '[:lower:]')
  assert_equal "$n" "6"
}

# bats test_tags=feature:doc-skills
@test "review-skill takes the skill to review as its argument and waits before editing" {
  test -n "$(field "$REVIEW_SKILL" argument-hint)"
  needs "$REVIEW_SKILL" 'Resolve `$ARGUMENTS` to a SKILL.md path' 'if empty, ask which skill' \
    '**Wait for approval before editing**'
}
