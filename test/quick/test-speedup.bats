#!/usr/bin/env bats
# The test-speedup skill's measure.sh on tiny fake test commands.

load ../helpers/common

setup() {
  temp_home
  M="$REPO/skills/test-speedup/scripts/measure.sh"
  FX="$REPO/test/fixtures/test-speedup"
  PROJ="$BATS_TEST_TMPDIR/proj"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp" FAKE_LOG="$BATS_TEST_TMPDIR/runner.log"
  unset RESULT_FILE CAP_SECONDS FAKE_STATUS
  mkdir -p "$TMPDIR" "$PROJ"
  cd "$PROJ"
}

measure() { bash "$M" "$@"; }
rspec_project() { echo 'gem "rspec"' > Gemfile; export PATH="$FX/rspec-bin:$PATH"; }

# bats test_tags=feature:test-speedup
@test "detect names the runner from the project's files" {
  for case in "go.mod::go" "Cargo.toml::rust" 'package.json:{"devDependencies":{"vitest":"1"}}:vitest' \
      'package.json:{"devDependencies":{"jest":"29"}}:jest' 'Gemfile:gem "rspec":rspec' "pom.xml::maven"; do
    file="${case%%:*}"; rest="${case#*:}"; want="${rest##*:}"; body="${rest%:*}"
    rm -f go.mod Cargo.toml package.json Gemfile pom.xml
    printf '%s\n' "$body" > "$file"
    run measure detect
    assert_success
    assert_output "$want"
  done
}

# bats test_tags=feature:test-speedup
@test "detect says unknown and exits 3 in a folder with no test runner" {
  run measure detect
  assert_failure 3
  assert_output "unknown"
}

# bats test_tags=feature:test-speedup
@test "time reports the command, its seconds and its failing status" {
  RESULT_FILE="$BATS_TEST_TMPDIR/result" run measure time -- bash -c 'echo ran-it; exit 7'
  assert_failure 7
  assert_output --partial "ran-it"
  assert_output --partial "CMD=bash -c echo ran-it; exit 7"
  assert_output --partial "EXIT=7"
  assert_output --regexp "WALL_SECONDS=[0-9]+"
  assert_equal "$(sed -n '1p;3,$p' "$BATS_TEST_TMPDIR/result")" "$(printf 'CMD=bash -c echo ran-it; exit 7\nEXIT=7\nDONE')"
  assert_file_not_exist "$TMPDIR/test-speedup.lock/pid"
}

# bats test_tags=feature:test-speedup
@test "time without a command prints its usage" {
  run measure time --
  assert_failure 2
  assert_output --partial "usage: measure.sh time -- <command...>"
}

# bats test_tags=feature:test-speedup
@test "a second run is refused while one is in flight" {
  run measure time -- bash "$M" time -- bash -c 'echo second-ran'
  assert_failure 4
  assert_output --partial "run already in flight (pid "
  refute_output --regexp "^second-ran"
  assert_output --partial "EXIT=4"
}

# bats test_tags=feature:test-speedup
@test "a lock left by a dead run is cleared and the command still runs" {
  bash -c 'exit 0' & dead=$!
  wait "$dead"
  mkdir "$TMPDIR/test-speedup.lock"
  echo "$dead" > "$TMPDIR/test-speedup.lock/pid"
  run measure time -- echo went-ahead
  assert_success
  assert_output --partial "clearing stale lock from pid $dead"
  assert_output --partial "went-ahead"
}

# bats test_tags=feature:test-speedup
@test "unlock removes the lock" {
  mkdir "$TMPDIR/test-speedup.lock"
  echo "$$" > "$TMPDIR/test-speedup.lock/pid"
  run measure unlock
  assert_success
  assert_output "lock cleared"
  assert_file_not_exist "$TMPDIR/test-speedup.lock/pid"
}

# bats test_tags=feature:test-speedup
@test "baseline reports time, status, count and the slowest tests from one run" {
  rspec_project
  RESULT_FILE="$BATS_TEST_TMPDIR/result" run measure baseline 2
  assert_success
  assert_output --partial "RUNNER=rspec"
  assert_output --regexp "WALL_SECONDS=[0-9]+"
  assert_output --partial "EXIT=0"
  assert_output --partial "COUNT=7"
  assert_output --partial "Cart adds an item"
  refute_output --partial "FAILURES"
  assert_equal "$(tail -1 "$BATS_TEST_TMPDIR/result")" "DONE"
  assert_equal "$(cat "$FAKE_LOG")" "exec rspec --profile 2"
}

# bats test_tags=feature:test-speedup
@test "baseline lists the failures and returns the runner's status" {
  rspec_project
  FAKE_STATUS=1 run measure baseline -- spec/cart_spec.rb
  assert_failure 1
  assert_output --partial "EXIT=1"
  assert_output --partial "$(printf 'FAILURES\n  1) Cart empties\nDONE')"
  assert_equal "$(cat "$FAKE_LOG")" "exec rspec --profile 25 spec/cart_spec.rb"
}

# bats test_tags=feature:test-speedup
@test "baseline reads the count and slowest times from Maven's XML reports" {
  touch pom.xml
  PATH="$FX/maven-bin:$PATH" run measure baseline 2
  assert_success
  assert_output --partial "COUNT=3"
  assert_equal "$(printf '%s\n' "$output" | sed -n '/^SLOWEST/,/^DONE/p' | cut -f1)" "$(printf 'SLOWEST\n9.50\n2.00\nDONE')"
}

# bats test_tags=feature:test-speedup
@test "run passes extra arguments to the runner and reports time and status" {
  rspec_project
  FAKE_STATUS=2 run measure run -- --tag fast
  assert_failure 2
  assert_output --partial "EXIT=2"
  assert_output --partial "DONE"
  assert_equal "$(cat "$FAKE_LOG")" "exec rspec --tag fast"
}

# bats test_tags=feature:test-speedup
@test "an unknown command prints the list of commands" {
  run measure frobnicate
  assert_failure 2
  assert_output --partial "usage: measure.sh {detect|baseline [N]|run|time -- <cmd>|count|profile|unlock}"
}
