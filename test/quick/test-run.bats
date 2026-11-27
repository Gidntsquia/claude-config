#!/usr/bin/env bats
# The runner itself: what makes `PASS <n> tests` trustworthy. Each case runs a copy of test/run in a scratch
# repo that holds only the test files the case writes, so nothing here runs the real suite.
# The planted bad lines are built from pieces: the lint reads this file too.

load ../helpers/common

setup() {
  temp_home
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/test/quick" "$R/test/helpers"
  cp "$REPO/test/run" "$R/test/run"
}

# put <file under test/quick> <test body>: one @test in a file of its own.
put() { printf '# bats file_%s=feature:x\n@%s "case" {\n  %s\n}\n' tags test "$2" >"$R/test/quick/$1"; }

# list: a features.txt that matches the scratch files, unless the case wrote its own
list() {
  [ -f "$R/own-list" ] && return 0
  local n
  n="$(cat "$R"/test/quick/*.bats 2>/dev/null | grep -c '^@test ' || true)"
  echo "x | the scratch feature | feature:x=$n" >"$R/test/features.txt"
}

# A clean environment, so the inner bats does not read the outer run's BATS_* variables.
# suite [NAME=value ... --] [test/run arguments]
suite() {
  local bats vars=()
  while [ $# -gt 0 ]; do case "$1" in *=*) vars[${#vars[@]}]="$1"; shift ;; --) shift; break ;; *) break ;; esac; done
  bats="$REPO/test/vendor/bats-core/bin/bats"
  [ -f "$bats" ] || bats="$(PATH="${PATH#"$BATS_LIBEXEC:"}" command -v bats)"
  list
  run env -i PATH="$(dirname "$bats"):/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$BATS_TEST_TMPDIR" HOME="$TEST_HOME" ${vars[@]+"${vars[@]}"} bash "$R/test/run" "$@"
}

last_line() { printf '%s\n' "$output" | tail -n 1; }

# bats test_tags=feature:test-runner
@test "test/run: passing tests end in PASS <n> tests and exit 0" {
  put a.bats true
  put b.bats true
  suite
  assert_success
  assert_equal "$(last_line)" "PASS 2 tests"
}

# bats test_tags=feature:test-runner
@test "test/run: a failing test ends in FAIL <failed> of <n> and exit 1" {
  put a.bats true
  put b.bats false
  suite
  assert_failure 1
  assert_equal "$(last_line)" "FAIL 1 of 2"
}

# bats test_tags=feature:test-runner
@test "test/run: a test file bats cannot read is a failure, not a pass" {
  put a.bats true
  printf '@%s "broken" {\n  if\n' test >"$R/test/quick/b.bats"
  suite
  assert_failure 1
  assert_a_line_matches '^FAIL [0-9]+ of [0-9]+$'
}

# bats test_tags=feature:test-runner
@test "test/run: bats dying part way through is a failure, not a pass" {
  put a.bats true
  put b.bats 'kill -9 "$(ps -o ppid= -p "$PPID" | tr -d " ")" "$PPID"'
  put c.bats true
  suite
  assert_failure 1
}

# bats test_tags=feature:test-runner
@test "test/run: a fixed wait in a quick test fails the run and names file and line" {
  put a.bats "sl""eep 1"
  suite
  assert_failure 1
  assert_output --partial "lint: test/quick/a.bats:3: sleep"
}

# bats test_tags=feature:test-runner
@test "test/run: a fixed wait spelled with its full path or in python is caught too" {
  put a.bats "/bin/sl""eep 1"
  put b.bats "python3 -c 'import time; time.sl""eep(1)'"
  suite
  assert_failure 1
  assert_output --partial "lint: test/quick/a.bats:3: sleep"
  assert_output --partial "lint: test/quick/b.bats:3: sleep"
}

# bats test_tags=feature:test-runner
@test "test/run: network, the real home, a bare skip and a fixed port each fail the run" {
  put net.bats "cu""rl https://example.invalid"
  put home.bats 'ls "$HO''ME"'
  put skip.bats "sk""ip"
  put port.bats "server --po""rt 8080"
  suite
  assert_failure 1
  assert_output --partial "net.bats:3: cu""rl or wget"
  assert_output --partial 'home.bats:3: $HO''ME'
  assert_output --partial "skip.bats:3: skip with no reason"
  assert_output --partial "port.bats:3: fixed port"
}

# bats test_tags=feature:test-runner
@test "test/run: an unknown tier prints the usage and exits 2" {
  suite bogus
  assert_failure 2
  assert_output --partial "usage: test/run"
}

# bats test_tags=feature:test-runner
@test "test/run: a test file that hangs is killed after the time limit and fails the run" {
  put a.bats true
  put b.bats 'mkfifo "$BATS_TEST_TMPDIR/never"; read -r line <>"$BATS_TEST_TMPDIR/never"'
  suite TEST_FILE_TIMEOUT=3 --
  assert_failure 1
  assert_output --partial "test/quick/b.bats: took longer than 3 s and was killed"
  assert_equal "$(last_line)" "FAIL 1 of 2"
}

# bats test_tags=feature:test-runner
@test "test/run: more files than slots all run and are all counted" {
  for i in 1 2 3 4 5 6 7; do put "f$i.bats" true; done
  put bad.bats false
  suite TEST_JOBS=3 --
  assert_failure 1
  assert_equal "$(last_line)" "FAIL 1 of 8"
}

# bats test_tags=feature:test-runner
@test "test/run: a check that bash 3.2 would silently ignore is refused" {
  put not.bats '! true'
  put brackets.bats '[[ a == b ]]'
  put fine.bats '[[ a == a ]] || false'
  suite
  assert_failure 1
  assert_output --partial "not.bats:3: a bare !"
  assert_output --partial "brackets.bats:3: a bare !"
  refute_output --partial "fine.bats:3"
}

# own <coverage line...>: the case's own features.txt
own() { printf '%s\n' "$@" >"$R/test/features.txt"; : >"$R/own-list"; }
# tagged <file> <id> <count>: a file of <count> passing tests tagged feature:<id>
tagged() {
  local i=0
  : >"$R/test/quick/$1"
  while [ "$i" -lt "$3" ]; do
    printf '# bats test_%s=feature:%s\n@%s "case %s" {\n  true\n}\n' tags "$2" test "$i" >>"$R/test/quick/$1"
    i=$((i + 1))
  done
}

# bats test_tags=feature:test-runner
@test "test/run: a list that matches the tags passes, with manual and untested features beside them" {
  tagged a.bats alpha 2
  own "# comment" "alpha | A | feature:alpha=2" "beta | B | manual: bin/release/rehearsal.sh" "gamma | C | untested: needs Windows"
  suite
  assert_success
  assert_output --partial "features: list and tests agree"
}

# bats test_tags=feature:test-runner
@test "test/run: deleting one of a feature's tests fails the run and names the feature" {
  tagged a.bats alpha 1
  own "alpha | A | feature:alpha=2"
  suite
  assert_failure 1
  assert_output --partial "features: alpha: test/features.txt says 2 tests tagged feature:alpha, found 1"
}

# bats test_tags=feature:test-runner
@test "test/run: deleting a feature's last test fails the run and names the feature" {
  tagged a.bats alpha 1
  own "alpha | A | feature:alpha=1" "beta | B | feature:beta=1"
  suite
  assert_failure 1
  assert_output --partial "features: beta: no test is tagged feature:beta"
}

# bats test_tags=feature:test-runner
@test "test/run: a test with no feature tag, or an id the list lacks, fails the run" {
  tagged a.bats alpha 1
  printf '@%s "bare" {\n  true\n}\n' test >"$R/test/quick/b.bats"
  tagged c.bats stray 1
  own "alpha | A | feature:alpha=1"
  suite
  assert_failure 1
  assert_output --partial "features: test/quick/b.bats:1: a test with no feature tag"
  assert_output --partial "features: test/quick/c.bats:2: feature:stray names an id that is not in test/features.txt"
}

# bats test_tags=feature:test-runner
@test "test/run: untested with tagged tests, a bare reason, a bad line and a double id each fail the run" {
  tagged a.bats alpha 1
  own "alpha | A | untested: nobody yet" "beta | B | untested:" "gamma | C" "beta | B again | manual: x"
  suite
  assert_failure 1
  assert_output --partial "features: alpha: listed as untested: nobody yet but 1 tests are tagged feature:alpha"
  assert_output --partial "says nothing after the colon"
  assert_output --partial "features: test/features.txt:3: wanted"
  assert_output --partial "features: beta: listed twice"
}

# bats test_tags=feature:test-runner
@test "test/run: a missing features.txt fails the run" {
  tagged a.bats alpha 1
  : >"$R/own-list"
  suite
  assert_failure 1
  assert_output --partial "features: test/features.txt is missing"
}

# bats test_tags=feature:test-runner
@test "test/run: pytest files are counted by their feature comment and test functions" {
  tagged a.bats alpha 1
  mkdir -p "$R/skills/s/tests"
  printf '# feature:%s\ndef test_one():\n    pass\ndef test_two():\n    pass\n' py >"$R/skills/s/tests/test_s.py"
  own "alpha | A | feature:alpha=1" "py | P | feature:py=3"
  suite
  assert_failure 1
  assert_output --partial "features: py: test/features.txt says 3 tests tagged feature:py, found 2"
}

# bats test_tags=feature:test-runner
@test "assertions: --regexp reads the output as one string, the line helpers read it line by line" {
  output="$(printf 'first\nnot ok 2')"
  refute_output --regexp '^not ok '
  assert_output --regexp 'not ok [0-9]$'
  assert_a_line_matches '^not ok '
  refute_a_line_matches '^second'
  run assert_a_line_matches '^second'
  assert_failure
  output="$(printf 'first\nnot ok 2')"
  run refute_a_line_matches '^not ok '
  assert_failure
}

# bats test_tags=feature:test-runner
@test "test/run: skipped tests are counted on a line of their own" {
  put a.bats true
  put b.bats 'skip "macOS only"'
  suite
  assert_success
  assert_a_line_matches '^skipped 1 '
  assert_equal "$(last_line)" "PASS 2 tests"
}

# bats test_tags=feature:test-runner
@test "test/run: a quick test skipped for a missing tool is a failure" {
  put a.bats 'skip "node missing"'
  suite
  assert_failure 1
  assert_output --partial "test/quick/a.bats: 1 skipped for a missing tool"
  assert_equal "$(last_line)" "FAIL 1 of 1"
}

# bats test_tags=feature:test-runner
@test "test/run: a machine test may skip for a missing tool" {
  mkdir -p "$R/test/machine"
  put a.bats 'skip "node missing"'
  list
  mv "$R/test/quick/a.bats" "$R/test/machine/a.bats"
  : > "$R/own-list"
  suite machine
  assert_success
  assert_equal "$(last_line)" "PASS 1 tests"
}

# bats test_tags=feature:test-runner
@test "test/run: the regex operator is not a home folder; a tilde path after an equals sign is" {
  put a.bats 'v=a; [[ "$v" =~ a ]] || false'
  suite
  assert_success
  put a.bats "v=$(printf '\176')/x"
  suite
  assert_failure 1
  assert_output --partial "lint: test/quick/a.bats:3: "
}
