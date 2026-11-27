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

# bats test_tags=feature:usage-api,escape:5,standin:security
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
  assert_a_line_matches '^HTTPError: HTTP Error 401'
  if is_mac; then assert_equal "$(real_keychains)" "$KC_WAS"; fi
}

# bats test_tags=feature:usage-api
@test "the usage request trusts the system's certificates when Python itself finds none" {
  [ -f /etc/ssl/cert.pem ] || skip "this system has no /etc/ssl/cert.pem to fall back on"
  export RUN_AGENT_CRED_FILE="$TEST_HOME/credentials.json" RUN_AGENT_HOME="$TEST_HOME/run-agent"
  printf '{"claudeAiOauth":{"accessToken":"%s","expiresAt":4102444800000}}\n' "$FAKE" > "$RUN_AGENT_CRED_FILE"
  mkdir -p "$TEST_HOME/no-certs"
  : > "$TEST_HOME/no-certs.pem"
  # Python's own certificate store is empty here, and the request is looked at instead of sent
  SSL_CERT_FILE="$TEST_HOME/no-certs.pem" SSL_CERT_DIR="$TEST_HOME/no-certs" run python3 -c '
import io, sys, urllib.request
sys.path.insert(0, sys.argv[1])
import parse
def look(req, timeout=None, context=None, **kw):
    n = len(context.get_ca_certs()) if context else 0
    print("certificates trusted" if n else "no certificates trusted")
    return io.BytesIO(b"{}")
urllib.request.urlopen = look
parse.fetch_reset()' "$P"
  assert_success
  assert_output "certificates trusted"
}

# bats test_tags=feature:usage-api
@test "the window reset shown is the five-hour window's, not the weekly one" {
  export RUN_AGENT_USAGE_FILE="$TEST_HOME/usage.json" RUN_AGENT_HOME="$TEST_HOME/run-agent"
  export RUN_AGENT_NOW=1792706400   # 2026-10-22 18:00 ET
  printf '%s\n' '{"five_hour":{"utilization":40,"resets_at":"2026-10-23T00:20:00.251269+00:00"},"seven_day":{"utilization":10,"resets_at":"2026-10-27T12:00:00.000000+00:00"}}' > "$RUN_AGENT_USAGE_FILE"
  run python3 "$P/parse.py" --window-reset
  assert_success
  assert_output "$(printf '1792714801\tlive')"   # rounded up to a whole second
}
