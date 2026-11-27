#!/usr/bin/env bats
# The five-hour window reset when the usage API is unreachable or answers 429, and where the API token comes from.
# Frozen clock 2026-10-22 6:00 PM ET; the fake API resets at 8:20 PM ET.
load ../helpers/common
load ../helpers/run-agent

setup() {
  ra_setup; ra_clock; export RUN_AGENT_NO_RETRY=1
  P="$RA_SRC/parse.py"
  A=$(( RUN_AGENT_NOW + 18000 ))
  AT9='"at":1792717200,"at_text":"at 9pm","at_shown":"9:00 PM ET (at 9pm, in 3h 0m)","run":"S worker . --at 1792717200 --at-text '"'"'at 9pm'"'"'"'
  ASSUMED_WIN="{\"at\":$A,\"at_text\":\"after window\",\"at_shown\":\"11:00 PM ET assumed (now + 5 h) (after window, in 5h 0m)\",\"reset\":$A,\"reset_shown\":\"11:00 PM ET (assumed (now + 5 h))\",\"reset_note\":\"assumed (now + 5 h)\",\"run\":\"S worker . --at $A --at-text 'after window' --window\"}"
}
teardown() { ra_teardown; }

# bats file_tags=feature:run-agent

# one live answer, which run-agent saves in its state folder
prime_cache() { ra --parse 'worker at 9pm' >/dev/null 2>&1 && [ -s "$RUN_AGENT_HOME/usage-reset.json" ]; }
# no cached reset: a state folder of its own, session transcripts under <1>
nocache() { local p="$1"; shift; RUN_AGENT_HOME="$T/home-nocache" RUN_AGENT_PROJECTS="$p" RUN_AGENT_USAGE_FILE="status:429" "$@"; }
# a session transcript: <timestamp> <file mtime epoch>
session() { mkdir -p "$T/proj/x" "$T/proj-empty"; printf '{"type":"x","timestamp":"%s"}\n' "$1" > "$T/proj/x/a.jsonl"; mtime "$2" "$T/proj/x/a.jsonl"; }
# does oauth_token() return <want>? prints yes or no, never the token
tokis() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parse; print("yes" if parse.oauth_token() == (sys.argv[2] or None) else "no")' "$RA_SRC" "$1"; }
# a fake Keychain command (records each call), one that cannot read, a fresh and an expired credentials file
creds() {
  mkdir -p "$T/secbin" "$T/nosec"
  printf '#!/bin/sh\necho called >> "%s"\n[ "$1 $2 $3 $4" = "find-generic-password -s Claude Code-credentials -w" ] || exit 9\necho "{\\"claudeAiOauth\\":{\\"accessToken\\":\\"tok-keychain-SECRET\\"}}"\n' "$T/sec.calls" > "$T/secbin/security"
  printf '#!/bin/sh\nexit 44\n' > "$T/nosec/security"
  chmod +x "$T/secbin/security" "$T/nosec/security"
  python3 -c 'import json,sys,time; json.dump({"claudeAiOauth":{"accessToken":"tok-file-SECRET","expiresAt":int((time.time()+3600)*1000)}}, open(sys.argv[1],"w")); json.dump({"claudeAiOauth":{"accessToken":"tok-old-SECRET","expiresAt":int((time.time()-86400)*1000)}}, open(sys.argv[2],"w"))' "$T/cred-fresh.json" "$T/cred-old.json"
}

# old: reset: live answer cached in the state dir (usage-reset.json)
@test "a live usage answer is cached in the state folder" {
  prime_cache
  run python3 -c "import json; print(json.load(open('$RUN_AGENT_HOME/usage-reset.json'))['reset'])"
  assert_output 1792714800
}

# old: time: after window with the API unreachable -> now + 5 h, assumed; the cached 8:20 PM is not used
@test "/run-agent after window with the usage API unreachable: now + 5 h, assumed, cache not used" {
  prime_cache
  RUN_AGENT_USAGE_FILE="$T/no-such-usage.json" pcheck 'worker after window' "$ASSUMED_WIN"
}

