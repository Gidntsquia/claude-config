#!/usr/bin/env bash
# parse.py with nothing stubbed: the real `security`, the real TLS stack and the real usage API, in a throwaway
# home with a made-up login. Every other test replaces these three, which is how the Mac's "usage API always
# failed" (no CA bundle for python3, the token only in the Keychain) reached a real machine.
#
#   keychain  macOS: a temporary keychain in the throwaway home holds a fake "Claude Code-credentials" item;
#             parse.oauth_token() reads it through the real `security`
#   usage     Linux, macOS: parse.fetch_reset() with the fake token must end in HTTP 401 from the API.
#             Any SSL error, or any other answer, fails.
#
# Run: bash test/real-usage.sh [keychain|usage]   (no argument: both). bash 3.2, python3 standard library.
# The token is made up here and is never printed. The real keychain search list is compared before and after.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$R/skills/run-agent/scripts"
ONLY="${1:-}"
PASS=0; FAILS=0
ok()  { PASS=$((PASS+1)); echo "ok   $1"; }
bad() { FAILS=$((FAILS+1)); echo "FAIL $1"; }
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
REAL_HOME="$HOME"
MAC=false; [ "$(uname -s)" = Darwin ] && MAC=true
H="$(mktemp -d "${TMPDIR:-/tmp}/cc-real-usage.XXXX")"
trap 'rm -rf "$H"' EXIT
real_keychains() { HOME="$REAL_HOME" security list-keychains -d user 2>&1 && HOME="$REAL_HOME" security default-keychain 2>&1; }
KC_WAS=""; $MAC && KC_WAS="$(real_keychains)"
FAKE="sk-ant-oat01-not-a-real-token-$$-$(date +%s)"
unset RUN_AGENT_USAGE_FILE RUN_AGENT_NOW RUN_AGENT_NO_RETRY
export RUN_AGENT_CRED_FILE="$H/no-such-credentials.json"   # the token can only come from the Keychain

if $MAC; then
  KC="$H/Library/Keychains/login.keychain-db"
  mkdir -p "$H/Library/Keychains"
  err="$(HOME="$H" security create-keychain -p "" "$KC" 2>&1 && HOME="$H" security unlock-keychain -p "" "$KC" 2>&1 \
    && HOME="$H" security list-keychains -d user -s "$KC" 2>&1 && HOME="$H" security default-keychain -d user -s "$KC" 2>&1 \
    && HOME="$H" security add-generic-password -s "Claude Code-credentials" -a "test" -A \
         -w "{\"claudeAiOauth\":{\"accessToken\":\"$FAKE\",\"expiresAt\":4102444800000}}" "$KC" 2>&1)" \
    || { bad "keychain: could not build the temporary keychain in $H: $err"; }
fi

if want keychain; then
  if $MAC; then
    got="$(HOME="$H" FAKE="$FAKE" python3 -c '
import os, sys
sys.path.insert(0, sys.argv[1])
import parse
t = parse.oauth_token()
print("match" if t == os.environ["FAKE"] else "no token" if not t else "another token")' "$P" 2>&1)"
    [ "$got" = match ] && ok "keychain: parse.oauth_token() read the fake item from the temporary keychain through the real security" \
      || bad "keychain: parse.oauth_token() from the temporary keychain: $got"
  else echo "skip keychain: not macOS"; fi
fi

if want usage; then
  # Linux has no Keychain: the same fake token goes in the credentials file of the throwaway home.
  if ! $MAC; then
    export RUN_AGENT_CRED_FILE="$H/credentials.json"
    printf '{"claudeAiOauth":{"accessToken":"%s","expiresAt":4102444800000}}\n' "$FAKE" > "$RUN_AGENT_CRED_FILE"
  fi
  got="$(HOME="$H" python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import parse
epoch, why = parse.fetch_reset()
print("epoch %s" % epoch if epoch else why)' "$P" 2>&1)"
  got="$(printf '%s' "$got" | sed "s/$FAKE/<token>/g")"
  case "$got" in
    *SSL*|*CERTIFICATE*|*certificate*) bad "usage: the call failed in TLS, before the API could answer: $got" ;;
    "HTTPError: HTTP Error 401"*) ok "usage: the real API answered the fake token with 401 over verified TLS ($got)" ;;
    *) bad "usage: wanted HTTP 401 from the real API, got: $got" ;;
  esac
fi

if $MAC; then
  [ "$(real_keychains)" = "$KC_WAS" ] && ok "the real keychain search list and default keychain are as they were at the start" \
    || bad "the real keychain search list or default keychain changed during this run"
fi
echo; echo "$PASS passed, $FAILS failed"
[ "$FAILS" = 0 ]
