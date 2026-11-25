#!/bin/bash
# usage: test/replay-page.sh [commit]      (default commit: HEAD; bash 3.2; needs gh and git)
# Builds plans/reports/release-replay.html for one commit from what was measured, with no status typed in by hand:
#   gh run list / gh run view      the install workflow's run of that commit: the macOS, Ubuntu, Windows and docker jobs
#   red.log (test/redgreen.sh)     for each of the 11 errors a real Mac showed, the FAIL count of the error's own
#                                  test with its fix taken out
#   rehearsal-out/<release>/       the two Docker rehearsals test/rehearsal.sh ran on this Mac
# The page opens with one banner. It is a green PASSED only when all four jobs of that commit are green, every one
# of the 11 errors has a red count above zero, and both rehearsals ran and passed. Anything else is a red FAILED
# with the reasons under it: a job that is red, still running or missing; a row with "no red proof"; a rehearsal
# that is FAIL or NOT RUN; a red.log or a rehearsal made from a commit that differs from this one in more than
# .md files. An error's row is green only when every job that runs its test is green.
# Prints the verdict and exits 0 for PASSED, 1 for FAILED, so a release script can stop on it.
#   REPLAY_RED_LOG   default plans/eval-checks/release/red.log
#   REPLAY_REHEARSAL default rehearsal-out
#   REPLAY_OUT       default plans/reports/release-replay.html
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
cd "$R" || exit 2
REPO="Gidntsquia/claude-config"
SHA="$(git rev-parse "${1:-HEAD}^{commit}" 2>/dev/null)" || { echo "replay-page.sh: no such commit: ${1:-HEAD}" >&2; exit 2; }
SHORT="$(git rev-parse --short "$SHA")"
RED="${REPLAY_RED_LOG:-$R/plans/eval-checks/release/red.log}"
REH="${REPLAY_REHEARSAL:-$R/rehearsal-out}"
OUT="${REPLAY_OUT:-$R/plans/reports/release-replay.html}"
mkdir -p "$(dirname "$OUT")"
T="$(mktemp -d "${TMPDIR:-/tmp}/replay-page.XXXX")"; trap 'rm -rf "$T"' EXIT
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
: > "$T/reasons"
reason() { printf '%s\n' "$*" >> "$T/reasons"; }
# same_but_docs <other commit>: that commit is this one, or differs from it only in .md files
same_but_docs() {
  local o; o="$(git rev-parse -q --verify "$1^{commit}" 2>/dev/null)" || return 1
  [ "$o" = "$SHA" ] && return 0
  [ -z "$(git diff --name-only "$o" "$SHA" | grep -v '\.md$')" ]
}

# ---- the runner jobs of this commit ---------------------------------------------------------------------------------
RUN_ID="$(gh run list --repo "$REPO" --commit "$SHA" --workflow install.yml --limit 20 --json databaseId,createdAt \
  --jq 'sort_by(.createdAt) | last | .databaseId // empty' 2>"$T/gh.err")"
: > "$T/jobs"; RUN_URL=""; RUN_WHEN=""
if [ -n "$RUN_ID" ]; then
  gh run view "$RUN_ID" --repo "$REPO" --json jobs --jq '.jobs[] | [.name, (if .status == "completed" then .conclusion else .status end), .url] | @tsv' > "$T/jobs" 2>>"$T/gh.err"
  RUN_URL="$(gh run view "$RUN_ID" --repo "$REPO" --json url --jq .url 2>>"$T/gh.err")"
  RUN_WHEN="$(gh run view "$RUN_ID" --repo "$REPO" --json createdAt --jq .createdAt 2>>"$T/gh.err")"
  # GitHub gives UTC; the page shows Eastern
  RUN_WHEN="$(TZ=America/New_York date -j -f '%Y-%m-%dT%H:%M:%SZ %z' "$RUN_WHEN +0000" '+%b %-d, %-I:%M %p ET' 2>/dev/null \
    || TZ=America/New_York date -d "$RUN_WHEN" '+%b %-d, %-I:%M %p ET' 2>/dev/null || echo "$RUN_WHEN")"
