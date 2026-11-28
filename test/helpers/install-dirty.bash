# Updating an install that has the user's own edits: the "dirty" start state and its checks (the dirty scenarios
# and bin/release/rehearsal.sh). Source test/helpers/install-lib.bash first.
GITID=(-c user.name=test -c user.email=test@example.com)
# target_commit <scratch dir>: prints a commit that holds this clone's HEAD plus its uncommitted files (the release
# under test), made in a scratch clone so nothing is written to this one.
target_commit() {
  local T="$1" head
  head="$(git -C "$R" rev-parse HEAD)" || return 1
  git clone -q "$R" "$T" 2>/dev/null && git -C "$T" checkout -q "$head" 2>/dev/null || return 1
  ( cd "$R" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
    | tar --null -T - -cf - ) | tar -xf - -C "$T" || return 1
  ( cd "$R" && git ls-files -z --deleted ) | ( cd "$T" && xargs -0 rm -f -- 2>/dev/null )
  git -C "$T" add -A >/dev/null 2>&1
  git -C "$T" diff --cached --quiet || git -C "$T" "${GITID[@]}" commit -qm "working tree" || return 1
  git -C "$T" rev-parse HEAD
}
# old_clone <clone> <start commit> <target repo> <target commit>: the user's clone as it stands before the update:
# branch main at the start commit, with the release under test fetched and waiting.
old_clone() {
  git clone -q "$R" "$1" 2>/dev/null || return 1
  git -C "$1" fetch -q "$3" HEAD 2>/dev/null || return 1
  git -C "$1" checkout -q -B main "$2" 2>/dev/null
}
# update_steps <clone> <target commit>: UPDATING.md steps 5 to 8 as the shell commands the file gives.
# Never reset --hard, clean or a forced push (UPDATING.md "Rules").
update_steps() {
  local K="$1" to="$2" stashed="" out rc
  if [ -n "$(git -C "$K" status --porcelain)" ]; then                                   # step 5
    git -C "$K" "${GITID[@]}" stash push --include-untracked -q -m "pre-update $(date +%F)" || { bad "update: git stash push failed"; return 1; }
    stashed=1
  fi
  # step 6: fast-forward when he has no commits of his own, else a merge that keeps them
  UPDATE_MERGE=ff
  if git -C "$K" merge-base --is-ancestor HEAD "$to"; then
    out="$(git -C "$K" merge --ff-only "$to" 2>&1)" || { bad "update: git merge --ff-only failed: $(last "$out")"; return 1; }
  else
    UPDATE_MERGE=merge
    if ! out="$(git -C "$K" "${GITID[@]}" merge --no-edit "$to" 2>&1)"; then
      UPDATE_MERGE="merge, conflicts in: $(git -C "$K" diff --name-only --diff-filter=U | tr '\n' ' ')"
      out="$("$PY" "$K/bin/resolve-kept-edits.py" "$K" --mine ours 2>&1)" || { bad "update: resolve-kept-edits.py --mine ours left a conflict: $(printf '%s' "$out" | tr '\n' ' ')"; return 1; }
      echo "$out" | sed 's/^/     /'
      git -C "$K" "${GITID[@]}" commit -q --no-edit || { bad "update: git commit --no-edit after the merge failed"; return 1; }
    fi
  fi
  if [ -n "$stashed" ]; then                                                           # step 7
    out="$(git -C "$K" "${GITID[@]}" stash pop 2>&1)"; rc=$?
    UPDATE_POP_CONFLICTS="$(git -C "$K" diff --name-only --diff-filter=U | tr '\n' ' ')"
    if [ "$rc" != 0 ]; then
      out="$("$PY" "$K/bin/resolve-kept-edits.py" "$K" 2>&1)" || { bad "update: resolve-kept-edits.py left a conflict: $(printf '%s' "$out" | tr '\n' ' ')"; return 1; }
      echo "$out" | sed 's/^/     /'
      git -C "$K" stash drop -q || { bad "update: git stash drop failed"; return 1; }
    fi
  fi
  out="$(cd "$K" && ./install.sh 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'           # step 8
  UPDATE_INSTALL_OUT="$out"
  expect "update: the current install.sh, no flags, exits 0 (got $rc)" test "$rc" = 0
}

