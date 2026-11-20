# Spec: Move stale agent definitions and backups into the local archive/
Drafted 2026-10-09.

## Ask
> Put stale agent defintions into the archive (i.e. evaluator-new now that it's been installed into the base evaluator)

User's answers:
- Stale files: `agents/evaluator-new.md`, `agents/run-loop.sh.retired`, `backups/evaluator-old-2026-10-08.md`. Also fold `backups/` into `archive/` and delete `backups/`.
- Destination: `archive/` (gitignored, local only).
- Naming: `<agent>-<YYYY-MM-DD>-<note>.md`; the note says why it is stale.
- Done check: `claude --agent evaluator-new` no longer resolves; USAGE.txt and README.md mention only live agents; `archive/README.txt` has a restore line per archived file; git status clean after a commit; `evaluator.md` byte-unchanged.
- Commit: yes, one commit, only these changes; leave the pending `settings.json` edit out of it.
- USAGE.txt: drop the run-loop line entirely.
- `archive/README.txt`: follow the existing planner format exactly, one line per file.

## What to build
A repo tidy-up in `/home/jaxon/files/claude-config`: the three stale files leave `agents/` and `backups/`, land in the gitignored `archive/` under dated, reason-bearing names, each with a one-line restore command appended to `archive/README.txt`; `backups/` is removed; `agents/USAGE.txt` is cut to the three live agents; the live `agents/evaluator.md` is untouched; the result is one commit.

## Facts
- `~/.claude/agents` is a symlink to the repo's `agents/` directory (install.sh line 12 links the whole dir), so deleting a file from `agents/` removes it from `~/.claude/agents` too. Verified with `ls -la ~/.claude/agents`.
- `agents/evaluator-new.md` and `agents/evaluator.md` differ only in frontmatter `name` and `description` (verified with `diff`).
- `.gitignore` ignores `archive/` ("Old prompt versions, local only") and `plans/`; `backups/` is not ignored and is committed (commit 93eee66).
- `archive/README.txt` format, one line per file: `Restore <what it was> (<when/why>, replaced by <what>): cp "/home/jaxon/files/claude-config/archive/<file>" ~/.claude/agents/<target>`.
- `agents/USAGE.txt` currently mentions run-loop (line 20-21) and `evaluator-new` (line 23). `README.md` and `wiki/` do not mention either (grep, verified).
- Working tree has an unrelated uncommitted change to `settings.json`.

## Requirements
1. (user) `agents/evaluator-new.md` is moved to `archive/evaluator-new-2026-10-09-installed-as-evaluator.md`; byte-identical content.
2. (user) `agents/run-loop.sh.retired` is moved to `archive/run-loop-2026-10-09-retired.sh`; byte-identical content, executable bit kept.
3. (user) `backups/evaluator-old-2026-10-08.md` is moved to `archive/evaluator-old-2026-10-08-pre-install.md`; byte-identical content.
4. (user) `backups/` directory no longer exists in the working tree or in git's index.
5. (user) `archive/README.txt` gains three lines appended after the existing two, in the existing format: what it was, when archived, what replaced it, then the `cp` command. Restore targets: `~/.claude/agents/evaluator-new.md`, `~/.claude/agents/run-loop.sh.retired`, `~/.claude/agents/evaluator.md` respectively. Existing lines unchanged.
6. (user) `agents/USAGE.txt` has no mention of `run-loop` and no mention of `evaluator-new`; the rest of the file is unchanged.
7. (user) `agents/evaluator.md`, `agents/planner.md`, `agents/worker.md` are byte-unchanged (`git diff` shows nothing for them).
8. (user) `~/.claude/agents/` lists exactly `USAGE.txt`, `evaluator.md`, `planner.md`, `worker.md`.
9. (user) `.gitignore` is unchanged; `archive/` stays ignored.
10. (default) `README.md` is unchanged (it already names only the three live agents).
11. (user) One commit contains exactly: the two deletions from `agents/`, the deletion from `backups/`, and the `agents/USAGE.txt` edit. `settings.json` stays modified and uncommitted. Commit message ends with the attribution lines given in the session's system reminder.
12. (default) Nothing is pushed.
13. (default) No other file in the repo changes.

## Constraints
- Shell (bash, git, mv) only; this is a file move, no code. Follow `~/.claude/CLAUDE.md` shell conventions (quote paths).
- Do not run `install.sh`.
- Do not touch `wiki/` (separate git repo) or `plans/`.

## Acceptance criteria
- [ ] R1-R3: `ls archive/` shows the three new names; `git show HEAD~1:agents/evaluator-new.md | cmp - archive/evaluator-new-2026-10-09-installed-as-evaluator.md` (and the equivalents for the other two) report no difference; `test -x archive/run-loop-2026-10-09-retired.sh`.
- [ ] R4: `test ! -e backups` and `git ls-files backups` prints nothing.
- [ ] R5: `wc -l archive/README.txt` is 5 (was 2 plus a trailing blank); each new line contains a `cp "/home/jaxon/files/claude-config/archive/..."` command ending in the stated target; `head -2` matches the previous content.
- [ ] R6: `grep -n "run-loop\|evaluator-new" agents/USAGE.txt` prints nothing; `git diff HEAD~1 -- agents/USAGE.txt` shows only removed lines.
- [ ] R7, R9, R10, R13: `git show --stat HEAD` lists only `agents/evaluator-new.md`, `agents/run-loop.sh.retired`, `backups/evaluator-old-2026-10-08.md`, `agents/USAGE.txt`.
- [ ] R8: `ls ~/.claude/agents/` prints exactly the four names; `claude --agent evaluator-new "."` fails to find the agent, `claude --agent evaluator "."` starts.
- [ ] R11: `git status --short` shows only ` M settings.json`; `git log -1 --format=%B` ends with the attribution lines.
- [ ] R12: `git status -sb` first line shows the branch ahead of origin by 1.
