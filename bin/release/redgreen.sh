#!/bin/bash
# usage: /bin/bash bin/release/redgreen.sh [out dir]      (default out dir: plans/eval-checks/release; about 25 minutes)
# Also writes test/results/escapes.txt (the count in TESTING.md).
# The red runs for the 11 errors a real Mac showed in November 2026 (plans/research/mac-gaps-retrace.md). For each
# error: a scratch clone of this repo at HEAD with that error's fix taken out (the non-test files put back as they
# were before the fix), and the error's own test run from that clone. A test that stays green with its fix removed
# does not test the fix. Writes red.log to the out dir: one "## row <error>: <n> FAIL line(s)" block per run.
# Nothing here touches the real clone or ~/.claude: every test runs in its own throwaway home. Commit first: the
# scratch clones hold HEAD, not uncommitted files. macOS (rows 1d and 5 need its keychain and defaults).
set -u
R="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$R/plans/eval-checks/release}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
X="$(mktemp -d "${TMPDIR:-/tmp}/cc-red.XXXX")"; trap 'rm -rf "$X"' EXIT
LOG="$OUT/red.log"; : > "$LOG"
say() { printf '%s\n' "$*" >> "$LOG"; }
fresh() { cd "$X" || exit 1; rm -rf "$X/c"; git clone -q "$R" "$X/c" || exit 1; cd "$X/c" || exit 1; }
# row <id> <what was undone> <test command, shown> ; then stdin = the test's output
row() {
  local out n; out="$(cat)"; n="$(printf '%s\n' "$out" | grep -c '^FAIL')"
  say ""; say "## row $1: $n FAIL line(s)"; say "undone: $2"; say "test:   $3"
  printf '%s\n' "$out" | grep -A1 '^FAIL' | grep -v '^--$' | cut -c1-400 >> "$LOG"
  printf '%s\n' "$out" | tail -1 | sed 's/^/last line: /' >> "$LOG"
}
BATS="$R/test/vendor/bats-core/bin/bats"; [ -f "$BATS" ] || BATS="$(command -v bats)"
# FAIL counts are per test: each failing `not ok` line is one.
scn() { SCN_NEED_OLDTAG=1 "$BATS" --tap "test/quick/install-$1.bats" 2>&1 | sed 's/^not ok/FAIL/'; }
run_agent_tests() { "$BATS" --tap test/quick/run-agent-*.bats 2>&1 | sed 's/^not ok/FAIL/'; }
unpatch() { local c="$1"; shift; git diff "$c^" "$c" -- "$@" | git apply -R --3way >/dev/null 2>&1 || { say "!! could not reverse $c on $*"; return 1; }; }

say "red runs, $(TZ=America/New_York date '+%Y-%m-%d %I:%M %p ET'), repo at $(git -C "$R" rev-parse --short HEAD)"
say "each row: a scratch clone with the fix's non-test files put back as they were before the fix; tests are HEAD's"