else
  reason "No run of the install workflow exists for commit $SHORT$( [ -s "$T/gh.err" ] && printf ' (gh: %s)' "$(head -1 "$T/gh.err")" )."
fi
job_pat() { case "$1" in macos) echo 'macos' ;; ubuntu) echo 'ubuntu' ;; windows) echo 'windows' ;; docker) echo '^docker' ;; esac; }
job_label() { case "$1" in macos) echo macOS ;; ubuntu) echo Ubuntu ;; windows) echo Windows ;; docker) echo Docker ;; esac; }
job_state() { local l; l="$(grep -i -m1 -e "$(job_pat "$1")" "$T/jobs" | cut -f2)"; echo "${l:-no run}"; }
job_url()   { grep -i -m1 -e "$(job_pat "$1")" "$T/jobs" | cut -f3; }
job_cell() {  # a link coloured by the job's state
  local st u cls; st="$(job_state "$1")"; u="$(job_url "$1")"; cls=bad; [ "$st" = success ] && cls=good
  if [ -n "$u" ]; then printf '<a class="%s" href="%s">%s: %s</a>' "$cls" "$u" "$(job_label "$1")" "$st"
  else printf '<span class="%s">%s: %s</span>' "$cls" "$(job_label "$1")" "$st"; fi
}
jobs_green=1
for j in macos ubuntu windows docker; do
  st="$(job_state "$j")"
  if [ "$st" != success ]; then jobs_green=0; [ -z "$RUN_ID" ] || reason "The $(job_label "$j") job of $SHORT is $st."; fi
done

# ---- the red runs ---------------------------------------------------------------------------------------------------
RED_HEAD=""; RED_SHA=""
if [ -f "$RED" ]; then
  RED_HEAD="$(head -1 "$RED")"; RED_SHA="$(printf '%s\n' "$RED_HEAD" | sed -n 's/.*repo at \([0-9a-f]*\).*/\1/p')"
  same_but_docs "${RED_SHA:-none}" || reason "red.log was made at ${RED_SHA:-an unknown commit}, which differs from $SHORT in more than .md files: run /bin/bash test/redgreen.sh at $SHORT."
else
  reason "There is no red.log ($RED): run /bin/bash test/redgreen.sh."
fi
# red_n <row name in red.log>: its FAIL count; empty when red.log has no such row
red_n() {
  [ -f "$RED" ] || return 0
  if [ "$1" = 6 ]; then
    grep -q '^## row 6' "$RED" || return 0
    awk '/^## row 6/{f=1; next} /^## row|^done /{f=0} f && /windows/ && /FAIL /{n++} END{print n+0}' "$RED"
  else
    grep -F -m1 -- "## row $1: " "$RED" | sed -n 's/.*: \([0-9][0-9]*\) FAIL line.*/\1/p'
  fi
}
red_undone() { [ -f "$RED" ] && awk -v h="## row $1: " 'index($0,h)==1{f=1; next} f && /^undone:/{sub(/^undone: */,""); print; exit}' "$RED"; }

