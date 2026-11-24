#!/usr/bin/env bash
# usage: CLAUDE_CODE_OAUTH_TOKEN=... test/rehearsal.sh [out dir]      (default out dir: ./rehearsal-out)
# The dress rehearsal of an update on a machine with the user's own edits. In the Docker image that
# test/docker-install.sh builds, it makes the start state of the `dirty` scenario (the install.sh of an older
# release, then his edits: lines added to CLAUDE.md and an agent, a notes file, an edit to the settings file on a
# line the release changed, a skill link replaced with his own folder), then types README's update sentence into
# `claude -p` and lets Claude do the rest. Nothing is fixed by hand. Afterwards it runs the dirty scenario's
# checks: his edits are there, no conflict markers, the stash is empty, his folder is byte-identical, every other
# link points into the clone, --check passes.
#   REHEARSAL_FROM=v1.2.1|v1.3.0-beta.5   the release he starts from (default v1.2.1)
#   REHEARSAL_BUDGET_USD, REHEARSAL_MAX_TURNS   caps for the one claude run (default 5 and 80)
# Writes to the out dir: start-state.txt, sentence.txt, transcript.jsonl (claude's stream), transcript.txt (the
# same, readable), results.txt (ok/FAIL lines), summary.txt. Exits 0 only when every check passed.
# The release under test is this clone's HEAD plus its uncommitted files, served to his clone as tag v1.3.0 from a
# local repository whose path holds Gidntsquia/claude-config (UPDATING.md steps 2 and 3 look at both).
# --inside is the part that runs in the container; it also runs on any Linux or Mac with a logged-in token.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" != --inside ]; then
  OUT="${1:-$R/rehearsal-out}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"; chmod 777 "$OUT"
  [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || { echo "rehearsal.sh: CLAUDE_CODE_OAUTH_TOKEN is not set (make one with: claude setup-token)" >&2; exit 2; }
  command -v docker >/dev/null 2>&1 || { echo "rehearsal.sh: docker is not installed" >&2; exit 2; }
  IMG="$(bash "$R/test/docker-install.sh" --build-only)" || { echo "rehearsal.sh: the image did not build" >&2; exit 2; }
  docker run --rm -e CLAUDE_CODE_OAUTH_TOKEN -e REHEARSAL_FROM="${REHEARSAL_FROM:-v1.2.1}" \
    -e REHEARSAL_BUDGET_USD="${REHEARSAL_BUDGET_USD:-5}" -e REHEARSAL_MAX_TURNS="${REHEARSAL_MAX_TURNS:-80}" \
    -v "$OUT:/out" "$IMG" bash -lc 'cd ~/claude-config && bash test/rehearsal.sh --inside /out'
  exit $?
fi

OUT="${2:-$R/rehearsal-out}"; mkdir -p "$OUT"
FROM="${REHEARSAL_FROM:-v1.2.1}"
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || { echo "rehearsal.sh: CLAUDE_CODE_OAUTH_TOKEN is not set" >&2; exit 2; }
SCN_LIB=1 . "$R/test/install-scenarios.sh" --terminal
SENTENCE="$(sed -n 's/^To update, tell Claude: "\(.*\)"\. The steps.*/\1/p' "$R/README.md")"
[ -n "$SENTENCE" ] || { echo "rehearsal.sh: README.md has no 'To update, tell Claude: \"...\"' line" >&2; exit 2; }
H="$(mktemp -d "${TMPDIR:-/tmp}/cc-rehearsal.XXXX")"; H="$(cd "$H" && pwd -P)"; CUR_H="$H"
K="$H/files/claude-config"
{
  export HOME="$H" PATH="$H/.local/bin:$PATH"
  home_setup "$H" rehearsal || exit 1
  to="$(target_commit "$H/target")" || { echo "FAIL rehearsal: could not build the release commit"; exit 1; }
  # where his clone will look for the release: origin, with the commit under test as tag v1.3.0 and on main
  ORIGIN="$H/remotes/Gidntsquia/claude-config.git"
  mkdir -p "$(dirname "$ORIGIN")" && git init -q --bare "$ORIGIN" \
    && git -C "$H/target" push -q "$ORIGIN" "$to:refs/heads/main" --tags \
    && git -C "$ORIGIN" tag -f v1.3.0 "$to" >/dev/null || { echo "FAIL rehearsal: could not make the origin repository"; exit 1; }
  dirty_setup "$H" "$K" "$FROM" "$H/target" "$to" || exit 1
  git -C "$K" tag -d v1.3.0 >/dev/null 2>&1
  git -C "$K" remote set-url origin "$ORIGIN"
} > "$OUT/setup.txt" 2>&1
setup_fails=$fails
{
  echo "start: claude-config $FROM installed with its own install.sh ($(git -C "$K" describe --tags 2>&1)), Claude Code $(claude --version 2>&1 | head -1), $(uname -sm)"
  echo "origin: $(git -C "$K" remote get-url origin)   (latest release tag there: $(git -C "$K" ls-remote --tags --refs origin 'v*' | sed 's|.*/||' | grep -v -e '-' | sort -V | tail -1))"
  echo "his edits before the update, git status --porcelain in the clone:"; git -C "$K" status --porcelain | sed 's/^/  /'
  echo "git diff --stat:"; git -C "$K" diff --stat | sed 's/^/  /'
  echo "his own folder in place of a link: $(ls -ld "$H/.claude/skills/review-skill" | cut -c1-10) ~/.claude/skills/review-skill ($(ls "$H/.claude/skills/review-skill" | tr '\n' ' '))"
} > "$OUT/start-state.txt" 2>&1
printf '%s\n' "$SENTENCE" > "$OUT/sentence.txt"

cd "$H/files" || exit 1
t0=$(date +%s)
claude -p "$SENTENCE" --output-format stream-json --verbose --permission-mode bypassPermissions \
  --max-budget-usd "${REHEARSAL_BUDGET_USD:-5}" --max-turns "${REHEARSAL_MAX_TURNS:-80}" \
  < /dev/null > "$OUT/transcript.raw" 2> "$OUT/claude-stderr.txt"; crc=$?
t1=$(date +%s)
cd "$R" || exit 1
# the token must not reach a saved file; the home's own path is shortened to ~
"$PY" - "$OUT" "$H" <<'PYEOF'
import json, os, sys
out, home = sys.argv[1], sys.argv[2]
tok = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "")
def clean(s):
    if tok: s = s.replace(tok, "***")
    return s.replace(home, "~")
