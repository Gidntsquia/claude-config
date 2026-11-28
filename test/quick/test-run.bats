#!/usr/bin/env bats
# The runner itself and the release tools beside it (bin/release/faults, repeat, trust-report): what makes
# `PASS <n> tests` trustworthy. Each case runs a copy of them in a scratch repo that holds only the test files the
# case writes, so nothing here runs the real suite.
# The planted bad lines are built from pieces: the lint reads this file too.

load ../helpers/common

setup() {
  temp_home
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/test/quick" "$R/test/helpers"
  # the runner these cases exercise: this repo's, or the one `bin/release/faults test-runner` planted a fault in
  UNDER="${TEST_RUNNER_UNDER_TEST:-$REPO/test}"
  cp "$UNDER/run" "$R/test/run"
  cp -R "$UNDER/lib" "$R/test/lib"
  mkdir -p "$R/bin/release"
  cp "$UNDER/../bin/release/faults" "$UNDER/../bin/release/repeat" "$UNDER/../bin/release/trust-report" "$R/bin/release/"
  # the records every run checks (test/quick/records.bats)
  mkdir -p "$R/.claude"
  printf '## Decisions\n\n## Next\n' >"$R/ARCHITECTURE.md"
  echo "scratch" >"$R/.claude/CLAUDE.md"
}

# put <file under test/quick> <test body>: one test in a file of its own.
put() { printf '# bats file_%s=feature:x\n@%s "case" {\n  %s\n}\n' tags test "$2" >"$R/test/quick/$1"; }

# list: a features.txt that matches the scratch files, unless the case wrote its own
list() {
  [ -f "$R/own-list" ] && return 0
  echo "x | the scratch feature" >"$R/test/features.txt"
}

