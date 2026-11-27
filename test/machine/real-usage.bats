#!/usr/bin/env bats
# parse.py with nothing stubbed: the real `security`, the real TLS stack and the real usage API, in a
# throwaway home with a made-up login. The quick tier replaces all three, which is how the Mac's "usage API
# always failed" (no CA bundle for python3, the token only in the Keychain) reached a real machine.
# The token is made up here and never printed. From test/real-usage.sh.

load ../helpers/common

setup() {
  temp_home
  P="$REPO/skills/run-agent/scripts"
  FAKE="sk-ant-oat01-not-a-real-token-$$-$(date +%s)"
  unset RUN_AGENT_USAGE_FILE RUN_AGENT_NOW RUN_AGENT_NO_RETRY
  export FAKE RUN_AGENT_CRED_FILE="$TEST_HOME/no-such-credentials.json"   # on a Mac the token can only come from the Keychain
  KC_WAS=""
  if is_mac; then KC_WAS="$(real_keychains)"; fi
}

is_mac() { [ "$(uname -s)" = Darwin ]; }
# The search list and default keychain of the person running the suite: read before and after, never written.
real_keychains() { HOME="$REAL_HOME" security list-keychains -d user 2>&1 && HOME="$REAL_HOME" security default-keychain 2>&1; }
# A keychain of the test's own, inside the throwaway home, holding the fake "Claude Code-credentials" item.
make_keychain() {
  local kc="$TEST_HOME/Library/Keychains/login.keychain-db" pw="scratch-$$"
  mkdir -p "$TEST_HOME/Library/Keychains"
  security create-keychain -p "$pw" "$kc"
  security unlock-keychain -p "$pw" "$kc" >/dev/null 2>&1 || true   # a hosted runner may lock it; not this test's failure
  security set-keychain-settings "$kc"
  security list-keychains -d user -s "$kc"
  security default-keychain -d user -s "$kc"
  security add-generic-password -s "Claude Code-credentials" -a "test" -A \
    -w "{\"claudeAiOauth\":{\"accessToken\":\"$FAKE\",\"expiresAt\":4102444800000}}" "$kc"
}

# bats test_tags=feature:usage-api,escape:5
@test "macOS: parse.py reads the login token from the Keychain through the real security" {
  if ! is_mac; then skip "not macOS: only a Mac has a Keychain"; fi
  make_keychain
  run python3 -c '
import os, sys
sys.path.insert(0, sys.argv[1])
import parse
t = parse.oauth_token()
print("match" if t == os.environ["FAKE"] else "no token" if not t else "another token")' "$P"
  assert_output "match"
  assert_equal "$(real_keychains)" "$KC_WAS"
}

# bats test_tags=feature:usage-api,escape:2
@test "the real usage API answers a made-up token with HTTP 401 over verified TLS" {
  if is_mac; then make_keychain
  else
    # No Keychain off a Mac: the same fake token goes in the credentials file of the throwaway home.
    export RUN_AGENT_CRED_FILE="$TEST_HOME/credentials.json"
    printf '{"claudeAiOauth":{"accessToken":"%s","expiresAt":4102444800000}}\n' "$FAKE" > "$RUN_AGENT_CRED_FILE"
  fi
  run python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import parse
epoch, why = parse.fetch_reset()
print("epoch %s" % epoch if epoch else why)' "$P"
  output="${output//$FAKE/<token>}"
  refute_output --regexp 'SSL|CERTIFICATE|certificate'
  assert_output --regexp '^HTTPError: HTTP Error 401'
  if is_mac; then assert_equal "$(real_keychains)" "$KC_WAS"; fi
}
