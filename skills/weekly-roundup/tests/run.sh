#!/usr/bin/env bash
# One command: run.sh  -> docker setup, image, S1-S4 in two containers, check.py, Firefox.
#   run.sh --interactive   (Req 12 fallback) open one terminal per container; you run the scenarios.
# Each claude -p run spends real tokens on this account.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd)"; SKILL="$(dirname "$T")"; OUT="$T/out"
if [ "$(id -u)" = 0 ]; then R() { "$@"; }; elif sudo -n true 2>/dev/null; then R() { sudo "$@"; }; else R() { wsl.exe -u root -- "$@"; }; fi
if docker info >/dev/null 2>&1; then D() { docker "$@"; }; else D() { R docker "$@"; }; fi
CREDS="$HOME/.claude/.credentials.json"
SK=/root/.claude/skills/weekly-roundup
CREATED=()
log() { echo "[$(date +%H:%M:%S)] $*"; }

"$T/setup_docker.sh" >/dev/null || { echo "docker setup failed"; exit 1; }
D build -q -t roundup-test -f "$T/Dockerfile" "$SKILL" >/dev/null || exit 1
python3 "$T/make_fixtures.py" --expected "$T/expected.json" || exit 1
if [ -z "${ONLY:-}" ]; then R rm -rf "$OUT"; else R rm -rf "$OUT/$ONLY"; fi; mkdir -p "$OUT"

start() {  # fresh containers; credentials copied in at start, never into the image
  for m in a b; do
    D rm -f "machine-$m" >/dev/null 2>&1
    D run -d --name "machine-$m" --hostname "machine-$m" roundup-test >/dev/null || exit 1
    D exec "machine-$m" mkdir -p /root/.claude
    D cp "$CREDS" "machine-$m:/root/.claude/.credentials.json"
    D exec "machine-$m" chmod 600 /root/.claude/.credentials.json
    if [ -f "$HOME/.claude.json" ]; then   # only the account fields claude needs to log in
      python3 -c 'import json,os;j=json.load(open(os.path.expanduser("~/.claude.json")));k={x:j[x] for x in ("oauthAccount","userID") if x in j};k["hasCompletedOnboarding"]=True;print(json.dumps(k))' > "$OUT/.cj.json"
      D cp "$OUT/.cj.json" "machine-$m:/root/.claude.json"; rm -f "$OUT/.cj.json"
    fi
    D exec "machine-$m" python3 "$SK/tests/make_fixtures.py" "$m" >/dev/null || exit 1
  done
}

cc() {  # cc <machine> <logfile> <prompt>  -- interactive claude in tmux inside the container (cc.sh);
  # headless `claude -p` has no Artifact tool. Prints the URL claude wrote to /tmp/cc.done.
  local u
  u=$(D exec "machine-$1" bash "$SK/tests/cc.sh" "/tmp/cc.log" "$3" 2>>"$2" | tail -1)
  D cp "machine-$1:/tmp/cc.log" "$2" >/dev/null 2>&1
  grep -Eo 'https://claude\.ai/[^ )>"]+' <<<"$u" | tail -1
}

PREAMBLE="Do not ask questions. The archive_url to use is the one in $SK/state.json, NOT the URL written in SKILL.md; use it everywhere SKILL.md mentions the archive. If a step needs a human, choose sensibly."

make_archive() {  # make_archive <scenario>: machine A publishes an empty throwaway archive
  local s="$1" u
  u=$(cc a "$OUT/$s/archive.log" "Build an empty Roundup Archive page and publish it as a NEW artifact (no url). Run: echo '[]' > $SK/archive_weeks.json && python3 $SK/build_archive.py --out /tmp/archive.html ; then publish /tmp/archive.html with the Artifact tool (icon: calendar, no capabilities). Print the artifact URL as the very last line, nothing after it.")
  [ -n "$u" ] || { echo "no archive URL for $s (see $OUT/$s/archive.log)"; return 1; }
  CREATED+=("$s archive: $u"); ARCHIVE="$u"
  for m in a b; do
    D exec "machine-$m" bash -c "echo '{\"last_run\":\"2026-10-04\",\"last_artifact_url\":\"\",\"archive_url\":\"$u\",\"last_cap_usage_pct\":0}' > $SK/state.json; echo '[]' > $SK/archive_weeks.json"
  done
}

