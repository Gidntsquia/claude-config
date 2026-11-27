# Loaded by every .bats file:   load ../helpers/common
# Gives assert_* and refute_* (bats-assert), assert_file_* (bats-file), temp_home, wait_until, run_legacy and $REPO.
REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export REPO TZ=UTC LC_ALL=C

# The three libraries are submodules in test/vendor/. Until they are added, the few assertions the tests use
# come from test/helpers/assert-fallback.bash (same names, same arguments).
if [ -f "$REPO/test/vendor/bats-support/load.bash" ] && [ -f "$REPO/test/vendor/bats-assert/load.bash" ] && [ -f "$REPO/test/vendor/bats-file/load.bash" ]; then
  load "$REPO/test/vendor/bats-support/load"
  load "$REPO/test/vendor/bats-assert/load"
  load "$REPO/test/vendor/bats-file/load"
else
  load "$REPO/test/helpers/assert-fallback"
fi
load "$REPO/test/helpers/home"
load "$REPO/test/helpers/wait"
load "$REPO/test/helpers/legacy"
