load ../helpers/common

setup() {
  temp_home
  RW="$REPO/agents/report-writer"
  CHECK="$REPO/agents/evals/report-writer/check.py"
  FIX="$REPO/test/fixtures/report-writer"
  export REPORT_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl"
  unset REPORT_WRITER_HOME CLAUDE_CONFIG_DIR FAKE_FIND_ERR FAKE_CARDS_ERR
  WORK="$BATS_TEST_TMPDIR/study"
  mkdir -p "$WORK"
  cp -R "$FIX/tiny/." "$WORK/"
  OUT="$WORK/report"
  PY="$(python3 -I -c 'import sys; print(sys.executable)')"
}

need_script_node() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) skip "the stand-in node is a script with a shebang, which Windows Python cannot start" ;; esac
}

build() { python3 -I "$RW/build.py" "$OUT" --data "$WORK/data" "$@"; }

# py <code> [args]: run a short Python snippet
py() { python3 -I -c "import json,sys,os,io
$1" "${@:2}"; }

values() {
  py 'for k, e in json.load(open(sys.argv[1])).items(): print("%s=%s" % (k, e.get("value")))' "$OUT/numbers.json"
}

# replace <file> <old> <new>: replace one exact text, failing when it is not there
replace() {
  py 'p, old, new = sys.argv[1:4]
s = io.open(p, encoding="utf-8").read()
assert old in s, "not in " + p + ": " + old
io.open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))' "$@"
}

# check_case <report dir>: check.py over a copy of a stored report, with no study data
check_case() {
  cp -R "$1" "$BATS_TEST_TMPDIR/case"
  run python3 -I "$CHECK" "$BATS_TEST_TMPDIR/case" --data "$BATS_TEST_TMPDIR/no-data" --mode phone --prose
}

# bats test_tags=feature:report-writer
@test "build reads each figure from the study files and prints it with its unit on the page" {
  run build --no-cards
  assert_success
  assert_output --partial "build: 1 card(s), 5 figures used of 5; no cards (--no-cards)"
  run values
  assert_output "old_s=12.5
new_mean=10.5
saved=2.0
saved_share=0.16
tokens=1234567.0"
  run cat "$OUT/report.html"
  assert_output --partial '<span class="n" data-key="old_s">12.5 s</span>'
  assert_output --partial '<span class="n" data-key="new_mean">10.50 s</span> <span class="src">(fast)</span>'
  assert_output --partial '<span class="n" data-key="saved_share">16.0%</span>'
  assert_output --partial '<span class="n" data-key="tokens">1,234,567 tokens</span>'
  assert_output --partial '<span class="id">gen 7</span>'
  assert_output --partial '<q class="ask">Why is the loop slow?</q>'
  assert_output --partial '<th class="num">seconds <span class="u">(s)</span></th>'
  run cat "$OUT/checker/OFF.txt"
  assert_output "checker: off (built with --no-checker)"
  assert_file_not_exist "$REPORT_LEDGER"
}

# bats test_tags=feature:report-writer
@test "build looks for study files in the report folder's parent when --data is not given" {
  mv "$WORK/data/runs.json" "$WORK/data/run.log" "$WORK/"
  run python3 -I "$RW/build.py" "$OUT" --no-cards
  assert_success
  refute_output --partial "not found"
  run values
  assert_output --partial "old_s=12.5"
}

# bats test_tags=feature:report-writer
@test "build replaces a wrong derived figure and says so" {
  replace "$OUT/numbers.json" '"seconds saved", "value": 99' '"seconds saved", "value": -7'
  run build --no-cards
  assert_success
  assert_output --partial "numbers: saved: stored -7 replaced by recomputed 2"
  run values
  assert_output --partial "saved=2.0"
}

# bats test_tags=feature:report-writer
@test "build shows a negative signed change with a real minus sign" {
  replace "$OUT/numbers.json" '["old_s", "new_mean"]' '["new_mean", "old_s"]'
  replace "$OUT/numbers.json" '"fmt": 2, "derived": {"op": "diff"' '"fmt": 2, "signed": true, "derived": {"op": "diff"'
  run build --no-cards
  assert_success
  run cat "$OUT/report.html"
  assert_output --partial '<span class="n" data-key="saved">−2.00 s</span>'
}

