# Updating claude-config

For a Claude (or a person) updating an existing install to the latest release. Run it unattended and stop only where it says STOP. The wiki's [Updating](https://github.com/Gidntsquia/claude-config/wiki/Updating) page explains the reasons behind these steps.

## What 1.3 adds

1.3 improves the planner, worker and evaluator loop by adding three core features to it: run-agent, phone modes and the usage guard.

- run-agent is now a main part of the workflow: each agent ends with the `/run-agent` line that starts the next one in the same tmux pane.
- Phone modes let you run the loop from your phone, with each item sent as a picture in the chat.
- The usage guard reduces token waste by stopping a worker before it starts too many `claude` runs or subagents.
- Planner, worker and evaluator fixes: researcher subagents, a worker that never ends on a question, an evaluator that opens items hidden.
- Stability: updating an install that has your own edits is now tested, and it still needs work.

## How the install is laid out

`./install.sh` symlinks files from this repo into `~/.claude`, and saves the user's choices in `~/.claude/claude-config.json`. The clone is the config, so the user's edits to `CLAUDE.md`, `settings.json` or the agents are uncommitted changes or local commits in the clone. The update must keep them.

## Steps

1. Find the clone: the `repo` value in `~/.claude/claude-config.json`. If that file is missing (installs before 1.2.1), use `dirname "$(readlink -f ~/.claude/CLAUDE.md)"`, or `dirname "$(readlink -f ~/.claude/agents/planner.md)"` and its parent. Call it `$REPO`. If none of these leads to a clone, install was never run: STOP and tell the user to follow https://github.com/Gidntsquia/claude-config/blob/main/INSTALL.md.
2. Check it is the right repo: `git -C "$REPO" remote get-url origin` must contain `Gidntsquia/claude-config` (or the user's fork of it).
3. Find the latest release tag. Never use a pre-release or draft.
   - With gh: `gh release view --repo Gidntsquia/claude-config --json tagName -q .tagName`
   - Without gh: `git -C "$REPO" ls-remote --tags --refs origin 'v*' | sed 's|.*/||' | grep -v -e '-' | sort -V | tail -1`
   Call it `$TAG`.
4. Read what changed: `git -C "$REPO" fetch --tags origin`, then `git -C "$REPO" show "$TAG:CHANGELOG.md" | head -60`. Tell the user the highlights in two or three lines.
5. Keep the user's changes: if `git -C "$REPO" status --porcelain` prints anything, run `git -C "$REPO" stash push --include-untracked -m "pre-update $(date +%F)"`. Note whether you stashed.
6. Move to the release.
   - Branch `main` with no local commits (`git -C "$REPO" rev-list origin/main..HEAD` is empty): `git -C "$REPO" merge --ff-only "$TAG"`.
   - The user has local commits: `git -C "$REPO" merge --no-edit "$TAG"`.
   - If that conflicts: `python3 "$REPO/bin/resolve-kept-edits.py" "$REPO" --mine ours`, then `git -C "$REPO" commit --no-edit`.
7. If you stashed: `git -C "$REPO" stash pop`.
   - If it stops on a conflict, the stash is still there and nothing is lost. Run `python3 "$REPO/bin/resolve-kept-edits.py" "$REPO"`, then `git -C "$REPO" stash drop`.
   - The script keeps the user's lines and adds the release's, and prints `resolved <file>` for each. A `settings.json` list entry both sides changed stays one entry with the user's value, so leave it as one.
   - If it prints `LEFT <file>`, STOP and ask the user about that file.
   - Afterwards `git -C "$REPO" stash list` shows no `pre-update` entry and `git -C "$REPO" status` lists the user's edits as uncommitted changes, as before the update.
8. Relink: `cd "$REPO" && ./install.sh`. It reapplies the choices saved in `~/.claude/claude-config.json` and is safe to rerun. It makes no backup copies. A file or folder of the user's own in the place of one of the repo's stays byte for byte, and the run prints `kept yours: <path> (repo's not installed)`. INSTALL.md step 5 says how to choose otherwise.
   - 1.2.0 to 1.2.1: run `./install.sh` and it reapplies your saved choices. If the file is missing, follow INSTALL.md's questions once (steps 3 to 5), then run `./install.sh --check`.
   - 1.2.1 to 1.3, in this order:
     1. Run `claude update` until `claude --version` prints 2.1.296 or newer (usage-guard needs it).
     2. Install `uv` if `command -v uv` prints nothing: `brew install uv` when `command -v brew` prints a path, otherwise `curl -LsSf https://astral.sh/uv/install.sh | sh` (uv's own installer, into `~/.local/bin`). The run-agent and assistant MCP servers do not start without it. This is a step of the update the user asked for, so run it yourself and do not leave it for the user to do or decide.
     3. Run `./install.sh`. It registers the run-agent MCP server. If it printed that `claude` is not on PATH, run `claude mcp add --transport stdio --scope user run-agent -- ~/.claude/skills/run-agent/mcp/server.py` once `claude` is installed.
     4. If the saved choice is `--settings keep`, add `$REPO/mods/defer-artifact` to `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` (after any directories already there, `:`-separated) to load the defer-artifact mod.
     5. Run `./install.sh --check`.
   - 1.3.0 to the next release: the repo's `settings.json` no longer carries four `autoMode.environment` entries that described the author's own project. A merge keeps them in a `settings.json` the user edited, and `--settings keep` leaves them in `~/.claude/settings.json`. Delete them there too, each a whole line of the `environment` list: the `**Repository visibility**` and `**Source control**` lines that name `descent-of-essence`, the `**Primary use of Claude Code**` line that names `Wordbound`, and the `**Trusted repo**` line. Then `python3 -m json.tool ~/.claude/settings.json >/dev/null` must exit 0. Leave every other entry, the user's own included.
9. Verify: `cd "$REPO" && ./install.sh --check` ends with `all checks passed`, and `git -C "$REPO" describe --tags --exact-match` prints `$TAG`. If step 6 merged the release into the user's own commits, the tag is behind their merge commit, so check that `git -C "$REPO" merge-base --is-ancestor "$TAG" HEAD` exits 0.
10. Tell the user the old and new version, what you kept from their changes (and the stash name if a pop was skipped), and that running Claude Code sessions must be restarted to pick up the new agents and settings.

## Coming from an install before v1.3

An install from September 2026 linked whole folders (`~/.claude/agents`, `commands`, `hooks`) into the clone, and iTerm2 could be set to load its preferences from the clone's `iterm2/` folder. Do these four things in one go, with no new Claude session or terminal tab in between:

1. Copy iTerm2's preferences out of the clone. If `"$REPO/iterm2/com.googlecode.iterm2.plist"` exists: `mkdir -p ~/.claude/iterm2-prefs-backup && cp -p "$REPO/iterm2/com.googlecode.iterm2.plist" ~/.claude/iterm2-prefs-backup/`. The release no longer has that file, so the pull deletes it while iTerm2 is still reading it.
2. Discard the local `iterm2/` edits: `git -C "$REPO" restore iterm2/`. iTerm2 wrote them and step 1 saved them. This is the one place a discard is right. Every other local change follows steps 5 to 7.
3. Pull: steps 3 to 7 above. Then put the preferences back where iTerm2 looks for them: if `"$REPO/iterm2/com.googlecode.iterm2.plist"` is gone, `cp -p ~/.claude/iterm2-prefs-backup/com.googlecode.iterm2.plist "$REPO/iterm2/"`. Git lists it as an untracked file from now on, and `--check` prints a `WARN` line for it. Both are fine.
4. Run `cd "$REPO" && ./install.sh` at once. The pull moved or removed files the old links point at, the usage-guard hook among them. The installer makes `~/.claude/hooks` a folder of its own, removes links to files the repo no longer has (it prints `removed <path>`), and tells iTerm2 to stop loading preferences from the clone. Restart iTerm2 afterwards. Once it shows the user's settings, the plist in `$REPO/iterm2/` and the copy in `~/.claude/iterm2-prefs-backup/` can be deleted.

Then `./install.sh --check`. A `WARN leftover from an older install` line names a `.pre-link` copy an older installer made. Delete it once the user has looked at it.

## Moving the clone

Move the folder, then run the installer from the new path:

```
mv "$REPO" <new path>
cd <new path> && ./install.sh
```

The installer prints `relinked <path> (was <old target>, now missing)` for each link. Run it before the next Claude session starts, then `./install.sh --check`. The wiki's Updating page says what it rewrites.

## What no test covers

`test/run` is the one test command, and `TESTING.md` lists everything a pass does not cover. Four things can only be checked by hand on the real machine after an update. The wiki's Updating page says why.

- The live login token and real usage numbers. Check: `python3 ~/.claude/skills/run-agent/scripts/parse.py --window-reset` prints an epoch followed by `live`. `assumed (now + 5 h)` means the usage API gave no answer.
- Sleep, wake or a reboot while a run is scheduled. Check: after waking, `run-agent.sh --jobs` still lists the run as `sleeping (pid N)`, and `--health` exits 0.
- A Keychain dialog in a GUI session. Check: run `test/run quick` at the Mac's own screen. No dialog should appear. If one does, press Cancel, never "Reset To Defaults".
- iTerm2 showing the profile. Check: iTerm2 > Settings > Profiles lists `claude-tmux`, and `./install.sh --check | grep iTerm2` prints a PASS line.

## Rules

- Never `git reset --hard`, `git checkout -- .`, `git clean`, or force-push. Nothing the user wrote may be lost.
- Do not push to the user's remote unless asked.
- To undo: `git -C "$REPO" checkout <old tag or commit>` then `./install.sh`. Note the old version (`git describe --tags`) before step 6.
- New settings in a release (for example denied tools) are listed in `CHANGELOG.md`. If one clashes with something the user turned on, keep the user's choice and mention it.
