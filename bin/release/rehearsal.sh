#!/usr/bin/env bash
# usage: bin/release/rehearsal.sh [out dir]      (default out dir: ./rehearsal-out, which git ignores)
# The dress rehearsal of an update on a machine that has been lived in. It runs on this Mac, in Docker (Colima:
# `brew install colima docker && colima start`), and nowhere on GitHub. In the image that bin/release/docker-image.sh
# builds, it makes the start state of the `dirty` scenario (the install.sh of an older release; then two commits of
# his own on main and a side branch, lines added to CLAUDE.md and an agent, a notes file, an edit to the settings
# file on a line the release changed, a skill link replaced with his own folder, session files, history.jsonl and
# a plugins folder under ~/.claude, and a settings file there that is his own copy), then types README's update
# sentence into `claude -p` and lets Claude do the rest. Nothing is fixed by hand. Afterwards it runs the dirty
# scenario's checks: his commits, edits and ~/.claude files are there, no conflict markers, the stash is empty,
# every other link points into the clone, --check passes.
# One run per start release, v1.2.1 then v1.3.0-beta.5, each into <out dir>/<release>/.
#   REHEARSAL_FROM=v1.2.1|v1.3.0-beta.5   run only that one
#   REHEARSAL_BUDGET_USD, REHEARSAL_MAX_TURNS   caps for each claude run (default 5 and 80)
# The Claude login: a token made once with `claude setup-token` and kept in this Mac's Keychain under the service
# name claude-config-rehearsal. It is read here and handed to the container as an environment variable for that
# one run. It is never written to a file, never put on a command line and never sent to GitHub; every saved file
# is searched for it afterwards. With no such Keychain item the script exits 2 and prints the two commands.
# Each run writes: start-state.txt, sentence.txt, transcript.jsonl (claude's stream), transcript.txt (the same,
# readable), results.txt (ok/FAIL lines), summary.txt (last line PASS or FAIL). Exits 0 only when every check of
# every run passed.
# The release under test is this clone's HEAD plus its uncommitted files, served to his clone as tag v1.3.0 from a
# local repository whose path holds Gidntsquia/claude-config (UPDATING.md steps 2 and 3 look at both).
# --inside <out dir> is the part that runs in the container (CLAUDE_CODE_OAUTH_TOKEN set, one REHEARSAL_FROM).
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KC_SERVICE=claude-config-rehearsal
if [ "${1:-}" != --inside ]; then
  OUT="${1:-$R/rehearsal-out}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
  command -v security >/dev/null 2>&1 || { echo "rehearsal.sh: no 'security' command: the rehearsal runs on the Mac that holds the Keychain item" >&2; exit 2; }
  if ! TOK="$(security find-generic-password -s "$KC_SERVICE" -w 2>/dev/null)" || [ -z "$TOK" ]; then
    {
      echo "rehearsal.sh: no Keychain item named $KC_SERVICE, so no rehearsal was run."
      echo "Make the token once and save it (the second command asks for the token; paste it there):"
      echo "    claude setup-token"
      echo "    security add-generic-password -U -s $KC_SERVICE -a \"\$USER\" -w"
      echo "Then run: bin/release/rehearsal.sh"
    } >&2
    exit 2
  fi
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo "rehearsal.sh: docker is not answering (brew install colima docker && colima start)" >&2; exit 2; }
  IMG="$(bash "$R/bin/release/docker-image.sh" --build-only)" || { echo "rehearsal.sh: the image did not build" >&2; exit 2; }
  rc=0
  for FROM in ${REHEARSAL_FROM:-v1.2.1 v1.3.0-beta.5}; do
    O="$OUT/$FROM"; rm -rf "$O"; mkdir -p "$O"; chmod 777 "$O"
    echo "== rehearsal from $FROM -> $O"
    CLAUDE_CODE_OAUTH_TOKEN="$TOK" docker run --rm -e CLAUDE_CODE_OAUTH_TOKEN -e REHEARSAL_FROM="$FROM" \
      -e REHEARSAL_BUDGET_USD="${REHEARSAL_BUDGET_USD:-5}" -e REHEARSAL_MAX_TURNS="${REHEARSAL_MAX_TURNS:-80}" \
      -v "$O:/out" "$IMG" bash -lc 'cd ~/claude-config && bash bin/release/rehearsal.sh --inside /out' || rc=1
    # the token must be in no saved file
    if grep -rqF -- "$TOK" "$O" 2>/dev/null; then
      echo "FAIL rehearsal: a saved file holds the token" | tee -a "$O/results.txt"; echo "FAIL" >> "$O/summary.txt"; rc=1
    else
      echo "ok   rehearsal: no saved file holds the token" | tee -a "$O/results.txt"
    fi
  done
  unset TOK
  exit $rc
