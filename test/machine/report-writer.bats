#!/usr/bin/env bats
# The report-writer's card renderer with the real node, Playwright and headless Chromium.
# The quick tier runs build.py with the stand-in node in test/fixtures/report-writer/bin.

load ../helpers/common

setup() {
  command -v node >/dev/null 2>&1 || skip "node missing"
  local home   # the account's own home, where Playwright keeps its browsers
  home="$(python3 -c 'import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
  temp_home
  export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$home/.cache/ms-playwright}"
  [ "$(uname -s)" != Darwin ] || [ -d "$PLAYWRIGHT_BROWSERS_PATH" ] || PLAYWRIGHT_BROWSERS_PATH="$home/Library/Caches/ms-playwright"
  export REPORT_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl"
  unset REPORT_WRITER_HOME CLAUDE_CONFIG_DIR
  WORK="$BATS_TEST_TMPDIR/study"
  mkdir -p "$WORK"
  cp -R "$REPO/test/fixtures/report-writer/tiny/." "$WORK/"
}

# bats test_tags=feature:report-writer
@test "a full build with the real card renderer draws a picture for every card" {
  run python3 -I "$REPO/agents/report-writer/build.py" "$WORK/report" --data "$WORK/data"
  case "$output" in *"playwright not found"*|*"Executable doesn't exist"*) skip "playwright missing" ;; esac
  assert_success
  assert_output --partial "cards ("
  pictures="$(find "$WORK/report/cards" -name '*.png' | wc -l | tr -d ' ')"
  [ "$pictures" -ge 1 ]
  run python3 -c 'import json,sys; print(all(c["css_height_px"] > 0 for c in json.load(open(sys.argv[1]))["cards"]))' "$WORK/report/cards/measure.json"
  assert_output "True"
}