# 1a, 1c, 1e: install.sh and bin/find-personal-paths.sh as they were before 503d16a
fresh; git show 503d16a^:install.sh > install.sh; git show 503d16a^:bin/find-personal-paths.sh > bin/find-personal-paths.sh
U="install.sh and bin/find-personal-paths.sh as before 503d16a"
scn sep22  | row 1a "$U" "bats test/quick/install-sep22.bats"
say "note: oldtag (R10) stays green with this install.sh: v1.2.1's installer does not make the Sep 22 layout (~/.claude/hooks as one link into the clone) that 1a needs, so 1a's red is sep22; oldtag's red is row 1d"
scn moved  | row 1c "$U" "bats test/quick/install-moved.bats"
scn theirs | row 1e "$U" "bats test/quick/install-theirs.bats"
# 1c, the new case: install.sh as before 60279af (broken links of a moved clone not counted when choosing defaults)
fresh; git show 60279af^:install.sh > install.sh
scn moved  | row "1c (no claude-config.json)" "install.sh as before 60279af" "bats test/quick/install-moved.bats"
# 1b: settings.json as before 01304e8 (hook commands end in exit 2 when the script is missing)
fresh; git show 01304e8^:settings.json > settings.json
scn noguard | row 1b "settings.json as before 01304e8" "bats test/quick/install-noguard.bats"
scn nohook  | row "1b (every hook command)" "settings.json as before 01304e8" "bats test/quick/install-nohook.bats"
# 1d: the iTerm2 undo taken out of install.sh (it predates 503d16a, so the lines are cut here)
fresh; python3 - <<'PY'
import re
s = open("install.sh").read()
n = s.count("defaults delete com.googlecode.iterm2 PrefsCustomFolder")
s = s.replace("defaults delete com.googlecode.iterm2 PrefsCustomFolder", ": no-undo")
s = re.sub(r"defaults write com\.googlecode\.iterm2 LoadPrefsFromCustomFolder -bool false", ": no-undo", s)
open("install.sh", "w").write(s); print("cut", n)
PY
scn oldtag | row 1d "install.sh without its 'defaults delete ... PrefsCustomFolder' and 'LoadPrefsFromCustomFolder false' lines" "bats test/quick/install-oldtag.bats"
# 1d, the harm itself: UPDATING.md's copy-the-plist-out step left out of the update (SCN_NO_PLIST_STEP=1)
fresh
SCN_NO_PLIST_STEP=1 scn plist | row "1d (plist)" "UPDATING.md 'Coming from an install before v1.3' step 1, the copy of the plist out of the clone (SCN_NO_PLIST_STEP=1)" "bats test/quick/install-plist.bats"
# 5: the throwaway home built without a keychain (the keychain is made by the test script itself; SCN_NO_KEYCHAIN leaves it out)
fresh
SCN_NO_KEYCHAIN=1 scn fresh | row 5 "home_setup's keychain creation (SCN_NO_KEYCHAIN=1)" "SCN_NO_KEYCHAIN=1 bats test/quick/install-fresh.bats"
# 2: parse.py as before 65d6fc4 (no CA file, no Keychain read)
fresh; unpatch 65d6fc4 skills/run-agent/scripts/parse.py
"$BATS" --tap test/machine/real-usage.bats 2>&1 | sed 's/^not ok/FAIL/' | row 2 "65d6fc4's changes to parse.py" "bats test/machine/real-usage.bats"
# 1f: the macOS port of the scripts (ed031af) undone in runner.sh, launch.py, jobs.py, bin/run-agent
fresh; unpatch ed031af skills/run-agent/scripts/runner.sh skills/run-agent/scripts/launch.py skills/run-agent/scripts/jobs.py bin/run-agent
run_agent_tests | row 1f "ed031af's changes to runner.sh, launch.py, jobs.py, bin/run-agent (run-agent.sh no longer reverses cleanly; left as is)" "bats test/quick/run-agent-*.bats"
# 3: runner.sh as before 65d6fc4 (asks the usage API at fire time)
fresh; unpatch 65d6fc4 skills/run-agent/scripts/runner.sh
run_agent_tests | row 3 "65d6fc4's changes to runner.sh" "bats test/quick/run-agent-*.bats (cases 'sched: window run fires at its stored run_at')"
# 4: jobs.py as before 782ccc4 (id taken without a lock)
fresh; unpatch 782ccc4 skills/run-agent/scripts/jobs.py
run_agent_tests | row 4 "782ccc4's changes to jobs.py" "bats test/quick/run-agent-*.bats (cases 'handoff: 3 at once', 'jobs: 12 schedulers at once')"
# 6: Windows taken out of the workflow's test job
fresh; sed 's/, windows-latest]/]/' .github/workflows/install.yml > wf && cat wf > .github/workflows/install.yml
"$BATS" --tap test/quick/install-windows.bats 2>&1 | sed 's/^not ok/FAIL/' | row 6 "windows-latest taken out of the test job" "bats test/quick/install-windows.bats"
# windows-stale-copy: install.sh as before 499a98d (a rerun left old copies in place)
fresh; git show 499a98d^:install.sh > install.sh
"$BATS" --tap test/quick/install-windows.bats 2>&1 | sed 's/^not ok/FAIL/' | row windows-stale-copy "install.sh as before 499a98d" "bats test/quick/install-windows.bats"
# 6 as it was found, in CI
say ""; say "## row 6: run 44974710129 (workflow_dispatch on 655041c, Nov 21): the first Windows run after the beta.5 commits"
( cd "$R" && gh run view 44974710129 --json conclusion,event,headSha,jobs --jq '"conclusion \(.conclusion), event \(.event), commit \(.headSha[0:7])", (.jobs[] | "  \(.name): \(.conclusion)")' ) >> "$LOG" 2>&1
( cd "$R" && gh run view 44974710129 --log-failed 2>/dev/null ) | grep 'FAIL ' | cut -f1,3- | sed 's/[0-9T:.-]*Z //' | cut -c1-300 >> "$LOG"
# the count bin/release/trust-report reads: past errors (the tests' escape:<id> tags) with a row that went red
red=0; all=0
for id in $(grep -hE '^[[:space:]]*#[[:space:]]*bats[[:space:]]+(file|test)_tags=' "$R"/test/quick/*.bats "$R"/test/machine/*.bats "$R"/test/docker/*.bats | grep -oE 'escape:[A-Za-z0-9_-]+' | sed 's/^escape://' | sort -u); do
  all=$((all + 1))
  grep -qE "^## row $id( \([^)]*\))?: [1-9][0-9]* FAIL" "$LOG" && red=$((red + 1))
done
mkdir -p "$R/test/results"
{ echo "# bin/release/redgreen.sh, $(TZ=America/New_York date '+%Y-%m-%d %I:%M %p ET') on $(uname -s), commit $(git -C "$R" rev-parse --short HEAD)"
  grep '^## row ' "$LOG" | sed 's/^## //'; echo "red $red of $all"; } > "$R/test/results/escapes.txt"
say ""; say "red $red of $all"
say ""; say "done $(TZ=America/New_York date '+%I:%M %p ET')"
