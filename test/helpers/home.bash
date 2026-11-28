# temp_home: give the test a home of its own under $BATS_TEST_TMPDIR and export it as HOME and TEST_HOME.
# Tests write "$TEST_HOME"; the lint in test/run refuses `$HOME` and `~` outside this file, so no test can
# read or change the home of the person running the suite. REAL_HOME is the home the suite started in, for
# the few machine tests that must prove they left it alone.
temp_home() {
  [ -n "${REAL_HOME:-}" ] || REAL_HOME="$HOME"
  mkdir -p "$BATS_TEST_TMPDIR/home"
  TEST_HOME="$(cd "$BATS_TEST_TMPDIR/home" && pwd -P)"
  export REAL_HOME TEST_HOME HOME="$TEST_HOME"
}