# error | what the Mac showed | red.log rows (name=test, ';'-separated) | the jobs that run the test
cat > "$T/rows" <<'ROWS'
1a|install.sh linked hooks/usage-guard to itself; every hook failed|1a=scenario sep22|macos ubuntu docker
1b|A missing guard script blocked every tool|1b=scenario noguard;1b (every hook command)=scenario nohook|macos ubuntu windows docker
1c|A moved clone's broken links were counted as the user's own files|1c=scenario moved;1c (no claude-config.json)=scenario moved, saved choices missing|macos ubuntu docker
1d|A pull would have taken away the preferences file iTerm2 was using|1d=scenario oldtag;1d (plist)=scenario plist|macos ubuntu docker
1e|--check flagged files the user kept|1e=scenario theirs|macos ubuntu windows docker
1f|The run-agent tests failed 140 of 309 on a stock Mac|1f=test.sh under /bin/bash 3.2, stock PATH|macos
2|The usage API call always failed on macOS|2=test/real-usage.sh|macos ubuntu
3|An after-window job ran late or was skipped when the window rolled over|3=test.sh, 'sched: window run fires at its stored run_at'|macos ubuntu
4|Two jobs scheduled in the same second got the same job id|4=test.sh, 'handoff: 3 at once', 'jobs: 12 schedulers at once'|macos ubuntu
5|A Keychain Not Found dialog came from the tests' throwaway home|5=keychain_ready, scenario nokeychain|macos
6|The beta.5 changes broke the Windows job and nobody saw it for two days|6=the workflow itself, on every push and pull request|windows
ROWS
: > "$T/trs"; nrows=0; nred=0; ngreen=0
while IFS='|' read -r err seen tests proof; do
  nrows=$((nrows+1)); row_red=1; row_green=1; tcell=""; rcell=""; jcell=""
  printf '%s\n' "$tests" | tr ';' '\n' > "$T/tests"
  while IFS= read -r t <&3; do
    name="${t%%=*}"; what="${t#*=}"; n="$(red_n "$name")"
    if [ "$name" = 6 ]; then note="run 44974710129 of Nov 21, the first Windows run after the beta.5 commits"; else note="$(red_undone "$name")"; fi
    tcell="$tcell<code>$(printf '%s' "$what" | esc)</code><br>"
    if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then rcell="$rcell<b class=redn>$n FAIL</b> <span class=dim>$(printf '%s' "$note" | esc)</span><br>"
    else row_red=0; rcell="$rcell<b class=bad>no red proof</b> <span class=dim>$( [ -n "$n" ] && echo "the test stayed green with the fix removed" || echo "no such row in red.log" )</span><br>"
         reason "Error $err ($what): no red proof."; fi
  done 3< "$T/tests"
  for j in $proof; do [ "$(job_state "$j")" = success ] || row_green=0; jcell="$jcell$(job_cell "$j") "; done
  [ "$row_red" = 1 ] && nred=$((nred+1))
  cls=rowbad; verdict="red"; if [ "$row_green" = 1 ] && [ "$row_red" = 1 ]; then cls=rowgood; verdict="green"; ngreen=$((ngreen+1)); fi
  printf '<tr class=%s><td class=e>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class=v>%s</td></tr>\n' \
    "$cls" "$err" "$(printf '%s' "$seen" | esc)" "$tcell" "$rcell" "$jcell" "$verdict" >> "$T/trs"
done < "$T/rows"

