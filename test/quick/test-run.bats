#!/usr/bin/env bats
# The runner itself: what makes `PASS <n> tests` trustworthy. Each case runs a copy of test/run in a scratch
# repo that holds only the test files the case writes, so nothing here runs the real suite.
# The planted bad lines are built from pieces: the lint reads this file too.

load ../helpers/common

setup() {
  temp_home
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/test/quick" "$R/test/helpers"
  # the runner these cases exercise: this repo's, or the one `test/run --faults test-runner` planted a fault in
  UNDER="${TEST_RUNNER_UNDER_TEST:-$REPO/test}"
  cp "$UNDER/run" "$R/test/run"
  cp -R "$UNDER/lib" "$R/test/lib"
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

# ---- the trust modes ----------------------------------------------------------------------------------------

# mfile <file> <tags> <test body>
mfile() { printf '# bats file_%s=%s\n@%s "case %s" {\n  %s\n}\n' tags "$2" test "$1" "$3" >"$R/test/quick/$1"; }
features_are() { printf '%s\n' "$@" >"$R/test/features.txt"; : >"$R/own-list"; }
g() { git -C "$R" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
# a repo with one program, its feature x, and one test that reads what the program prints
fault_repo() {
  printf 'echo "total 3"\necho "extra"\n' >"$R/app.sh"
  mkdir -p "$R/test/faults/x"
  mfile a.bats feature:x '[ "$(bash "${BATS_TEST_DIRNAME}/../../app.sh" | head -n 1)" = "total 3" ]'
  list
  git init -q "$R"
  g add app.sh test
  g commit -qm start
}
# fault <name> <old line> <new line> [file]: a patch file made by git itself
fault() {
  local f="${4:-app.sh}"
  sed "s/$2/$3/" "$R/$f" >"$R/changed" && cp "$R/changed" "$R/$f" && rm "$R/changed"
  g diff -- "$f" >"$R/test/faults/x/$1.patch"
  g checkout -q -- "$f"
}

# bats test_tags=feature:test-runner
@test "test/run --only: runs the tests of that feature and no others" {
  mfile a.bats feature:x true
  mfile b.bats feature:y false
  features_are "x | one | feature:x=1" "y | two | feature:y=1"
  suite --only x
  assert_success
  assert_equal "$(last_line)" "PASS 1 tests"
  suite --only y
  assert_failure 1
  suite --only nothing
  assert_failure 2
}

# bats test_tags=feature:test-runner
@test "test/run --faults: counts the faults the tests catch, names the missed one and leaves the repo as it was" {
  fault_repo
  fault wrong-total "total 3" "total 4"
  fault no-total 'echo "total 3"' ':'
  fault extra-gone '"extra"' '"gone"'
  before="$(g status --porcelain)$(g rev-parse HEAD)"
  suite --faults x
  assert_failure 1
  assert_line "caught x/no-total"
  assert_line "caught x/wrong-total"
  assert_line "missed x/extra-gone"
  assert_equal "$(last_line)" "caught 2 of 3"
  assert_equal "$(g status --porcelain)$(g rev-parse HEAD)" "$before"
  assert_file_not_exist "$R/test/results/faults.txt"
}

# bats test_tags=feature:test-runner
@test "test/run --faults: all caught exits 0 and a full run records the result" {
  fault_repo
  fault one "total 3" "total 4"
  fault two "total 3" "total 5"
  fault three "total 3" "sum 3"
  suite --faults
  assert_success
  assert_equal "$(last_line)" "caught 3 of 3"
  assert_equal "$(tail -n 1 "$R/test/results/faults.txt")" "caught 3 of 3"
}

# bats test_tags=feature:test-runner
@test "test/run --faults: fewer than three faults, a patch that edits tests and one that does not apply all fail" {
  fault_repo
  fault edits-test "case a.bats" "case b" test/quick/a.bats
  printf -- '--- a/app.sh\n+++ b/app.sh\n@@ -1 +1 @@\n-nothing like this\n+x\n' >"$R/test/faults/x/stale.patch"
  suite --faults x
  assert_failure 1
  assert_line "error x/edits-test: a fault may not edit test/"
  assert_output --partial "error x/stale: the patch does not apply"
  assert_line "short x: 2 of 3 faults planted"
  assert_equal "$(last_line)" "caught 0 of 2"
}

# bats test_tags=feature:test-runner
@test "test/run --repeat: passing runs agree, each under its own seed, and the result is recorded" {
  put a.bats true
  list
  suite quick --repeat 3 --seed 40
  assert_success
  assert_line "run 3 seed 42: PASS 1 tests"
  assert_equal "$(last_line)" "agreed 3 of 3"
  assert_equal "$(tail -n 1 "$R/test/results/repeat.txt")" "agreed 3 of 3"
}

# bats test_tags=feature:test-runner
@test "test/run --repeat: one run that differs lowers the count and fails" {
  put a.bats 'echo >>"$MARKS"; [ "$(wc -l <"$MARKS")" -ne 2 ]'
  list
  suite MARKS="$BATS_TEST_TMPDIR/marks" -- quick --repeat 3 --seed 1
  assert_failure 1
  assert_equal "$(last_line)" "agreed 2 of 3"
}

# bats test_tags=feature:test-runner
@test "test/run --repeat: the seed decides the order of the files, and the same seed repeats it" {
  local f
  for f in a b c d e; do put "$f.bats" "echo $f >>\"\$ORDER\""; done
  list
  order() { rm -f "$BATS_TEST_TMPDIR/order"; suite ORDER="$BATS_TEST_TMPDIR/order" TEST_JOBS=1 -- quick --repeat "$2" --seed "$1"; tr -d '\n' <"$BATS_TEST_TMPDIR/order"; }
  first="$(order 7 1)"
  assert_equal "$(order 7 1)" "$first"
  all="$(order 7 6)"
  assert_equal "${#all}" 30
  [ "$(printf '%s' "$all" | fold -w 5 | sort -u | wc -l)" -gt 1 ]
}

# bats test_tags=feature:test-runner
@test "test/run --agree: adds up the runs of several result files" {
  printf '# shard\nrun 1 seed 1: PASS 4 tests\nrun 2 seed 2: PASS 4 tests\nagreed 2 of 2\n' >"$BATS_TEST_TMPDIR/one"
  printf 'run 1 seed 3: PASS 4 tests\n' >"$BATS_TEST_TMPDIR/two"
  suite --agree "$BATS_TEST_TMPDIR/one" "$BATS_TEST_TMPDIR/two"
  assert_success
  assert_equal "$(last_line)" "agreed 3 of 3"
  printf 'run 1 seed 4: FAIL 1 of 4 [x]\n' >"$BATS_TEST_TMPDIR/two"
  suite --agree "$BATS_TEST_TMPDIR/one" "$BATS_TEST_TMPDIR/two"
  assert_failure 1
  assert_equal "$(last_line)" "agreed 2 of 3"
}

# bats test_tags=feature:test-runner
@test "test/run --report: writes the five numbers between the marks and keeps the rest of TESTING.md" {
  mkdir -p "$R/test/results" "$R/test/machine"
  put a.bats true
  features_are "x | one | feature:x=1" "y | two | manual: by hand"
  printf '# %s file_tags=feature:x,escape:e1,standin:s1\n' bats >"$R/test/machine/m.bats"
  printf 'e1 | one\ne2 | two\n' >"$R/test/escapes.txt"
  printf 's1 | a | standin:s1\ns2 | b | none: no way\n' >"$R/test/standins.txt"
  printf '# by hand, 11-27 on Test, commit abc\ncaught 5 of 6\n' >"$R/test/results/faults.txt"
  printf '# by hand, 11-27 on Test, commit abc\nagreed 9 of 9\n' >"$R/test/results/repeat.txt"
  printf 'above\n<!-- trust-report:start -->\nold\n<!-- trust-report:end -->\nbelow\n' >"$R/TESTING.md"
  suite --report
  assert_success
  run cat "$R/TESTING.md"
  assert_line "above"
  assert_line "below"
  [ "$(grep -c "^old$" "$R/TESTING.md")" = 0 ]
  assert_line "| Features with automated tests | 1 of 2 | completeness |"
  assert_line '- `y`: manual: by hand'
  assert_line "| Planted faults caught | 5 of 6 | sensitivity |"
  assert_line "| Past real-machine errors with a test | 1 of 2 | fidelity |"
  assert_line "| Repeated shuffled runs that agreed | 9 of 9 | consistency |"
  assert_line "| Stand-ins with a test against the real tool | 1 of 2 | fidelity |"
}

# bats test_tags=feature:test-runner
@test "test/run --report: a TESTING.md without the marks is left alone and exits 2" {
  list
  echo "mine" >"$R/TESTING.md"
  suite --report
  assert_failure 2
  assert_equal "$(cat "$R/TESTING.md")" "mine"
}

# bats test_tags=feature:test-runner
@test "test/run: a past error with no test, or a stand-in with no machine test, fails the run" {
  put a.bats true
  list
  printf 'gone | was\n' >"$R/test/escapes.txt"
  printf 's1 | a | standin:s1\n' >"$R/test/standins.txt"
  suite
  assert_failure 1
  assert_line "features: no test is tagged escape:gone (test/escapes.txt)"
  assert_line "features: no machine test is tagged standin:s1 (test/standins.txt)"
}