person_for() {  # person_for <machine> <run#>: A's usage is Jet, B's is Jaxon, spelled differently per run
  case "$1$2" in a1) echo "Jet";; a2) echo "jett";; a*) echo "jet Lee";; b1) echo "Jaxson";; b*) echo "jax";; esac
}

run_roundup() {  # run_roundup <scenario> <machine> <cap|keep>
  local s="$1" m="$2" cap="$3" capText u who
  if [ "$cap" = keep ]; then capText="No new cap-pct: keep the stored one (omit --cap-pct)."; else capText="cap-pct is $cap."; fi
  who=$(person_for "$m" "$RUN"); EXTRA=""
  [ "$s" = S4 ] && EXTRA=" Whatever the fixtures show, include exactly one \"Things fixed\" entry for this machine (first run: write one from the fixture commit history; rerun: rewrite it, replacing the old one listed in rewrite.fixed), with data-fixed-id on it. Quote the script's rewrite value verbatim in your report."
  u=$(cc "$m" "$OUT/$s/$m-$RUN.log" "$PREAMBLE Run /weekly-roundup for this week. $capText The usage on this machine belongs to: $who (pass exactly that text as --person). Assign features yourself.${EXTRA:-} Publish the week page (a joining run if the archive already lists this week) and update the archive. Write your full report to the user (what you replaced or added, as SKILL.md says) BEFORE the final step; then print the week page URL as the very last line, nothing after it.")
  RUN=$((RUN+1))
  [ -n "$u" ] || { echo "$s/$m: no URL (see log)"; return 1; }
  WEEK="$u"
}

fetch_week() {  # fetch_week <scenario>
  local s="$1"
  cc a "$OUT/$s/fetch.log" "Read the artifact $WEEK with the Artifact tool (action read), then run: cp <the saved file path from the result> /tmp/week.html . Print DONE as the last line." >/dev/null
  D cp machine-a:/tmp/week.html "$OUT/$s/week.html"
}

fetch_archive() {  # fetch_archive <scenario>: the throwaway archive page, to check the week is listed once
  local s="$1"
  cc a "$OUT/$s/fetch-archive.log" "Read the artifact $ARCHIVE with the Artifact tool (action read), then run: cp <the saved file path from the result> /tmp/archive-out.html . Print DONE as the last line." >/dev/null
  D cp machine-a:/tmp/archive-out.html "$OUT/$s/archive.html"
}

scenario() {  # scenario <name> "machine:cap" ...
  local s="$1"; shift; mkdir -p "$OUT/$s"; RUN=1
  log "== $s: $*"; start; make_archive "$s" || return 1
  for step in "$@"; do run_roundup "$s" "${step%%:*}" "${step##*:}" || return 1; done
  CREATED+=("$s week page: $WEEK")
  fetch_week "$s"
  [ "$s" = S4 ] && fetch_archive "$s"
  for m in a b; do last=$(ls "$OUT/$s"/$m-*.log 2>/dev/null | tail -1); [ -n "$last" ] && cp "$last" "$OUT/$s/$m.log"; done
}

if [ "${1:-}" = --interactive ]; then
  start
  for m in a b; do
    "$HOME/.claude/local-tools/term-open.sh" "machine$m" "$T" "wsl.exe -u root -- docker exec -it -e IS_SANDBOX=1 machine-$m claude --dangerously-skip-permissions"
  done
  echo "Run the three scenarios by hand in the two terminals, save week pages to out/S1..S3/week.html, then: python3 $T/check.py"
  exit 0
fi

# ONLY=S4 run.sh runs just that scenario (the others' week.html are then absent and check.py reports them)
want() { [ -z "${ONLY:-}" ] || [ "$ONLY" = "$1" ]; }
want S1 && scenario S1 a:40 b:55
want S2 && scenario S2 b:55 a:40
want S3 && scenario S3 a:40 b:55 a:keep
want S4 && scenario S4 a:40 a:keep

python3 "$T/check.py"; RC=$?
FF="/mnt/c/Program Files/Mozilla Firefox/firefox.exe"
[ -f "$OUT/S3/week.html" ] && "$FF" -new-window "$(wslpath -w "$OUT/S3/week.html")" &
echo; echo "Throwaway artifacts created (delete them yourself; nothing was deleted):"
printf '  %s\n' "${CREATED[@]}"
exit $RC
