# Loaded by every .bats file:   load ../helpers/common
# Gives assert_* and refute_* (bats-assert), assert_file_* (bats-file), temp_home, wait_until and $REPO.
REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export REPO TZ=UTC LC_ALL=C

load "$REPO/test/vendor/bats-support/load"
load "$REPO/test/vendor/bats-assert/load"
load "$REPO/test/vendor/bats-file/load"
load "$REPO/test/helpers/home"
load "$REPO/test/helpers/wait"