# bats test_tags=feature:report-writer
@test "build refuses to read a figure from a data file the writer made inside the report folder" {
  printf '[{"name": "slow", "seconds": 1}]\n' >"$OUT/tally.json"
  replace "$OUT/numbers.json" '"file": "runs.json", "field": "[name=slow]' '"file": "../report/tally.json", "field": "[name=slow]'
  run build --no-cards
  assert_success
  assert_output --partial "numbers: old_s: file ../report/tally.json is a writer-made data file"
  run values
  assert_output --partial "old_s=None"
}

# bats test_tags=feature:report-writer
@test "build stops on a figure the numbers file does not have" {
  replace "$OUT/report.md" "over {tokens}" "over {nothing}"
  run build --no-cards
  assert_failure
  assert_output --partial "build.py: unknown figure {nothing}"
  assert_file_not_exist "$OUT/report.html"
}

# bats test_tags=feature:report-writer
@test "build stops on a digit typed into a table cell" {
  replace "$OUT/report.md" ";; old | {old_s}" ";; old | 12.5"
  run build --no-cards
  assert_failure
  assert_output --partial "::table cell '12.5' holds a typed digit"
}

# bats test_tags=feature:report-writer
@test "build stops on a table row with the wrong number of cells" {
  replace "$OUT/report.md" ";; old | {old_s}" ";; old"
  run build --no-cards
  assert_failure
  assert_output --partial "::table row 'old' has 1 cells, the header has 2"
}

# bats test_tags=feature:report-writer
@test "build stops on a split bar whose parts do not add up to its total" {
  replace "$OUT/report.md" "::checker off" "::split old_s | new_mean saved_share

::checker off"
  run build --no-cards
  assert_failure
  assert_output --partial "::split old_s: segments new_mean + saved_share sum to 10.66, total is 12.5 (-14.7%, more than 1% off)"
}

# bats test_tags=feature:report-writer
@test "build stops on a side-by-side card label that holds a digit" {
  replace "$OUT/report.md" "::checker off" "::pair left=old_s right=new_mean | rows=run7

::checker off"
  run build --no-cards
  assert_failure
  assert_output --partial "::pair row label 'run7' holds a digit; name it in words"
}

# bats test_tags=feature:report-writer
@test "build prints the checker's loops, findings and cost on the last line of the report" {
  replace "$OUT/report.md" "::checker off" "::checker loops=2 raised=3 fixed=2 open=1 tokens=4567 seconds=89"
  run build --no-cards
  assert_success
  run cat "$OUT/report.html"
  assert_output --partial "checker: 2 loop"
  assert_output --partial "checker tokens 4,567, wall 89 s"
}

# bats test_tags=feature:report-writer
@test "build turns a send-back note into its own page without a checker folder" {
  printf '# Needs data\n\nThe run took {secs}.\n' >"$OUT/NEEDS-DATA.md"
  printf '{"secs": {"label": "secs", "value": 3, "unit": "s", "fmt": 0}}\n' >"$OUT/needs-data.json"
  run build --md NEEDS-DATA.md --numbers needs-data.json --no-cards
  assert_success
  run cat "$OUT/NEEDS-DATA.html"
  assert_output --partial '<span class="n" data-key="secs">3 s</span>'
  assert_file_not_exist "$OUT/report.html"
  assert_file_not_exist "$OUT/checker/OFF.txt"
}

# bats test_tags=feature:report-writer
@test "build names the missing report or numbers file" {
  rm "$OUT/numbers.json"
  run build --no-cards
  assert_failure
  assert_a_line_matches '^build\.py: no .*/numbers\.json'
  refute_output --partial "Traceback"
  rm "$OUT/report.md"
  run build --no-cards
  assert_failure
  assert_a_line_matches '^build\.py: no .*/report\.md'
  refute_output --partial "Traceback"
  run python3 -I "$RW/build.py"
  assert_failure
  assert_output --partial "python3 -I build.py <report dir>"
}

