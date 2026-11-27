# temp_home: give the test a home of its own under $BATS_TEST_TMPDIR and export it as HOME and TEST_HOME.
# Tests write "$TEST_HOME"; the lint in test/run refuses `$HOME` and `~` outside this file, so no test can
# read or change the home of the person running the suite.
temp_home() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME"
  export TEST_HOME HOME="$TEST_HOME"
}
