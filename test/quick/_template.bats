#!/usr/bin/env bats
# Copy to test/quick/<feature>.bats (a name starting with `_` is not run). Then:
#   1. name the test after what the user sees, and tag it with the feature's id from test/features.txt;
#   2. run `test/run` and see it fail before the code exists;
#   3. write the code, run `test/run` again.
# Quick-tier rules, checked by the lint in test/run: no sleep (wait_until), no network, no home but
# "$TEST_HOME", no fixed port, no skip without a reason.

load ../helpers/common

setup() {
  temp_home
}

# bats test_tags=feature:<id>
@test "install.sh --check prints PASS for every link after a fresh install" {
  run "$REPO/install.sh" --check
  assert_success
  assert_output --partial "PASS"
  refute_output --partial "FAIL"
}