# bats test_tags=feature:report-writer
@test "a full build splits the report into screen-sized cards, counts words and writes one ledger line" {
  need_script_node
  replace "$OUT/report.md" "::checker off" "## What was saved?

The saving again is {saved}.

::checker off"
  printf '## Openings\n\npick: moment — it fits the run\n' >"$OUT/NOTES.md"
  printf '{"out": "/elsewhere", "title_shape": "x"}\n' >"$REPORT_LEDGER"
  PATH="$FIX/bin:$PATH" run build
  assert_success
  assert_output --partial "figures used of 5"
  assert_output --regexp "build: [2-9] cards \("
  assert_output --partial "words: "
  assert_output --partial "ledger: moment | The _ in the _"
  PATH="$FIX/bin:$PATH" run build
  assert_success
  run py 'rows = [json.loads(l) for l in open(sys.argv[1])]
print(len(rows), rows[0]["out"], rows[1]["form"], rows[1]["out"] == os.path.realpath(sys.argv[2]))
print([w["section"] for w in json.load(open(sys.argv[2] + "/cards/measure.json"))["words"]])' "$REPORT_LEDGER" "$OUT"
  assert_output --partial "2 /elsewhere moment True"
  assert_output --partial "What was saved?"
}

# bats test_tags=feature:report-writer
@test "build says so when the card renderer fails" {
  need_script_node
  PATH="$FIX/bin:$PATH" FAKE_CARDS_ERR="browser crashed" run build
  assert_failure
  assert_output --partial "cards.mjs failed: browser crashed"
  assert_file_not_exist "$REPORT_LEDGER"
}

# bats test_tags=feature:report-writer
@test "the card renderer is JavaScript node can parse" {
  run node --check "$RW/cards.mjs"
  assert_success
}

# bats test_tags=feature:report-writer
@test "check passes the figure checks on a freshly built report" {
  build --no-cards
  run python3 -I "$CHECK" "$OUT" --data "$WORK/data" --mode phone --prose
  assert_output --partial "PASS numbers_match_sources: 5 figures match their sources"
  assert_output --partial "PASS numbers_on_page: 7 number spans, 0 loose numbers"
  assert_output --partial "PASS one_value_per_quantity: 5 labels, each one value"
  assert_output --partial "PASS figures: 5 keys in report.md all resolve; no digit typed in prose"
  assert_output --partial "PASS checker_line: checker: off"
  # the tiny study is no essay, so the whole check fails on layout and style, and on nothing about the figures
  assert_failure 1
  assert_a_line_matches '^check\.py: FAIL \([0-9]+ failing: paragraphs, '
  refute_a_line_matches '^FAIL (numbers_|one_value|figures|checker_line|expected)'
}

# bats test_tags=feature:report-writer
@test "check fails a report whose figure no longer matches the study file" {
  build --no-cards
  replace "$WORK/data/runs.json" '"seconds": 12.5' '"seconds": 20'
  run python3 -I "$CHECK" "$OUT" --data "$WORK/data" --mode phone --prose
  assert_failure 1
  assert_output --partial "FAIL numbers_match_sources: old_s: runs.json → [name=slow].seconds = 20"
  assert_output --partial "numbers.json says 12.5"
}

# bats test_tags=feature:report-writer
@test "check fails a number typed straight into the page or the prose" {
  build --no-cards
  replace "$OUT/report.html" "The saving is " "The saving of 4321 is "
  replace "$OUT/report.md" "The saving is " "The saving of 4321 is "
  run python3 -I "$CHECK" "$OUT" --data "$WORK/data" --mode phone --prose
  assert_failure 1
  assert_output --partial "FAIL numbers_on_page: 1 numbers outside numbers.json spans: '4321'"
  assert_output --partial "FAIL figures:"
  assert_output --partial "digits typed in prose: [\"'4321' in"
}