# The start state for `dirty` and for bin/release/rehearsal.sh: the start commit's own install.sh, then four things the
# user did since. dirty_setup <home> <clone> <start commit> <target repo> <target commit>
MINE_RULE="- my own rule: say which file you changed"
MINE_NOTE="My own note for the helper: I work in Eastern time."
MINE_COMMITTED="My own reminder, committed: plans stay under two pages."
# his own settings file, written before the old installer runs (--settings merge keeps a file that is his)
MINE_SETTINGS='{"model": "opus", "cleanupPeriodDays": 365, "permissions": {"deny": ["Bash(rm -rf:*)"]}, "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo my-own-settings-hook >/dev/null"}]}]}}'
dirty_setup() {
  local H="$1" K="$2" from="$3" C="$1/.claude" out rc HM="/ho""me/him"   # in two halves: no home path in this file
  old_clone "$K" "$from" "$4" "$5" || { bad "dirty: could not clone $R at $from"; return 1; }
  # his git identity, as on any machine he commits from
  git config --file "$H/.gitconfig" user.name "Sample Brother"; git config --file "$H/.gitconfig" user.email "brother@example.com"
  printf '%s\n' "$MINE_SETTINGS" > "$C/settings.json"
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" "$TERMFLAG" --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "dirty: the install.sh of $from exits 0 (got $rc)" test "$rc" = 0
  expect "dirty: the clone is clean after that install" test -z "$(git -C "$K" status --porcelain 2>&1)"
  expect "dirty: his settings file is his own copy, not a link" sh -c "[ -f '$C/settings.json' ] && [ ! -L '$C/settings.json' ]"
  # 0a. a lived-in ~/.claude: session files, the prompt history and a plugins folder
  mkdir -p "$C/projects/-home-him-files-my-game" "$C/projects/-home-him-files-claude-config" "$C/plugins/cache/his-market/his-plugin/1.0.0/skills/greet"
  printf '%s\n' '{"type":"user","sessionId":"11111111-aaaa-4bbb-8ccc-000000000001","message":{"role":"user","content":"add a jump button"}}' \
                '{"type":"assistant","sessionId":"11111111-aaaa-4bbb-8ccc-000000000001","message":{"role":"assistant","content":[{"type":"text","text":"Added."}]}}' \
    > "$C/projects/-home-him-files-my-game/11111111-aaaa-4bbb-8ccc-000000000001.jsonl"
  printf '%s\n' '{"type":"user","sessionId":"22222222-aaaa-4bbb-8ccc-000000000002","message":{"role":"user","content":"why is my status line blank"}}' \
    > "$C/projects/-home-him-files-claude-config/22222222-aaaa-4bbb-8ccc-000000000002.jsonl"
  printf '%s\n' '{"display":"add a jump button","timestamp":1794000000000,"project":"'"$HM"'/files/my-game"}' \
                '{"display":"why is my status line blank","timestamp":1794000100000,"project":"'"$HM"'/files/claude-config"}' > "$C/history.jsonl"
  printf -- '---\nname: greet\ndescription: his own plugin skill\n---\nSay hello.\n' > "$C/plugins/cache/his-market/his-plugin/1.0.0/skills/greet/SKILL.md"
  printf '%s\n' '{"note": "his own file beside the plugins"}' > "$C/plugins/his-notes.json"
  mkdir -p "$H/orig/lived" && cp -R "$C/projects" "$C/history.jsonl" "$C/plugins" "$H/orig/lived/"
  # 0b. two commits of his own on main, and a side branch with a third: main has diverged from the release
  mkdir -p "$K/my-scripts" && printf '#!/bin/sh\necho my backup\n' > "$K/my-scripts/backup.sh"
  git -C "$K" add my-scripts/backup.sh && git -C "$K" commit -qm "my backup script" || { bad "dirty: could not make his first commit"; return 1; }
  printf '\n%s\n' "$MINE_COMMITTED" >> "$K/agents/planner.md"
  git -C "$K" commit -qam "planner: my own reminder" || { bad "dirty: could not make his second commit"; return 1; }
  git -C "$K" checkout -q -b my-experiments && printf 'an idea I am trying\n' > "$K/my-experiment.md" && git -C "$K" add my-experiment.md \
    && git -C "$K" commit -qm "an experiment" && git -C "$K" checkout -q main || { bad "dirty: could not make his side branch"; return 1; }
  git -C "$K" rev-parse HEAD > "$H/his-commit"; git -C "$K" rev-parse my-experiments > "$H/his-branch"
  # v1.2.1's installer kept a settings.json.pre-link copy; whatever is there now is the old release's doing
  find "$H" -name '*.pre-link*' 2>/dev/null | LC_ALL=C sort > "$H/orig/pre-link.list"
  expect "dirty: main has two commits the release lacks, so it has diverged ($(git -C "$K" rev-list --count "$5..HEAD" 2>&1))" test "$(git -C "$K" rev-list --count "$5..HEAD" 2>&1)" = 2
  # 1. uncommitted edits to tracked files
  printf '\n%s\n' "$MINE_RULE" >> "$K/CLAUDE.md"
  printf '\n%s\n' "$MINE_NOTE" >> "$K/agents/helper.md"
  printf 'notes I keep in the clone\n' > "$K/my-notes.md"
  # 2. an edit that conflicts with the release: the first line of the settings file that the release changed and
  #    that holds a rule or a hook command becomes his own.
  out="$("$PY" - "$K/settings.json" <(git -C "$K" show "$5:settings.json") <<'PYEOF'
import difflib, re, sys
old = open(sys.argv[1], encoding="utf-8").read().split("\n")
new = open(sys.argv[2], encoding="utf-8").read().split("\n")
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
    if tag not in ("replace", "delete"):
        continue
    for i in range(i1, i2):
        m = re.match(r'^(\s*)"command": "(.*)"(,?)$', old[i])
        if m:
            old[i] = '%s"command": "echo my-own-hook >/dev/null; %s"%s' % m.groups()
        elif re.match(r'^\s*"[^"]*",?$', old[i]) and i > 0 and old[i - 1].rstrip().endswith(("[", ",")):
            old[i] = re.sub(r'"[^"]*"', '"Bash(my-own-tool:*)"', old[i], count=1)
        else:
            continue
        open(sys.argv[1], "w", encoding="utf-8", newline="\n").write("\n".join(old))
        print("line %d: %s" % (i + 1, old[i].strip()[:100]))
        sys.exit(0)
sys.exit("no line of the settings file that the release changed holds a rule or a hook command")
PYEOF
)" || { bad "dirty: could not make the conflicting edit: $out"; return 1; }
  echo "     his conflicting edit, settings file $out"
  # 3. a link he replaced with a real file: his own skill folder where the installer's link was
  expect "dirty: .claude/skills/review-skill is a link before he replaces it" test -L "$C/skills/review-skill"
  rm -f "$C/skills/review-skill" && mkdir -p "$C/skills/review-skill"
  printf -- '---\nname: review-skill\ndescription: my own review skill\n---\nmine, not a link\n' > "$C/skills/review-skill/SKILL.md"
  mkdir -p "$H/orig" && cp -R "$C/skills/review-skill" "$H/orig/review-skill"
  git -C "$K" rev-parse HEAD > "$H/start-commit"
}
# links_outside <dir> <clone>: the links up to two levels under <dir> that do not resolve inside <clone>
links_outside() {
  local f t
  find "$1" -maxdepth 2 -type l 2>/dev/null | grep -v '/debug/' | while IFS= read -r f; do
    t="$(cd "$(dirname "$f")" 2>/dev/null && cd "$(dirname "$(readlink "$f")")" 2>/dev/null && pwd -P)"
    case "$t/" in ("$2"/*) ;; (*) printf '%s ' "$f" ;; esac
  done
}
# dirty_asserts <home> <clone> <target commit>: his commits, his ~/.claude files, his edits, and the closing checks
dirty_asserts() {
  local H="$1" K="$2" to="$3" C="$1/.claude" out rc f
  expect "dirty: the clone holds the release ($(git -C "$K" rev-parse --short "$to" 2>&1) is an ancestor of HEAD, on main)" sh -c "git -C '$K' merge-base --is-ancestor '$to' HEAD && [ \"\$(git -C '$K' symbolic-ref --short HEAD)\" = main ]"
  # his commits and his branch
  expect "dirty: his two commits are still in main's history" git -C "$K" merge-base --is-ancestor "$(cat "$H/his-commit")" HEAD
  expect "dirty: 'my backup script' and 'planner: my own reminder' are in git log" test "$(git -C "$K" log --format=%s "$to..HEAD" | grep -c -x -e 'my backup script' -e 'planner: my own reminder')" = 2
  expect "dirty: his committed file my-scripts/backup.sh is there" test "$(cat "$K/my-scripts/backup.sh" 2>&1 | tail -1)" = "echo my backup"
  expect "dirty: his committed line is still in agents/planner.md" grep -qxF -- "$MINE_COMMITTED" "$K/agents/planner.md"
  expect "dirty: .claude/agents/planner.md shows his committed line too" grep -qxF -- "$MINE_COMMITTED" "$C/agents/planner.md"
  expect "dirty: his branch my-experiments is where he left it" test "$(git -C "$K" rev-parse my-experiments 2>&1)" = "$(cat "$H/his-branch")"
  # the lived-in ~/.claude
  out=""; while IFS= read -r f; do cmp -s "$H/orig/lived/$f" "$C/$f" || out="$out $f"; done <<EOF
$(cd "$H/orig/lived" && find . -type f | sed 's|^\./||')
EOF
  expect "dirty: his session files, history.jsonl and plugins folder are byte-identical (changed or gone:$out)" test -z "$out"
  expect "dirty: there were 5 such files to compare" test "$(cd "$H/orig/lived" && find . -type f | wc -l | tr -d ' ')" = 5
  expect "dirty: .claude's settings file is still his own copy, not a link" sh -c "[ -f '$C/settings.json' ] && [ ! -L '$C/settings.json' ]"
  expect "dirty: his settings keys remain (model, cleanupPeriodDays, his deny rule, his hook)" "$PY" -c "
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
assert s.get('model')=='opus', s.get('model')
assert s.get('cleanupPeriodDays')==365
assert 'Bash(rm -rf:*)' in s['permissions']['deny']
assert any('my-own-settings-hook' in h.get('command','') for e in s['hooks']['PreToolUse'] for h in e.get('hooks',[]))" "$C/settings.json"
  # R7
  expect "dirty: his line is still in CLAUDE.md" grep -qxF -- "$MINE_RULE" "$K/CLAUDE.md"
  expect "dirty: his line is still in agents/helper.md" grep -qxF -- "$MINE_NOTE" "$K/agents/helper.md"
  expect "dirty: his untracked notes file is still in the clone" test "$(cat "$K/my-notes.md" 2>&1)" = "notes I keep in the clone"
  expect "dirty: git stash list is empty" test -z "$(git -C "$K" stash list 2>&1)"
  expect "dirty: .claude/CLAUDE.md shows his line too" grep -qxF -- "$MINE_RULE" "$C/CLAUDE.md"
  # R8
  f="$K/settings.json"
  expect "dirty: his edit is still in the clone's settings file" grep -q -e 'my-own-hook' -e 'my-own-tool' "$f"
  expect "dirty: no conflict markers in the files he edited" test -z "$(grep -l -E '^(<<<<<<< |>>>>>>> |=======$)' "$f" "$K/CLAUDE.md" "$K/agents/helper.md" 2>/dev/null)"
  expect "dirty: the settings file parses as JSON and holds every value of the release's but the one he changed, with no hook twice" "$PY" - "$f" <(git -C "$K" show "$to:settings.json") <<'PYEOF'
import json, sys
mine = json.load(open(sys.argv[1], encoding="utf-8")); rel = json.load(open(sys.argv[2], encoding="utf-8"))
def missing(m, r, path=""):
    if isinstance(r, dict):
        if not isinstance(m, dict): return [path]
        return [x for k, v in r.items() for x in (missing(m[k], v, path + "/" + k) if k in m else [path + "/" + k])]
    if isinstance(r, list):
        if not isinstance(m, list): return [path]
        out = []
        for i, x in enumerate(r):
            if x in m: continue
            # not there as the release has it: it may be the entry he edited, which stays one entry with his value
            twins = [y for y in m if isinstance(x, dict) and isinstance(y, dict) and any(k in y and y[k] == v for k, v in x.items())]
            best = min((missing(y, x, path + "[%d]" % i) for y in twins), key=len, default=[path + "[%d]" % i])
            out += best
        return out
    if m == r: return []
    return [] if isinstance(m, str) and ("my-own-hook" in m or "my-own-tool" in m) else [path]
gone = missing(mine, rel)
assert not gone, "the release's values missing from the merged file: %s" % gone[:6]
# an entry he edited is one entry, not his and the release's side by side (a hook listed twice runs twice)
for event, entries in rel.get("hooks", {}).items():
    r = [e.get("matcher") for e in entries]; m = [e.get("matcher") for e in mine.get("hooks", {}).get(event, [])]
    more = sorted(set(str(x) for x in r if m.count(x) > r.count(x)))
    assert not more, "%s lists more entries than the release for matcher %s" % (event, more)
PYEOF
  expect "dirty: .claude's settings file holds his edit too" grep -q -e 'my-own-hook' -e 'my-own-tool' "$C/settings.json"
  expect "dirty: .claude's settings file parses as JSON" "$PY" -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$C/settings.json"
  # R9
  expect "dirty: his real folder .claude/skills/review-skill is byte-identical" diff -r "$C/skills/review-skill" "$H/orig/review-skill"
  expect "dirty: ... and is still a real folder, not a link" sh -c "[ -d '$C/skills/review-skill' ] && [ ! -L '$C/skills/review-skill' ]"
  out=""; for f in "$K"/skills/*/; do f="$(basename "$f")"; [ "$f" = review-skill ] && continue
    [ -L "$C/skills/$f" ] && [ "$C/skills/$f" -ef "$K/skills/$f" ] || out="$out $f"; done
  expect "dirty: every other skill is a link into the clone (not:$out)" test -z "$out"
  expect "dirty: the agents resolve into the clone" test "$C/agents/planner.md" -ef "$K/agents/planner.md"
  out="$(links_outside "$C" "$K")"
  expect "dirty: every link under .claude points into the clone (not: $out)" test -z "$out"
  # closing: --check, no backup copies, nothing but his edits differs from the release
  out="$(cd "$K" && ./install.sh --check 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "dirty: --check exits 0 and ends 'all checks passed' (got $rc, '$(last "$out")')" test "$rc$(last "$out")" = "0all checks passed"
  expect "dirty: the update made no .pre-link copy (the old installer left $(wc -l < "$H/orig/pre-link.list" | tr -d ' '))" test "$(find "$H" -name '*.pre-link*' 2>/dev/null | LC_ALL=C sort)" = "$(cat "$H/orig/pre-link.list")"
  out="$(git -C "$K" status --porcelain 2>&1 | sed 's/^...//' | LC_ALL=C sort | tr '\n' ' ')"
  expect "dirty: git status lists his four files and nothing else (lists: $out)" test "$out" = "CLAUDE.md agents/helper.md my-notes.md settings.json "
}
scn_dirty_from() {  # <home> <start commit>
  local H="$1" from="$2" K="$1/files/claude-config" to
  to="$(target_commit "$H/target")" || { bad "dirty from $from: could not build the release commit"; return; }
  dirty_setup "$H" "$K" "$from" "$H/target" "$to" || return
  UPDATE_POP_CONFLICTS=""; UPDATE_INSTALL_OUT=""
  update_steps "$K" "$to" || return
  expect "dirty from $from: step 6 was a merge, not a fast-forward, because he has commits of his own (${UPDATE_MERGE:-none})" has "${UPDATE_MERGE:-}" '^merge'
  expect "dirty from $from: the stash pop did stop on a conflict in the settings file (conflicted: ${UPDATE_POP_CONFLICTS:-none})" has "$UPDATE_POP_CONFLICTS" 'settings\.json'
  expect "dirty from $from: install.sh said it kept his skill" has "$UPDATE_INSTALL_OUT" "^  kept yours: $H/.claude/skills/review-skill (repo's not installed)\$"
  dirty_asserts "$H" "$K" "$to"
}
scn_dirty_v121() { scn_dirty_from "$1" v1.2.1; }
scn_dirty_beta5() { scn_dirty_from "$1" v1.3.0-beta.5; }