fi

OUT="${2:-$R/rehearsal-out}"; mkdir -p "$OUT"
( : > "$OUT/.w" ) 2>/dev/null && rm -f "$OUT/.w" || { echo "rehearsal.sh: cannot write to $OUT (with Colima the out dir must be under your home folder, which is what it shares with the container)" >&2; exit 2; }
FROM="${REHEARSAL_FROM:-v1.2.1}"
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || { echo "rehearsal.sh: CLAUDE_CODE_OAUTH_TOKEN is not set" >&2; exit 2; }
REAL_HOME="$HOME"; TERMFLAG=--terminal; . "$R/test/helpers/install-lib.bash"; . "$R/test/helpers/install-dirty.bash"
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
  echo "his own commits on main (the release has neither):"; git -C "$K" log --format='  %h %s' "$to..HEAD"
  echo "his side branch: my-experiments at $(git -C "$K" log -1 --format='%h %s' my-experiments)"
  echo "his edits before the update, git status --porcelain in the clone:"; git -C "$K" status --porcelain | sed 's/^/  /'
  echo "git diff --stat:"; git -C "$K" diff --stat | sed 's/^/  /'
  echo "his own folder in place of a link: $(ls -ld "$H/.claude/skills/review-skill" | cut -c1-10) ~/.claude/skills/review-skill ($(ls "$H/.claude/skills/review-skill" | tr '\n' ' '))"
  echo "his ~/.claude, lived in:"; ( cd "$H/.claude" && find projects history.jsonl plugins -type f | LC_ALL=C sort | sed 's/^/  /' )
  echo "~/.claude/settings.json is his own copy (not a link), with his keys: model $(jget "$H/.claude/settings.json" model), cleanupPeriodDays $(jget "$H/.claude/settings.json" cleanupPeriodDays)"
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
  expect "rehearsal: the clone has the tag v1.3.0 and it is the release under test" test "$(git -C "$K" rev-parse 'v1.3.0^{commit}' 2>&1)" = "$to"
  expect "rehearsal: main holds the release tag (git describe: $(git -C "$K" describe --tags 2>&1))" git -C "$K" merge-base --is-ancestor "$to" HEAD
  dirty_asserts "$H" "$K" "$to"
  # UPDATING.md's 1.2.1 -> 1.3 step: the run-agent MCP server starts with uv, and installing it is Claude's step, not his
  expect "rehearsal: uv is installed after the update ($(PATH="$H/.local/bin:$H/.cargo/bin:$PATH" command -v uv 2>&1))" env PATH="$H/.local/bin:$H/.cargo/bin:$PATH" uv --version
} > "$OUT/results.txt" 2>&1
fails=$((fails + setup_fails))
{
  echo "from $FROM, $(TZ=America/New_York date '+%Y-%m-%d %I:%M %p ET'), claude ran $((t1 - t0)) s and exited $crc"
  echo "release under test: $(git -C "$R" rev-parse HEAD 2>&1)$( [ -z "$(git -C "$R" status --porcelain 2>/dev/null)" ] || echo ' plus uncommitted files' )"
  echo "$(grep -c '^ok' "$OUT/results.txt") ok, $(grep -c '^FAIL' "$OUT/results.txt") FAIL after the update; $setup_fails FAIL while building the start state"
  [ "$fails" = 0 ] && echo "PASS: no manual fix was made" || echo "FAIL"
} > "$OUT/summary.txt"
cat "$OUT/start-state.txt"; echo; echo "> $SENTENCE"; echo; grep -e '^ok' -e '^FAIL' "$OUT/results.txt"; echo; cat "$OUT/summary.txt"
rm -rf "$H"; CUR_H=""; [ -z "$KC_START" ] || rm -f "$KC_START"
[ "$fails" = 0 ]