# old: time: after window with the API at 429 -> now + 5 h, assumed
@test "/run-agent after window with the usage API at 429: now + 5 h, assumed" {
  prime_cache
  RUN_AGENT_USAGE_FILE="status:429" pcheck 'worker after window' "$ASSUMED_WIN"
}

# old: reset: --window-reset with no live answer = now + 5 h, assumed (cache ignored)
@test "--window-reset with no live answer is now + 5 h, assumed, ignoring the cache" {
  prime_cache
  RUN_AGENT_USAGE_FILE="status:429" run python3 "$P" --window-reset
  assert_output "$A	assumed (now + 5 h)"
}

# old: reset: --window-reset live = the API reset rounded up to a whole second (…00.251 -> …01)
@test "--window-reset live is the API reset rounded up to a whole second" {
  run python3 "$P" --window-reset
  assert_output "1792714801	live"
}

# old: time: two hours before the window with the API at 429 -> cached reset, scheduled (session input)
@test "/run-agent two hours before the window uses the cached reset when the API says 429" {
  prime_cache
  RUN_AGENT_USAGE_FILE="status:429" pcheck 'worker fable low two hours before the window' \
    "{\"flags\":\"--model fable --effort low\",\"at\":1792707600,\"at_text\":\"two hours before the window\",\"at_shown\":\"6:20 PM ET (two hours before window 8:20 PM, cached, in 20m)\",\"reset\":1792714800,\"reset_shown\":\"8:20 PM ET (cached)\",\"reset_note\":\"cached\",\"command\":\"claude --agent worker \\\".\\\" --model fable --effort low --name \\\"worker: repo (fable)\\\"\",\"run\":\"S worker . --at 1792707600 --at-text 'two hours before the window' --at-shown '6:20 PM ET (two hours before window 8:20 PM, cached, in 20m)' -- --model fable --effort low\"}"
}

# old: time: at 9pm with the API at 429 -> reset shown as cached, no error text
@test "/run-agent at 9pm with the API at 429 shows the reset as cached" {
  prime_cache
  RUN_AGENT_USAGE_FILE="status:429" pcheck 'worker at 9pm' "{$AT9,\"reset\":1792714800,\"reset_shown\":\"8:20 PM ET (cached)\",\"reset_note\":\"cached\"}"
}

# old: time: 429 text never shown in --parse output
@test "/run-agent never shows the 429 error text" {
  prime_cache
  RUN_AGENT_USAGE_FILE="status:429" run ra --parse 'worker at 9pm dry'
  assert_success
  assert_output --partial '8:20 PM ET (cached)'
  refute_output --regexp 'HTTPError|429'

}

# old: reset: 429 retried (1 s + 3 s) then cached (4 s)
@test "a 429 answer is retried after 1 s and 3 s, then the cached reset is shown" {
  prime_cache
  local t0 dt
  t0=$(date +%s)
  run env -u RUN_AGENT_NO_RETRY RUN_AGENT_USAGE_FILE="status:429" python3 "$P" --reset-shown
  dt=$(( $(date +%s) - t0 ))
  assert_output "8:20 PM ET (cached)"
  [ "$dt" -ge 3 ]
  [ "$dt" -le 8 ]
}

# old: reset: no cache -> estimated from transcripts (session 2:30 PM, running) = 7:30 PM
@test "with no cache the reset is estimated from a running session" {
  session 2026-10-22T18:30:00.000Z "$RUN_AGENT_NOW"
  nocache "$T/proj" run python3 "$P" --reset-shown
  assert_output "7:30 PM ET (estimated from session activity)"
}

# old: reset: --window-reset ignores the session estimate (7:30 PM) -> now + 5 h, assumed
@test "--window-reset ignores the session estimate" {
  session 2026-10-22T18:30:00.000Z "$RUN_AGENT_NOW"
  nocache "$T/proj" run python3 "$P" --window-reset
  assert_output "$A	assumed (now + 5 h)"
}

