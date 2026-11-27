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
put() { printf '@%s "case" {\n  %s\n}\n' test "$2" >"$R/test/quick/$1"; }

# A clean environment, so the inner bats does not read the outer run's BATS_* variables.
# suite [NAME=value ... --] [test/run arguments]
suite() {
  local bats vars=()
  while [ $# -gt 0 ]; do case "$1" in *=*) vars[${#vars[@]}]="$1"; shift ;; --) shift; break ;; *) break ;; esac; done
  bats="$REPO/test/vendor/bats-core/bin/bats"
  [ -f "$bats" ] || bats="$(PATH="${PATH#"$BATS_LIBEXEC:"}" command -v bats)"
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
  assert_output --regexp '^FAIL [0-9]+ of [0-9]+$'
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
  assert_output --partial "lint: test/quick/a.bats:2: sleep"
}

# bats test_tags=feature:test-runner
@test "test/run: a fixed wait spelled with its full path or in python is caught too" {
  put a.bats "/bin/sl""eep 1"
  put b.bats "python3 -c 'import time; time.sl""eep(1)'"
  suite
  assert_failure 1
  assert_output --partial "lint: test/quick/a.bats:2: sleep"
  assert_output --partial "lint: test/quick/b.bats:2: sleep"
}

# bats test_tags=feature:test-runner
@test "test/run: network, the real home, a bare skip and a fixed port each fail the run" {
  put net.bats "cu""rl https://example.invalid"
  put home.bats 'ls "$HO''ME"'
  put skip.bats "sk""ip"
  put port.bats "server --po""rt 8080"
  suite
  assert_failure 1
  assert_output --partial "net.bats:2: cu""rl or wget"
  assert_output --partial 'home.bats:2: $HO''ME'
  assert_output --partial "skip.bats:2: skip with no reason"
  assert_output --partial "port.bats:2: fixed port"
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
  assert_output --partial "not.bats:2: a bare !"
  assert_output --partial "brackets.bats:2: a bare !"
  refute_output --partial "fine.bats:2"
}
