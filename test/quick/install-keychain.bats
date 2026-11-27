#!/usr/bin/env bats
# The install tests' own safety guards: no throwaway home without its own keychain on macOS (claude would otherwise
# put up the "Keychain Not Found" dialog on the real screen), and no --terminal run on WSL (it writes Windows keys).

load ../helpers/common
load ../helpers/install-bats

setup_file() { install_setup_file nokeychain; }
teardown_file() { install_teardown_file; }
mac_only() { [ "$(uname -s)" = Darwin ] || skip "keychains are a macOS case"; }

# bats test_tags=feature:install
@test "a throwaway home without a keychain: the run fails" {
  mac_only
  passed "nokeychain: the run fails"
}

# bats test_tags=feature:install
@test "a throwaway home without a keychain: the FAIL line names the home" {
  mac_only
  passed "nokeychain: the FAIL line names the home"
}

# bats test_tags=feature:install
@test "a throwaway home without a keychain: neither install.sh nor claude runs in it" {
  mac_only
  passed "nokeychain: neither install.sh nor claude ran in it"
}

# bats test_tags=feature:install
@test "nokeychain: the whole scenario ran to its end with no failed check" {
  mac_only
  ran_clean
}

# bats test_tags=feature:install
@test "on WSL the install tests refuse to run with --terminal" {
  temp_home
  run env WSL_DISTRO_NAME=pretend SCN_TERMFLAG=--terminal SCN_REAL_HOME="$TEST_HOME" SCN_OUT= \
    bash "$REPO/test/helpers/install-run.bash" a
  assert_failure 2
  assert_output --partial "install tests: refusing to run --terminal on WSL"
  refute_output --partial "== scenario"
}