# bats test_tags=feature:report-writer
@test "check compares the deciding figures and state words with an expected file" {
  build --no-cards
  printf '{"figures": [{"key": "saved", "value": 2, "tol": 0.01}], "state_words": ["saving"]}\n' >"$WORK/expected.json"
  run python3 -I "$CHECK" "$OUT" --data "$WORK/data" --mode phone --prose --expected "$WORK/expected.json"
  assert_output --partial "PASS expected: 1 figures within tolerance"
  refute_a_line_matches '^check\.py: FAIL .*expected'
  assert_a_line_matches '^check\.py: FAIL \([0-9]+ failing: '
  printf '{"figures": [{"key": "saved", "value": 777, "tol": 0.01}], "state_words": ["abandoned"]}\n' >"$WORK/expected.json"
  run python3 -I "$CHECK" "$OUT" --data "$WORK/data" --mode phone --prose --expected "$WORK/expected.json"
  assert_failure 1
  assert_output --partial "FAIL expected: saved: expected 777±0.01, no figure within tolerance; state word 'abandoned' missing from the ending"
  assert_a_line_matches '^check\.py: FAIL \([0-9]+ failing: .*expected\)'
}

# bats test_tags=feature:report-writer
@test "the golden report passes every check that does not need the study data" {
  # checked where it lies: a copy elsewhere is rightly failed for copying the golden's sentences
  run python3 -I "$CHECK" "$REPO/agents/evals/report-writer/golden/r5/B" \
    --data "$BATS_TEST_TMPDIR/no-data" --mode phone --prose
  assert_failure 1
  assert_output --partial "PASS style: "
  assert_output --partial "PASS outline_match: "
  assert_output --partial "failing: numbers_match_sources)"
}

# bats test_tags=feature:report-writer
@test "check fails a report that copies sentences from the golden report" {
  check_case "$REPO/agents/evals/report-writer/golden/r5/B"
  assert_failure 1
  assert_output --partial "FAIL style: shared: "
  assert_output --partial "copied from golden r5/B"
}

# bats test_tags=feature:report-writer
@test "the focus case is caught for its section that has no outline row" {
  check_case "$RW/cases/focus"
  assert_failure 1
  assert_output --partial "FAIL outline_match: section 7: report.md has '🧭 How did the certain feed do on its own?'"
  assert_output --partial "FAIL unasked_once: 'certain feed' in 3 sentences"
  assert_output --partial "failing: numbers_match_sources, style, outline_match, outline_budget, unasked_once)"
}

# bats test_tags=feature:report-writer
@test "the slips case is caught for its four writing slips" {
  check_case "$RW/cases/slips"
  assert_failure 1
  assert_output --partial "FAIL doubled_unit: "
  assert_output --partial "{a_unused_n} (unit 'listings') is followed by 'listings'"
  assert_output --partial "FAIL split_sliver: "
  assert_output --partial "segment 'unused' ({a_unused}) is 1.5% of A_total"
  assert_output --partial "FAIL machinery_aside: "
  assert_output --partial "FAIL opening_subject: "
  assert_output --partial "names the machine 'Jaxon-PC'"
  assert_output --partial "PASS checker_rows: 4 claim findings, 0 high open"
  assert_output --partial "failing: numbers_match_sources, doubled_unit, split_sliver, machinery_aside, opening_subject)"
}

# bats test_tags=feature:report-writer
@test "check fails a serious checker finding that was left open" {
  cp -R "$RW/cases/slips" "$BATS_TEST_TMPDIR/open"
  replace "$BATS_TEST_TMPDIR/open/NOTES.md" "state words unchanged, no second read | fixed |" "state words unchanged, no second read | |"
  run python3 -I "$CHECK" "$BATS_TEST_TMPDIR/open" --data "$BATS_TEST_TMPDIR/no-data" --mode phone --prose
  assert_failure 1
  assert_output --partial "FAIL checker_rows: 1 high finding(s) open: 'A_measured'"
}

# preflight_home: a report-writer folder with the files preflight looks for
preflight_home() {
  export REPORT_WRITER_HOME="$BATS_TEST_TMPDIR/agents/report-writer"
  mkdir -p "$REPORT_WRITER_HOME" "$BATS_TEST_TMPDIR/agents/evals/report-writer"
  : >"$REPORT_WRITER_HOME/build.py"
  : >"$REPORT_WRITER_HOME/cards.mjs"
  : >"$BATS_TEST_TMPDIR/agents/evals/report-writer/check.py"
}

