# Updating claude-config

For a Claude (or a person) updating an existing install to the latest release. Run it unattended; stop only where it says STOP.

## How the install is laid out

`./install.sh` symlinks files from this repo into `~/.claude` (`agents`, `CLAUDE.md`, `settings.json`, `statusline.sh`, and each folder in `skills/`). So the repo clone **is** the config: changing the clone changes `~/.claude`. Any edits the user made to `CLAUDE.md`, `settings.json` or the agents are uncommitted changes or local commits in the clone, and the update must keep them.

## Steps

1. Find the clone: `dirname "$(readlink -f ~/.claude/settings.json)"`. Call it `$REPO`. If `~/.claude/settings.json` is not a symlink, install was never run: STOP and tell the user to follow the README quickstart.
2. Check it is the right repo: `git -C "$REPO" remote get-url origin` must contain `Gidntsquia/claude-config` (or the user's fork of it).
3. Find the latest release tag (never use a pre-release or draft):
   - With gh: `gh release view --repo Gidntsquia/claude-config --json tagName -q .tagName`
   - Without gh: `git -C "$REPO" ls-remote --tags --refs origin 'v*' | sed 's|.*/||' | grep -v -- '-' | sort -V | tail -1`
   Call it `$TAG`.
4. Read what changed: `git -C "$REPO" fetch --tags origin`, then `git -C "$REPO" show "$TAG:CHANGELOG.md" | head -60`. Tell the user the highlights in two or three lines.
5. Keep the user's changes: if `git -C "$REPO" status --porcelain` prints anything, run `git -C "$REPO" stash push --include-untracked -m "pre-update $(date +%F)"`. Note whether you stashed.
6. Move to the release. If the branch is `main` with no local commits (`git -C "$REPO" rev-list origin/main..HEAD` is empty): `git -C "$REPO" merge --ff-only "$TAG"`. If the user has local commits: `git -C "$REPO" merge "$TAG"`. If that conflicts, resolve each file by keeping the user's lines and adding the release's new lines (for `settings.json`, keep the user's values and add new keys); if you cannot tell which is right for a line, STOP and ask the user about that one line.
7. If you stashed: `git -C "$REPO" stash pop`. Resolve conflicts the same way.
8. Relink: `cd "$REPO" && ./install.sh`. It is safe to rerun. A real (non-symlink) file in `~/.claude` is moved to `<name>.pre-link`, not deleted.
9. Verify: `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/agents` and each `~/.claude/skills/*` that came from the repo are symlinks into `$REPO` (`readlink`), `python3 -c 'import json,sys; json.load(open(sys.argv[1]))' ~/.claude/settings.json` succeeds, and `git -C "$REPO" describe --tags --exact-match` prints `$TAG`.
10. Tell the user: the old and new version, what you kept from their changes (and the stash name if a pop was skipped), and that running Claude Code sessions must be restarted to pick up the new agents and settings.

## Rules

- Never `git reset --hard`, `git checkout -- .`, `git clean`, or force-push. Nothing the user wrote may be lost.
- Do not push to the user's remote unless asked.
- To undo: `git -C "$REPO" checkout <old tag or commit>` then `./install.sh`. Note the old version (`git describe --tags`) before step 6.
- New settings in a release (for example denied tools) are listed in `CHANGELOG.md`. If one clashes with something the user turned on, keep the user's choice and mention it.