# ---- the rehearsals -------------------------------------------------------------------------------------------------
# With the Keychain item present, every saved rehearsal file is searched for the token.
TOK="$(security find-generic-password -s claude-config-rehearsal -w 2>/dev/null || true)"
: > "$T/reh"; reh_pass=0
for from in v1.2.1 v1.3.0-beta.5; do
  D="$REH/$from"
  if [ ! -s "$D/results.txt" ] || [ ! -s "$D/summary.txt" ]; then
    reason "Rehearsal from $from: NOT RUN."
    printf '<h3>From %s: <b class=bad>NOT RUN</b></h3>\n<p>No results in <code>%s</code>. Run <code>test/rehearsal.sh</code> on this Mac; it needs Docker (Colima) and the Keychain item <code>claude-config-rehearsal</code>, and prints the two commands that make it when it is missing.</p>\n' \
      "$from" "$(printf '%s' "${D#$R/}" | esc)" >> "$T/reh"
    continue
  fi
  nok="$(grep -c '^ok' "$D/results.txt")"; nfail="$(grep -c '^FAIL' "$D/results.txt")"
  state=PASS; cls=good
  if [ "$nfail" != 0 ] || [ "$(tail -1 "$D/summary.txt")" != "PASS: no manual fix was made" ]; then state=FAIL; cls=bad; reason "Rehearsal from $from: FAIL ($nfail FAIL line(s))."; fi
  rsha="$(sed -n 's/^release under test: \([0-9a-f]*\).*/\1/p' "$D/summary.txt" | head -1)"
  if ! same_but_docs "${rsha:-none}"; then state=FAIL; cls=bad; reason "Rehearsal from $from was run on ${rsha:-an unknown commit}, which differs from $SHORT in more than .md files."; fi
  if grep -q 'uncommitted files' "$D/summary.txt"; then state=FAIL; cls=bad; reason "Rehearsal from $from was run with uncommitted files in the clone."; fi
  tokline="the Keychain item is not on this Mac now, so the files were not searched again"
  if [ -n "$TOK" ]; then
    if grep -rqF -- "$TOK" "$D" 2>/dev/null; then state=FAIL; cls=bad; tokline="A SAVED FILE HOLDS THE TOKEN"; reason "Rehearsal from $from: a saved file holds the token."
    else tokline="searched every file in the folder for the token: 0 hits"; fi
  fi
  [ "$state" = PASS ] && reh_pass=$((reh_pass+1))
  rel="../../${D#$R/}"
  {
    printf '<h3>From %s: <b class=%s>%s</b></h3>\n<p class=dim>%s</p>\n' "$from" "$cls" "$state" "$(tr '\n' ' ' < "$D/summary.txt" | esc)"
    printf '<h4>His start state</h4><pre>%s</pre>\n' "$(esc < "$D/start-state.txt")"
    printf '<h4>The one sentence he pastes</h4><pre class=say>%s</pre>\n' "$(esc < "$D/sentence.txt")"
    printf '<h4>Transcript</h4><p><a href="%s/transcript.txt">%s/transcript.txt</a> (%s lines; %s)</p>\n' "$rel" "$(printf '%s' "${D#$R/}" | esc)" "$(wc -l < "$D/transcript.txt" | tr -d ' ')" "$tokline"
    printf '<h4>After Claude finished: %s PASS, %s FAIL</h4><ul class=res>\n' "$nok" "$nfail"
    grep -e '^ok' -e '^FAIL' "$D/results.txt" | esc | sed -e 's|^ok   \(.*\)$|<li class=p>PASS \1</li>|' -e 's|^FAIL \(.*\)$|<li class=f>FAIL \1</li>|'
    printf '</ul>\n'
  } >> "$T/reh"
done
unset TOK

# ---- the page -------------------------------------------------------------------------------------------------------
awk '!seen[$0]++' "$T/reasons" > "$T/reasons.u"
if [ -s "$T/reasons.u" ]; then VERDICT=FAILED; else VERDICT=PASSED; fi
NOW="$(TZ=America/New_York date '+%b %-d, %Y, %-I:%M %p ET')"
{
cat <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>v1.3.0 release replay</title>
<style>
body{font:15px/1.5 -apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1d1d1f;background:#fbfaf7;max-width:1180px;margin:28px auto;padding:0 20px}
h1{font-size:26px;margin:18px 0 4px} h2{font-size:20px;margin:38px 0 8px;border-bottom:1px solid #d9d4c7;padding-bottom:4px}
h3{font-size:17px;margin:26px 0 4px} h4{font-size:14px;margin:16px 0 4px;color:#444}
.banner{padding:16px 20px;border-radius:6px;color:#fff;font-size:17px}
.banner b{font-size:30px;letter-spacing:.04em;display:block}
.banner.FAILED{background:#b3261e} .banner.PASSED{background:#1a7f37}
.banner ul{margin:8px 0 0;padding-left:22px;font-size:15px}
table{border-collapse:collapse;width:100%;background:#fff} th,td{border:1px solid #d9d4c7;padding:7px 9px;vertical-align:top;text-align:left}
th{background:#efece3;font-size:13px} td.e{font-weight:700;white-space:nowrap}
tr.rowgood td.e,tr.rowgood td.v{background:#e3f3e7;color:#1a7f37} tr.rowbad td.e,tr.rowbad td.v{background:#fbe4e2;color:#b3261e}
td.v{font-weight:700}
code{font:12.5px ui-monospace,Menlo,monospace;background:#f1eee6;padding:1px 4px;border-radius:3px}
pre{font:12.5px/1.45 ui-monospace,Menlo,monospace;background:#fff;border:1px solid #d9d4c7;padding:10px;overflow:auto;white-space:pre-wrap}
pre.say{background:#eef4ff;border-color:#b8cdf0}
.dim{color:#6b6b6b;font-size:13px} .redn{color:#8a5a00} .good{color:#1a7f37} .bad{color:#b3261e}
a.good,a.bad,span.good,span.bad{display:inline-block;margin:0 6px 2px 0;white-space:nowrap;font-weight:600}
.jobs{background:#fff;border:1px solid #d9d4c7;padding:10px 14px;margin:14px 0;font-size:16px}
ul.res{list-style:none;padding:0;margin:0;font:12.5px/1.6 ui-monospace,Menlo,monospace} ul.res li.p{color:#1a7f37} ul.res li.f{color:#b3261e;font-weight:700}
</style></head><body>
HTML
printf '<div class="banner %s"><b>%s</b>' "$VERDICT" "$VERDICT"
if [ "$VERDICT" = PASSED ]; then
  printf 'Commit <code>%s</code>: all four runner jobs are green, all 11 errors have a red run, and both rehearsals passed.' "$SHORT"
else
  printf 'Commit <code>%s</code> is not ready to release. What is red:<ul>\n' "$SHORT"
  esc < "$T/reasons.u" | sed 's|^|<li>|; s|$|</li>|'
  printf '</ul>'
fi
printf '</div>\n<h1>v1.3.0 release replay</h1>\n'
printf '<p class=dim>Built %s by <code>test/replay-page.sh</code> for commit <code>%s</code>. Nothing on this page is typed in: the jobs come from <code>gh run view</code>, the red counts from <code>red.log</code>, the rehearsals from <code>rehearsal-out/</code>.</p>\n' "$NOW" "$SHORT"
printf '<h2>1. The four runner jobs of <code>%s</code></h2>\n<div class=jobs>' "$SHORT"
for j in macos ubuntu windows docker; do job_cell "$j"; printf ' '; done
if [ -n "$RUN_ID" ]; then printf '<br><span class=dim>Run <a href="%s">%s</a>, started %s. Each link opens that job on GitHub.</span>' "$RUN_URL" "$RUN_ID" "$RUN_WHEN"
else printf '<br><span class=dim>GitHub has no run of the install workflow for this commit. Push it, wait for the run, and build the page again.</span>'; fi
printf '</div>\n'
printf '<h2>2. The 11 errors my Mac showed: %s of %s have a red run, %s of %s rows are green</h2>\n' "$nred" "$nrows" "$ngreen" "$nrows"
printf '<p>Red: <code>test/redgreen.sh</code> made a scratch clone, put the named files back as they were before the fix, and ran the error&#39;s own test; the number is the count of FAIL lines, and a test that stays green without its fix reads <b class=bad>no red proof</b>. Runner jobs: the jobs of the commit above that run that test. A row is green only when it has its red runs and every one of its jobs is green.</p>\n'
printf '<p class=dim>%s</p>\n' "$(printf '%s' "${RED_HEAD:-no red.log}" | esc)"
printf '<table><tr><th>Error</th><th>What the Mac showed</th><th>Test</th><th>Red: fix removed</th><th>Runner jobs of %s</th><th>Row</th></tr>\n' "$SHORT"
cat "$T/trs"
printf '</table>\n'
printf '<h2>3. The rehearsals on this Mac, in Docker: %s of 2 passed</h2>\n' "$reh_pass"
printf '<p><code>test/rehearsal.sh</code> builds, in a fresh ubuntu:24.04 container, an older release installed by that release&#39;s own installer and then lived in: two commits of his own on <code>main</code> and a side branch, uncommitted edits, a <code>settings.json</code> line the release also changed, a skill link replaced by his own folder, session files, <code>history.jsonl</code>, a <code>plugins/</code> folder and a settings file under <code>~/.claude</code> that is his own copy. Then it pastes README&#39;s update sentence into <code>claude -p</code> and checks the result. The Claude login comes from this Mac&#39;s Keychain and goes to the container as an environment variable; nothing is stored on GitHub.</p>\n'
cat "$T/reh"
printf '</body></html>\n'
} > "$OUT"
echo "replay-page.sh: $VERDICT for $SHORT: jobs $(for j in macos ubuntu windows docker; do printf '%s=%s ' "$j" "$(job_state "$j")"; done); $nred of $nrows errors have a red run; $reh_pass of 2 rehearsals passed -> ${OUT#$R/}"
[ "$VERDICT" = PASSED ] || sed 's/^/  red: /' "$T/reasons.u"
[ "$VERDICT" = PASSED ]