# bats test_tags=feature:report-writer
@test "preflight is silent when everything a build needs is there" {
  need_script_node
  PATH="$FIX/bin:$PATH" run python3 -I "$RW/preflight.py"
  assert_success
  assert_output ""
}

# bats test_tags=feature:report-writer
@test "preflight names the missing files and how to restore them" {
  preflight_home
  rm "$REPORT_WRITER_HOME/build.py" "$BATS_TEST_TMPDIR/agents/evals/report-writer/check.py"
  run python3 -I "$RW/preflight.py"
  assert_failure 1
  assert_output --partial "blocked: rerun claude-config's install.sh; missing "
  assert_output --partial "build.py, "
  assert_output --partial "check.py"
  refute_output --partial "cards.mjs"
}

# bats test_tags=feature:report-writer
@test "preflight asks for Node.js when node is not on PATH" {
  preflight_home
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  PATH="$BATS_TEST_TMPDIR/empty" run "$PY" -I "$RW/preflight.py"
  assert_failure 1
  assert_output "blocked: install Node.js so \`node\` is on PATH (the cards are drawn by cards.mjs)"
}

# bats test_tags=feature:report-writer
@test "preflight passes on the install command for a missing browser library" {
  need_script_node
  preflight_home
  PATH="$FIX/bin:$PATH" FAKE_FIND_ERR="no playwright; install it: npx playwright install chromium --with-deps" \
    run python3 -I "$RW/preflight.py"
  assert_failure 1
  assert_output "blocked: npx playwright install chromium --with-deps"
  PATH="$FIX/bin:$PATH" FAKE_FIND_ERR="something else broke" run python3 -I "$RW/preflight.py"
  assert_failure 1
  assert_output "blocked: npm i -g playwright && npx playwright install chromium"
}

# transcripts: three subagent logs, one after the cutoff, one begun before it, one untouched since before it
transcripts() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  py 'import datetime
d = os.path.join(sys.argv[1], "projects", "p", "s", "subagents")
os.makedirs(d)
def log(name, start, tokens):
    rows = [{"type": "user", "timestamp": start + ":00Z"},
            {"type": "assistant", "timestamp": start + ":30Z", "message": {"usage": {"input_tokens": tokens,
             "cache_creation_input_tokens": 20, "cache_read_input_tokens": 3, "output_tokens": 4}}},
            {"type": "user", "timestamp": start + ":45Z", "message": {"usage": {"input_tokens": 9999}}}]
    p = os.path.join(d, "agent-%s.jsonl" % name)
    open(p, "w").write("".join(json.dumps(r) + "\n" for r in rows) + "not json\n")
    return p
log("new", "2021-03-02T10:00", 100)
log("began-before", "2021-02-01T10:00", 5000)
old = log("stale", "2021-03-02T11:00", 7000)
t = datetime.datetime(2020, 1, 1, tzinfo=datetime.timezone.utc).timestamp()
os.utime(old, (t, t))' "$CLAUDE_CONFIG_DIR"
}

# bats test_tags=feature:report-writer
@test "checker usage totals the tokens and seconds of subagents started since the given time" {
  transcripts
  run python3 -I "$RW/checker_usage.py" 2021-03-01T00:00:00Z
  assert_success
  assert_output "tokens=127 seconds=45 agents=1"
  run python3 -I "$RW/checker_usage.py" 2021-03-01T00:00:00Z --json
  assert_success
  assert_output --partial '"tokens": 127, "seconds": 45, "agents": 1'
  assert_output --partial 'agent-new.jsonl'
}

# bats test_tags=feature:report-writer
@test "checker usage reports zero when no subagent ran, and needs a start time" {
  transcripts
  run python3 -I "$RW/checker_usage.py" 2022-01-01T00:00:00Z
  assert_success
  assert_output "tokens=0 seconds=0 agents=0"
  run python3 -I "$RW/checker_usage.py"
  assert_failure 1
  assert_output --partial "checker_usage.py <since ISO-8601 UTC"
}