raw = clean(open(os.path.join(out, "transcript.raw"), encoding="utf-8", errors="replace").read())
open(os.path.join(out, "transcript.jsonl"), "w", encoding="utf-8").write(raw)
os.remove(os.path.join(out, "transcript.raw"))
p = os.path.join(out, "claude-stderr.txt"); open(p, "w").write(clean(open(p, errors="replace").read())) if os.path.exists(p) else None
lines = []
def cut(s, n=1500):
    s = s.strip()
    return s if len(s) <= n else s[:n] + "\n   ... (%d more characters)" % (len(s) - n)
for row in raw.splitlines():
    try: m = json.loads(row)
    except ValueError: continue
    t = m.get("type")
    if t == "assistant":
        for c in m.get("message", {}).get("content", []):
            if c.get("type") == "text" and c.get("text", "").strip():
                lines.append("CLAUDE: " + c["text"].strip())
            elif c.get("type") == "tool_use":
                i = c.get("input", {})
                lines.append("  RUNS %s: %s" % (c.get("name"), cut(str(i.get("command") or i.get("url") or i.get("file_path") or json.dumps(i)), 600)))
    elif t == "user":
        content = m.get("message", {}).get("content", [])
        for c in content if isinstance(content, list) else []:
            if c.get("type") == "tool_result":
                r = c.get("content")
                if isinstance(r, list): r = "\n".join(x.get("text", "") for x in r if isinstance(x, dict))
                lines.append("  GOT: " + cut(str(r or "")).replace("\n", "\n       "))
    elif t == "result":
        lines.append("END: %s, %s turns, $%.2f" % (m.get("subtype"), m.get("num_turns"), m.get("total_cost_usd") or 0))
open(os.path.join(out, "transcript.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
PYEOF

fails=0
{
  expect "rehearsal: claude -p exited 0 (got $crc)" test "$crc" = 0
  expect "rehearsal: the clone is at the release tag (git describe: $(git -C "$K" describe --tags --exact-match 2>&1))" test "$(git -C "$K" describe --tags --exact-match 2>&1)" = v1.3.0
  dirty_asserts "$H" "$K" "$to"
} > "$OUT/results.txt" 2>&1
fails=$((fails + setup_fails))
{
  echo "from $FROM, $(TZ=America/New_York date '+%Y-%m-%d %I:%M %p ET'), claude ran $((t1 - t0)) s and exited $crc"
  echo "$(grep -c '^ok' "$OUT/results.txt") ok, $(grep -c '^FAIL' "$OUT/results.txt") FAIL after the update; $setup_fails FAIL while building the start state"
  [ "$fails" = 0 ] && echo "PASS: no manual fix was made" || echo "FAIL"
} > "$OUT/summary.txt"
cat "$OUT/start-state.txt"; echo; echo "> $SENTENCE"; echo; grep -e '^ok' -e '^FAIL' "$OUT/results.txt"; echo; cat "$OUT/summary.txt"
rm -rf "$H"; CUR_H=""; [ -z "$KC_START" ] || rm -f "$KC_START"
[ "$fails" = 0 ]