# A clean environment, so the inner bats does not read the outer run's BATS_* variables.
# suite [NAME=value ... --] [test/run arguments]
# tool <faults|repeat|trust-report> [NAME=value ... --] [arguments]: the same for a release tool
suite() {
  local bats vars=()
  while [ $# -gt 0 ]; do case "$1" in *=*) vars[${#vars[@]}]="$1"; shift ;; --) shift; break ;; *) break ;; esac; done
  bats="$REPO/test/vendor/bats-core/bin/bats"
  [ -f "$bats" ] || bats="$(PATH="${PATH#"$BATS_LIBEXEC:"}" command -v bats)"
  list
  # git and python3 are outside /usr/bin on Windows Git Bash (and python3 on some Macs)
  local t d tools=""
  for t in git python3; do d="$(command -v "$t")" && tools="$tools:$(dirname "$d")"; done
  run env -i PATH="$(dirname "$bats"):/usr/bin:/bin:/usr/sbin:/sbin$tools" ${SYSTEMROOT:+SYSTEMROOT="$SYSTEMROOT"} TMPDIR="$BATS_TEST_TMPDIR" HOME="$TEST_HOME" ${vars[@]+"${vars[@]}"} bash "$R/${TOOL:-test/run}" "$@"
}
tool() { local TOOL="bin/release/$1"; shift; suite "$@"; }

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
@test "test/run: a looped test that fails names the case it stopped at, in brackets on its FAILED line" {
  put a.bats 'for c in "at 9pm" "in 2h" "at noon"; do echo "case: $c"; [ "$c" != "in 2h" ]; done'
  put b.bats 'echo "case: passes"; true'
  put c.bats 'echo "no case line"; false'
  suite
  assert_failure 1
  assert_line "FAILED x: case [in 2h]"
  assert_line "FAILED x: case"
  assert_equal "$(printf '%s\n' "$output" | grep -c '^FAILED ')" 2
  assert_equal "$(last_line)" "FAIL 2 of 3"
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
  assert_output "usage: test/run [quick|machine|docker|all] | --only <feature>"
}

# bats test_tags=feature:test-runner
@test "test/run: the old modes and any extra argument print the usage and exit 2" {
  put a.bats true
  local args
  for args in "--faults" "--faults x" "--report" "all --report" "quick --repeat 2" "--agree f" "quick --seed 1" "--only" "--only x y" "quick machine"; do
    # shellcheck disable=SC2086
    suite $args
    assert_failure 2
    assert_output "usage: test/run [quick|machine|docker|all] | --only <feature>"
  done
}

# bats test_tags=feature:test-runner
@test "test/run: a failing run names each failed test with its feature just above the FAIL line" {
  tagged a.bats alpha 2
  printf '# bats test_%s=feature:beta\n@%s "beta: the total is right" {\n  false\n}\n' tags test >>"$R/test/quick/a.bats"
  printf '# bats file_%s=feature:gamma\n@%s "gamma works" {\n  false\n}\n@%s "gamma passes" {\n  true\n}\n' tags test test >"$R/test/quick/b.bats"
  own "alpha | A" "beta | B" "gamma | C"
  suite
  assert_failure 1
  assert_equal "$(printf '%s\n' "$output" | tail -n 3 | sort)" "$(printf '%s\n' "FAIL 2 of 5" "FAILED beta: beta: the total is right" "FAILED gamma: gamma works")"
  assert_equal "$(printf '%s\n' "$output" | grep -c '^FAILED ')" 2
}

# bats test_tags=feature:test-runner
@test "test/run: a failing pytest test is named with the feature of its file" {
  tagged a.bats alpha 1
  mkdir -p "$R/skills/s/tests" "$BATS_TEST_TMPDIR/py/pytest"
  printf '# feature:%s\ndef test_one():\n    assert 1 == 2\ndef test_two():\n    pass\n' py >"$R/skills/s/tests/test_s.py"
  own "alpha | A" "py | P"
  # pytest's own closing lines for that file, printed by a module of the same name: the scratch repo has no
  # project for uv to install the real one from
  : >"$BATS_TEST_TMPDIR/py/pytest/__init__.py"
  printf 'import sys\nprint("FAILED skills/s/tests/test_s.py::test_one - assert 1 == 2")\nprint("1 failed, 1 passed in 0.01s")\nsys.exit(1)\n' >"$BATS_TEST_TMPDIR/py/pytest/__main__.py"
  suite PYTHONPATH="$BATS_TEST_TMPDIR/py" --
  assert_failure 1
  assert_line "FAILED py: skills/s/tests/test_s.py::test_one"
  assert_equal "$(last_line)" "FAIL 1 of 3"
}

# bats test_tags=feature:test-runner
@test "test/run: a lint problem and a feature with no test each get a FAILED line" {
  put a.bats "sl""eep 1"
  own "x | X" "beta | B"
  suite
  assert_failure 1
  assert_line "FAILED lint: test/quick/a.bats:3: sleep: use wait_until <seconds> <command>"
  assert_line "FAILED features: beta has no test"
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
@test "test/run: a list whose features all have tests passes and says how many it counted" {
  tagged a.bats alpha 2
  tagged b.bats beta 1
  own "# comment" "alpha | A" "beta | B"
  suite
  assert_success
  assert_line "features: 2 features, 3 tests, every feature has one"
}

# bats test_tags=feature:test-runner
@test "test/run: a new tagged test passes with no other file edited, and so does deleting one" {
  tagged a.bats alpha 2
  own "alpha | A"
  suite
  assert_equal "$(last_line)" "PASS 2 tests"
  list_before="$(cat "$R/test/features.txt")"
  printf '# bats test_%s=feature:alpha\n@%s "a new case" {\n  true\n}\n' tags test >>"$R/test/quick/a.bats"
  suite
  assert_success
  assert_equal "$(last_line)" "PASS 3 tests"
  tagged a.bats alpha 1
  suite
  assert_success
  assert_equal "$(last_line)" "PASS 1 tests"
  assert_equal "$(cat "$R/test/features.txt")" "$list_before"
}

# bats test_tags=feature:test-runner
@test "test/run: deleting a feature's last test fails the run and names the feature" {
  tagged a.bats alpha 1
  own "alpha | A" "beta | B"
  suite
  assert_failure 1
  assert_line "features: beta has no test"
  assert_line "FAILED features: beta has no test"
}

# bats test_tags=feature:test-runner
@test "test/run: a test with no feature tag, or an id the list lacks, fails the run" {
  tagged a.bats alpha 1
  printf '@%s "bare" {\n  true\n}\n' test >"$R/test/quick/b.bats"
  tagged c.bats stray 1
  own "alpha | A"
  suite
  assert_failure 1
  assert_output --partial "features: test/quick/b.bats:1: a test with no feature tag"
  assert_output --partial "features: test/quick/c.bats:2: feature:stray names an id that is not in test/features.txt"
}

# bats test_tags=feature:test-runner
@test "test/run: a bad line, a row with a third column and a double id each fail the run" {
  tagged a.bats alpha 1
  own "alpha | A" "gamma" "alpha | A again" "delta | D | feature:delta=1"
  suite
  assert_failure 1
  assert_output --partial "features: test/features.txt:2: wanted"
  assert_output --partial "features: alpha: listed twice"
  assert_output --partial "features: test/features.txt:4: wanted"
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
@test "test/run: a pytest file's test functions count for the feature its comment names" {
  tagged a.bats alpha 1
  mkdir -p "$R/skills/s/tests"
  printf '# feature:%s\ndef test_one():\n    pass\ndef test_two():\n    pass\n' py >"$R/skills/s/tests/test_s.py"
  own "alpha | A" "py | P"
  suite
  assert_line "features: 2 features, 3 tests, every feature has one"
  own "alpha | A"
  suite
  assert_failure 1
  assert_output --partial "features: skills/s/tests/test_s.py: feature:py names an id that is not in test/features.txt"
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

# ---- one feature, and the release tools ----------------------------------------------------------------------------------------

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
  # as in the real repo: text stays LF in every clone, whatever the runner's autocrlf says (Windows)
  printf '* text eol=lf\n' >"$R/.gitattributes"
  g add .gitattributes app.sh test
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
  features_are "x | one" "y | two"
  suite --only x
  assert_success
  assert_equal "$(last_line)" "PASS 1 tests"
  suite --only y
  assert_failure 1
  suite --only nothing
  assert_failure 2
}

# bats test_tags=feature:test-runner
@test "bin/release/faults: counts the faults the tests catch, names the missed one and leaves the repo as it was" {
  fault_repo
  fault wrong-total "total 3" "total 4"
  fault no-total 'echo "total 3"' ':'
  fault extra-gone '"extra"' '"gone"'
  before="$(g status --porcelain)$(g rev-parse HEAD)"
  tool faults x
  assert_failure 1
  assert_line "caught x/no-total"
  assert_line "caught x/wrong-total"
  assert_line "missed x/extra-gone"
  assert_equal "$(last_line)" "caught 2 of 3"
  assert_equal "$(g status --porcelain)$(g rev-parse HEAD)" "$before"
  assert_file_not_exist "$R/test/results/faults.txt"
}

# bats test_tags=feature:test-runner
@test "bin/release/faults: all caught exits 0 and a full run records the result" {
  fault_repo
  fault one "total 3" "total 4"
  fault two "total 3" "total 5"
  fault three "total 3" "sum 3"
  tool faults
  assert_success
  assert_equal "$(last_line)" "caught 3 of 3"
  assert_equal "$(tail -n 1 "$R/test/results/faults.txt")" "caught 3 of 3"
}

# bats test_tags=feature:test-runner
@test "bin/release/faults: fewer than three faults, a patch that edits tests and one that does not apply all fail" {
  fault_repo
  fault edits-test "case a.bats" "case b" test/quick/a.bats
  printf -- '--- a/app.sh\n+++ b/app.sh\n@@ -1 +1 @@\n-nothing like this\n+x\n' >"$R/test/faults/x/stale.patch"
  tool faults x
  assert_failure 1
  assert_line "error x/edits-test: a fault may not edit test/"
  assert_output --partial "error x/stale: the patch does not apply"
  assert_line "short x: 2 of 3 faults planted"
  assert_equal "$(last_line)" "caught 0 of 2"
}

# bats test_tags=feature:test-runner
@test "bin/release/repeat: passing runs agree, each under its own seed, and the result is recorded" {
  put a.bats true
  list
  tool repeat TEST_SEED=40 -- 3
  assert_success
  assert_line "seed 40 (3 runs; rerun the same orders with TEST_SEED=40)"
  assert_line "run 3 seed 42: PASS 1 tests"
  assert_equal "$(last_line)" "agreed 3 of 3"
  assert_equal "$(tail -n 1 "$R/test/results/repeat.txt")" "agreed 3 of 3"
}

# bats test_tags=feature:test-runner
@test "bin/release/repeat: with no TEST_SEED it picks a seed and prints it" {
  put a.bats true
  list
  tool repeat 1
  assert_success
  assert_a_line_matches '^seed [0-9]+ \(1 runs; rerun the same orders with TEST_SEED=[0-9]+\)$'
}

# bats test_tags=feature:test-runner
@test "bin/release/repeat: one run that differs lowers the count, fails and names the test" {
  put a.bats 'echo >>"$MARKS"; [ "$(wc -l <"$MARKS")" -ne 2 ]'
  list
  tool repeat MARKS="$BATS_TEST_TMPDIR/marks" TEST_SEED=1 -- 3
  assert_failure 1
  assert_line "run 2 seed 2: FAIL 1 of 1 [x: case;]"
  assert_equal "$(last_line)" "agreed 2 of 3"
}

# bats test_tags=feature:test-runner
@test "bin/release/repeat: no number, or a word for one, prints its usage and exits 2" {
  tool repeat
  assert_failure 2
  tool repeat many
  assert_failure 2
  assert_output "usage: bin/release/repeat <n> [<result file>...]"
}

# bats test_tags=feature:test-runner
@test "test/run: TEST_SEED decides the order of the files, is printed, and the same seed repeats it" {
  local f
  for f in a b c d e; do put "$f.bats" "echo $f >>\"\$ORDER\""; done
  list
  order() { rm -f "$BATS_TEST_TMPDIR/order"; suite ORDER="$BATS_TEST_TMPDIR/order" TEST_JOBS=1 TEST_SEED="$1" --; tr -d '\n' <"$BATS_TEST_TMPDIR/order"; }
  first="$(order 7)"
  assert_equal "$(order 7)" "$first"
  suite TEST_SEED=7 --
  assert_line "seed 7"
  all=""; for f in 1 2 3 4 5 6; do all="$all$(order "$f") "; done
  [ "$(printf '%s' "$all" | tr ' ' '\n' | grep . | sort -u | wc -l)" -gt 1 ]
  suite TEST_SEED=seven --
  assert_failure 2
}

# bats test_tags=feature:test-runner
@test "bin/release/repeat <n> <files>: adds up the runs of several result files against the planned number" {
  printf '# shard\nrun 1 seed 1: PASS 4 tests\nrun 2 seed 2: PASS 4 tests\nagreed 2 of 2\n' >"$BATS_TEST_TMPDIR/one"
  printf 'run 1 seed 3: PASS 4 tests\n' >"$BATS_TEST_TMPDIR/two"
  tool repeat 3 "$BATS_TEST_TMPDIR/one" "$BATS_TEST_TMPDIR/two"
  assert_success
  assert_equal "$(last_line)" "agreed 3 of 3"
  tool repeat 4 "$BATS_TEST_TMPDIR/one" "$BATS_TEST_TMPDIR/two"
  assert_failure 1
  assert_equal "$(last_line)" "agreed 3 of 4"
  printf 'run 1 seed 4: FAIL 1 of 4 [x]\n' >"$BATS_TEST_TMPDIR/two"
  tool repeat 3 "$BATS_TEST_TMPDIR/one" "$BATS_TEST_TMPDIR/two"
  assert_failure 1
  assert_equal "$(last_line)" "agreed 2 of 3"
}

# bats test_tags=feature:test-runner
@test "bin/release/trust-report: writes the five numbers between the marks and keeps the rest of TESTING.md" {
  mkdir -p "$R/test/results" "$R/test/machine"
  put a.bats true
  features_are "x | one" "y | two"
  printf '# %s file_tags=feature:x,escape:e1,standin:s1\n' bats >"$R/test/machine/m.bats"
  printf '# by hand, 11-27 on Test, commit abc\ncaught x/a\nmissed x/b\nshort y: 0 of 3 faults planted\ncaught 5 of 6\n' >"$R/test/results/faults.txt"
  printf '# by hand, 11-27 on Test, commit abc\nagreed 9 of 9\n' >"$R/test/results/repeat.txt"
  printf '# by hand, 11-27 on Test, commit abc\nred 1 of 1\n' >"$R/test/results/escapes.txt"
  printf 'above\n<!-- trust-report:start -->\nold\n<!-- trust-report:end -->\nbelow\n' >"$R/TESTING.md"
  tool trust-report
  assert_success
  run cat "$R/TESTING.md"
  assert_line "above"
  assert_line "below"
  [ "$(grep -c "^old$" "$R/TESTING.md")" = 0 ]
  assert_output --partial "| 1 of 2 features |"
  assert_output --partial "| 5 of 6 planted faults caught |"
  assert_output --partial "| 1 of 1 went red with the fix removed (1 have a test) |"
  assert_output --partial "| 9 of 9 shuffled runs agreed |"
  assert_output --partial "| 1 compared in the machine tier |"
  assert_output --partial "commit abc. Faults not caught: x/b y."
  assert_output --partial ". Measured: faults 11-27 on Test, commit abc; old bugs 11-27 on Test, commit abc; repeat 11-27 on Test, commit abc."
}

# bats test_tags=feature:test-runner
@test "bin/release/trust-report: names each replayed bug with its test, and gives each feature its counts before and now" {
  mkdir -p "$R/test/results"
  put a.bats true
  put b.bats true
  features_are "x | one" "y | two" "z | three"
  printf '# by hand, 11-27 on Test, commit abc\nrow e1: 2 FAIL line(s)\nbug e1 | the clock ran backwards | clock: it counts forwards\nred 1 of 1\n' >"$R/test/results/escapes.txt"
  printf '# a comment\nx | 7 | 3\ny | in x | 0\n' >"$R/test/results/before.txt"
  printf '<!-- trust-report:start -->\n<!-- trust-report:end -->\n' >"$R/TESTING.md"
  tool trust-report
  assert_success
  assert_line "| the clock ran backwards | clock: it counts forwards |"
  assert_line "| x | 7 | 3 | 2 | z | 0 | 0 | 0 |"
  assert_line "| y | in x | 0 | 0 | | | | |"
}

# bats test_tags=feature:test-runner
@test "bin/release/repeat <n> <files> with REPEAT_RECORD keeps each system's sum, and the trust report shows them side by side" {
  put a.bats true
  list
  printf 'run 1 seed 1: PASS 4 tests\nrun 2 seed 2: PASS 4 tests\n' >"$BATS_TEST_TMPDIR/one"
  tool repeat REPEAT_RECORD=macOS REPEAT_NOTE="CI run 7, 11-27, commit abc" -- 2 "$BATS_TEST_TMPDIR/one"
  assert_success
  assert_equal "$(last_line)" "agreed 2 of 2"
  assert_equal "$(head -n 1 "$R/test/results/repeat-macOS.txt")" "# bin/release/repeat 2, CI run 7, 11-27, commit abc"
  printf 'run 1 seed 1: PASS 4 tests\nrun 2 seed 2: FAIL 2 of 4 [x: the late one;y: a | b;]\nrun 3 seed 3: FAIL 1 of 4 [x: the late one;]\n' >"$BATS_TEST_TMPDIR/short"
  tool repeat REPEAT_RECORD=Ubuntu REPEAT_NOTE="CI run 7, 11-27, commit abc" -- 3 "$BATS_TEST_TMPDIR/short"
  assert_failure
  printf '<!-- trust-report:start -->\n<!-- trust-report:end -->\n' >"$R/TESTING.md"
  tool trust-report
  assert_success
  assert_output --partial "| Ubuntu agreed 1 of 3 (failed: x: the late one; y: a / b), macOS agreed 2 of 2 |"
  assert_output --partial "repeat on macOS CI run 7, 11-27, commit abc"
}

# bats test_tags=feature:test-runner
@test "bin/release/trust-report: repeated runs that all failed the same way are shown as failed" {
  put a.bats true
  list
  mkdir -p "$R/test/results"
  printf '# by hand, 11-27 on Test, commit abc\nrun 1 seed 1: FAIL 1 of 4 [x]\nrun 2 seed 2: FAIL 1 of 4 [x]\nagreed 2 of 2\n' >"$R/test/results/repeat.txt"
  printf '<!-- trust-report:start -->\n<!-- trust-report:end -->\n' >"$R/TESTING.md"
  tool trust-report
  assert_success
  assert_output --partial "| 2 of 2 shuffled runs agreed (2 of the runs failed) |"
}

# bats test_tags=feature:test-runner
@test "bin/release/trust-report: the three tables come first and the line saying when each was measured comes last" {
  mkdir -p "$R/test/results"
  put a.bats true
  features_are "x | one"
  printf '# by hand, 11-27 on Test, commit abc\nbug e1 | the clock ran backwards | clock: it counts forwards\nred 1 of 1\n' >"$R/test/results/escapes.txt"
  printf 'x | 7 | 3\n' >"$R/test/results/before.txt"
  printf '# Testing\n<!-- trust-report:start -->\n<!-- trust-report:end -->\n' >"$R/TESTING.md"
  tool trust-report
  assert_success
  run grep -n '^| Piece \|^| Old bug \|^| Feature | \|^Written by \|^<!-- trust-report:end' "$R/TESTING.md"
  assert_equal "$(printf '%s\n' "$output" | sed 's/^[0-9]*:\(.\{9\}\).*/\1/' | tr '\n' ',')" "| Piece |,| Old bug,| Feature,Written b,<!-- trus,"
  assert_equal "$(sed -n 3p "$R/TESTING.md")" "| Piece | Why it is kept | Today |"
}

# workflow_step <step name>: the script of that step of the CI workflow, with its ${{ }} values replaced by 1
workflow_step() {
  python3 -c '
import re, sys
sys.stdout.reconfigure(newline="\n")   # Windows would write CR LF, which bash reads as part of a command
lines = open(sys.argv[1]).read().split("\n")
i = lines.index("      - name: " + sys.argv[2])
assert lines[i + 1] == "        run: |", lines[i + 1]
for line in lines[i + 2:]:
    if not line.startswith("          "):
        break
    print(re.sub(r"\$\{\{.*?\}\}", "1", line[10:]))' "$REPO/.github/workflows/install.yml" "$1"
}
# as GitHub runs a step on Linux when the job names no shell: bash -e, in the checkout
run_step() {
  workflow_step "$1" >"$BATS_TEST_TMPDIR/step.sh"
  run bash -c 'cd "$1" && PATH=/usr/bin:/bin bash -e "$2"' _ "$R" "$BATS_TEST_TMPDIR/step.sh"
}

# bats test_tags=feature:test-runner
@test "weekly repeat job: passes at 300 passing runs on each system, fails when 300 failed the same way or a system is missing" {
  local i result os
  for result in "PASS 4 tests" "FAIL 1 of 4 [x]"; do
    for os in ubuntu-latest macos-latest; do
      mkdir -p "$R/shards/repeat-$os-0"
      i=0
      : >"$R/shards/repeat-$os-0/repeat.txt"
      while [ "$i" -lt 300 ]; do i=$((i + 1)); echo "run $i seed $i: $result" >>"$R/shards/repeat-$os-0/repeat.txt"; done
    done
    run_step "bin/release/repeat 300 (add up each system's shards)"
    assert_line "ubuntu-latest: agreed 300 of 300"
    assert_line "macos-latest: agreed 300 of 300"
    case "$result" in PASS*) assert_success ;; *) assert_failure ;; esac
  done
  i=0
  while [ "$i" -lt 300 ]; do i=$((i + 1)); echo "run $i seed $i: PASS 4 tests"; done >"$R/shards/repeat-ubuntu-latest-0/repeat.txt"
  rm -r "$R/shards/repeat-macos-latest-0"
  run_step "bin/release/repeat 300 (add up each system's shards)"
  assert_failure
  assert_line "ubuntu-latest: agreed 300 of 300"
}

# bats test_tags=feature:test-runner
@test "weekly repeat job: a shard that dies before finishing leaves no old result to upload" {
  mkdir -p "$R/test/results"
  echo "run 1 seed 1: PASS 4 tests" >"$R/test/results/repeat.txt"
  printf '#!/bin/bash\nexit 137\n' >"$R/bin/release/repeat"
  chmod +x "$R/bin/release/repeat"
  run_step "bin/release/repeat 30"
  assert_failure
  assert_file_not_exist "$R/test/results/repeat.txt"
}

# bats test_tags=feature:test-runner
@test "bin/release/trust-report: a TESTING.md without the marks is left alone and exits 2" {
  list
  echo "mine" >"$R/TESTING.md"
  tool trust-report
  assert_failure 2
  assert_equal "$(cat "$R/TESTING.md")" "mine"
}
