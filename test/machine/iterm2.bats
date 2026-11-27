#!/usr/bin/env bats
# iTerm2 on a real Mac. The first test needs a Mac without iTerm2, the second installs it, so they stay in
# this order in this file. Both change the account they run in, so they run on a CI runner only.

load ../helpers/common

ci_mac() { [ "$(uname -s)" = Darwin ] && { [ "${GITHUB_ACTIONS:-}" = true ] || [ "${ITERM2_LIVE:-}" = 1 ]; }; }

# bats test_tags=feature:terminal-setup
@test "macOS: --terminal with iTerm2 absent skips the profile and --check still passes" {
  if ! ci_mac; then skip "changes the account's real setup: a CI Mac only (ITERM2_LIVE=1 to run anyway)"; fi
  if [ -d /Applications/iTerm.app ]; then skip "iTerm2 is installed: this case needs a Mac without it"; fi
  temp_home
  cd "$REPO"
  run /bin/bash test/stock-mac.sh ./install.sh --projects "$(printf '\176/files')" --terminal --default-profile --statusline squid --settings merge
  assert_output --partial "iTerm2 is not installed"
  run /bin/bash test/stock-mac.sh ./install.sh --check
  assert_success
}

# bats test_tags=feature:terminal-setup,escape:1d
@test "macOS: an update run while the real iTerm2 reads its preferences from the clone keeps its plist" {
  if ! ci_mac; then skip "changes the account's real iTerm2 preferences: a CI Mac only (ITERM2_LIVE=1 to run anyway)"; fi
  run /bin/bash "$REPO/test/iterm2-live.sh"
  refute_output --regexp '^FAIL '
  assert_success
}