# old: time: after window with a session estimate and no live answer -> now + 5 h, assumed
@test "/run-agent after window with only a session estimate: now + 5 h, assumed" {
  session 2026-10-22T18:30:00.000Z "$RUN_AGENT_NOW"
  nocache "$T/proj" pcheck 'worker after window' "$ASSUMED_WIN"
}

# old: token: file token not expired -> used, Keychain not read
@test "an unexpired credentials file token is used and the Keychain is not read" {
  creds
  PATH="$T/secbin:$PATH" RUN_AGENT_CRED_FILE="$T/cred-fresh.json" run tokis tok-file-SECRET
  assert_output yes
  assert_file_not_exist "$T/sec.calls"
}

# old: token: file token expired -> Keychain item "Claude Code-credentials"
@test "an expired file token falls back to the Keychain item" {
  creds
  PATH="$T/secbin:$PATH" RUN_AGENT_CRED_FILE="$T/cred-old.json" run tokis tok-keychain-SECRET
  assert_output yes
  [ -s "$T/sec.calls" ]
}

# old: token: no credentials file -> Keychain
@test "with no credentials file the Keychain token is used" {
  creds
  PATH="$T/secbin:$PATH" RUN_AGENT_CRED_FILE="$T/no-cred.json" run tokis tok-keychain-SECRET
  assert_output yes
}

# old: token: expired file, Keychain unreadable -> the file token (the API then decides)
@test "an expired file token is still used when the Keychain cannot be read" {
  creds
  PATH="$T/nosec:$PATH" RUN_AGENT_CRED_FILE="$T/cred-old.json" run tokis tok-old-SECRET
  assert_output yes
}

# old: token: neither -> none
@test "with neither a file nor a Keychain item there is no token" {
  creds
  PATH="$T/nosec:$PATH" RUN_AGENT_CRED_FILE="$T/no-cred.json" run tokis ''
  assert_output yes
}

# old: tls: verified with /etc/ssl/cert.pem when present
@test "the usage API call verifies TLS with /etc/ssl/cert.pem when present" {
  grep -q 'cafile=CA_FILE if os.path.isfile(CA_FILE)' "$P"
  grep -q '^CA_FILE = "/etc/ssl/cert.pem"' "$P"
}

# old: reset: old sessions only -> now + 5 h, assumed
@test "with only old sessions the reset is now + 5 h, assumed" {
  session 2026-10-22T10:00:00.000Z $(( RUN_AGENT_NOW - 6*3600 - 1800 ))
  nocache "$T/proj" run python3 "$P" --reset-shown
  assert_output "11:00 PM ET (assumed: no window open, next message starts one)"
}

# old: reset: nothing at all -> now + 5 h, assumed
@test "with nothing known the reset is now + 5 h, assumed" {
  mkdir -p "$T/proj-empty"
  nocache "$T/proj-empty" run python3 "$P" --reset-shown
  assert_output "11:00 PM ET (assumed: no window open, next message starts one)"
}

# old: time: two hours before the window, nothing known -> assumed window, still scheduled
@test "/run-agent two hours before the window with nothing known still schedules from the assumed window" {
  mkdir -p "$T/proj-empty"
  nocache "$T/proj-empty" pcheck 'worker two hours before the window' \
    "{\"at\":$(( RUN_AGENT_NOW + 3*3600 )),\"at_text\":\"two hours before the window\",\"at_shown\":\"9:00 PM ET (two hours before window 11:00 PM, assumed: no window open, next message starts one, in 3h 0m)\",\"reset\":$A,\"reset_shown\":\"11:00 PM ET (assumed: no window open, next message starts one)\",\"reset_note\":\"assumed: no window open, next message starts one\",\"run\":\"S worker . --at $(( RUN_AGENT_NOW + 3*3600 )) --at-text 'two hours before the window' --at-shown '9:00 PM ET (two hours before window 11:00 PM, assumed: no window open, next message starts one, in 3h 0m)'\"}"
}
