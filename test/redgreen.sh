#!/bin/bash
# usage: /bin/bash test/redgreen.sh [out dir]      (default out dir: plans/eval-checks/release; about 25 minutes)
# The red runs for the 11 errors a real Mac showed in November 2026 (plans/research/mac-gaps-retrace.md). For each
# error: a scratch clone of this repo at HEAD with that error's fix taken out (the non-test files put back as they
# were before the fix), and the error's own test run from that clone. A test that stays green with its fix removed
# does not test the fix. Writes red.log to the out dir: one "## row <error>: <n> FAIL line(s)" block per run.
# Nothing here touches the real clone or ~/.claude: every test runs in its own throwaway home. Commit first: the
# scratch clones hold HEAD, not uncommitted files. macOS (rows 1d and 5 need its keychain and defaults).
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$R/plans/eval-checks/release}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
X="$(mktemp -d "${TMPDIR:-/tmp}/cc-red.XXXX")"; trap 'rm -rf "$X"' EXIT
LOG="$OUT/red.log"; : > "$LOG"
TMUX_DIR="$(dirname "$(command -v tmux)")"
say() { printf '%s\n' "$*" >> "$LOG"; }
fresh() { cd "$X" || exit 1; rm -rf "$X/c"; git clone -q "$R" "$X/c" || exit 1; cd "$X/c" || exit 1; }
# row <id> <what was undone> <test command, shown> ; then stdin = the test's output
row() {
  local out n; out="$(cat)"; n="$(printf '%s\n' "$out" | grep -c '^FAIL')"
  say ""; say "## row $1: $n FAIL line(s)"; say "undone: $2"; say "test:   $3"
  printf '%s\n' "$out" | grep -A1 '^FAIL' | grep -v '^--$' | cut -c1-400 >> "$LOG"
  printf '%s\n' "$out" | tail -1 | sed 's/^/last line: /' >> "$LOG"
}
scn() { SCN_ONLY="$1" SCN_NEED_OLDTAG=1 /bin/bash test/install-scenarios.sh --terminal 2>&1; }
stock_testsh() { env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" TERM=xterm-256color LANG=en_US.UTF-8 PATH="/usr/bin:/bin:/usr/sbin:/sbin:$TMUX_DIR" /bin/bash skills/run-agent/scripts/test.sh 2>&1; }
unpatch() { local c="$1"; shift; git diff "$c^" "$c" -- "$@" | git apply -R --3way >/dev/null 2>&1 || { say "!! could not reverse $c on $*"; return 1; }; }

say "red runs, $(TZ=America/New_York date '+%Y-%m-%d %I:%M %p ET'), repo at $(git -C "$R" rev-parse --short HEAD)"
say "each row: a scratch clone with the fix's non-test files put back as they were before the fix; tests are HEAD's"

# 1a, 1c, 1e: install.sh and bin/find-personal-paths.sh as they were before 503d16a
fresh; git show 503d16a^:install.sh > install.sh; git show 503d16a^:bin/find-personal-paths.sh > bin/find-personal-paths.sh
U="install.sh and bin/find-personal-paths.sh as before 503d16a"
scn sep22  | row 1a "$U" "SCN_ONLY=sep22 test/install-scenarios.sh --terminal"
say "note: oldtag (R10) stays green with this install.sh: v1.2.1's installer does not make the Sep 22 layout (~/.claude/hooks as one link into the clone) that 1a needs, so 1a's red is sep22; oldtag's red is row 1d"
scn moved  | row 1c "$U" "SCN_ONLY=moved test/install-scenarios.sh --terminal"
scn theirs | row 1e "$U" "SCN_ONLY=theirs test/install-scenarios.sh --terminal"
# 1c, the new case: install.sh as before 60279af (broken links of a moved clone not counted when choosing defaults)
fresh; git show 60279af^:install.sh > install.sh
scn moved  | row "1c (no claude-config.json)" "install.sh as before 60279af" "SCN_ONLY=moved test/install-scenarios.sh --terminal"
# 1b: settings.json as before 01304e8 (hook commands end in exit 2 when the script is missing)
fresh; git show 01304e8^:settings.json > settings.json
scn noguard | row 1b "settings.json as before 01304e8" "SCN_ONLY=noguard test/install-scenarios.sh --terminal"
scn nohook  | row "1b (every hook command)" "settings.json as before 01304e8" "SCN_ONLY=nohook test/install-scenarios.sh --terminal"
# 1d: the iTerm2 undo taken out of install.sh (it predates 503d16a, so the lines are cut here)
fresh; python3 - <<'PY'
import re
s = open("install.sh").read()
n = s.count("defaults delete com.googlecode.iterm2 PrefsCustomFolder")
s = s.replace("defaults delete com.googlecode.iterm2 PrefsCustomFolder", ": no-undo")
s = re.sub(r"defaults write com\.googlecode\.iterm2 LoadPrefsFromCustomFolder -bool false", ": no-undo", s)
open("install.sh", "w").write(s); print("cut", n)
PY
scn oldtag | row 1d "install.sh without its 'defaults delete ... PrefsCustomFolder' and 'LoadPrefsFromCustomFolder false' lines" "SCN_ONLY=oldtag test/install-scenarios.sh --terminal"
# 1d, the harm itself: UPDATING.md's copy-the-plist-out step left out of the update (SCN_NO_PLIST_STEP=1)
fresh
SCN_ONLY=plist SCN_NEED_OLDTAG=1 SCN_NO_PLIST_STEP=1 /bin/bash test/install-scenarios.sh --terminal 2>&1 | row "1d (plist)" "UPDATING.md 'Coming from an install before v1.3' step 1, the copy of the plist out of the clone (SCN_NO_PLIST_STEP=1)" "SCN_ONLY=plist test/install-scenarios.sh --terminal"
# 5: the throwaway home built without a keychain (the keychain is made by the test script itself; SCN_NO_KEYCHAIN leaves it out)
fresh
SCN_ONLY=a SCN_NO_KEYCHAIN=1 /bin/bash test/install-scenarios.sh --terminal 2>&1 | row 5 "home_setup's keychain creation (SCN_NO_KEYCHAIN=1)" "SCN_ONLY=a test/install-scenarios.sh --terminal"
# 2: parse.py as before 65d6fc4 (no CA file, no Keychain read)
fresh; unpatch 65d6fc4 skills/run-agent/scripts/parse.py
test/run machine 2>&1 | sed 's/^not ok/FAIL/' | row 2 "65d6fc4's changes to parse.py" "test/run machine (test/machine/real-usage.bats)"
# 1f: the macOS port of the scripts (ed031af) undone in runner.sh, launch.py, jobs.py, bin/run-agent
fresh; unpatch ed031af skills/run-agent/scripts/runner.sh skills/run-agent/scripts/launch.py skills/run-agent/scripts/jobs.py bin/run-agent
stock_testsh | row 1f "ed031af's changes to runner.sh, launch.py, jobs.py, bin/run-agent (run-agent.sh no longer reverses cleanly; left as is)" "/bin/bash skills/run-agent/scripts/test.sh, PATH=/usr/bin:/bin:/usr/sbin:/sbin:<tmux>"
# 3: runner.sh as before 65d6fc4 (asks the usage API at fire time)
fresh; unpatch 65d6fc4 skills/run-agent/scripts/runner.sh
stock_testsh | row 3 "65d6fc4's changes to runner.sh" "/bin/bash skills/run-agent/scripts/test.sh (cases 'sched: window run fires at its stored run_at')"
# 4: jobs.py as before 782ccc4 (id taken without a lock)
fresh; unpatch 782ccc4 skills/run-agent/scripts/jobs.py
stock_testsh | row 4 "782ccc4's changes to jobs.py" "/bin/bash skills/run-agent/scripts/test.sh (cases 'handoff: 3 at once', 'jobs: 12 schedulers at once')"
# 6: no scratch copy: the red is the run that showed it
say ""; say "## row 6: run 44974710129 (workflow_dispatch on 655041c, Nov 21): the first Windows run after the beta.5 commits"
( cd "$R" && gh run view 44974710129 --json conclusion,event,headSha,jobs --jq '"conclusion \(.conclusion), event \(.event), commit \(.headSha[0:7])", (.jobs[] | "  \(.name): \(.conclusion)")' ) >> "$LOG" 2>&1
( cd "$R" && gh run view 44974710129 --log-failed 2>/dev/null ) | grep 'FAIL ' | cut -f1,3- | sed 's/[0-9T:.-]*Z //' | cut -c1-300 >> "$LOG"
say ""; say "done $(TZ=America/New_York date '+%I:%M %p ET')"
