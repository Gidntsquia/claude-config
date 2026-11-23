# Updating claude-config

For a Claude (or a person) updating an existing install to the latest release. Run it unattended; stop only where it says STOP.

## How the install is laid out

`./install.sh` symlinks files from this repo into `~/.claude` (the agents, each folder in `skills/`, and, when the user chose them, `CLAUDE.md`, `settings.json` and `statusline.sh`; a merged `settings.json` is a real file). The choices are saved in `~/.claude/claude-config.json`. So the repo clone **is** the config: changing the clone changes `~/.claude`. Any edits the user made to `CLAUDE.md`, `settings.json` or the agents are uncommitted changes or local commits in the clone, and the update must keep them.

## Steps

1. Find the clone: the `repo` value in `~/.claude/claude-config.json`. If that file is missing (installs before 1.2.1), use `dirname "$(readlink -f ~/.claude/CLAUDE.md)"`, or `dirname "$(readlink -f ~/.claude/agents/planner.md)"` and its parent. Call it `$REPO`. If none of these leads to a clone, install was never run: STOP and tell the user to follow https://github.com/Gidntsquia/claude-config/blob/main/INSTALL.md.
2. Check it is the right repo: `git -C "$REPO" remote get-url origin` must contain `Gidntsquia/claude-config` (or the user's fork of it).
3. Find the latest release tag (never use a pre-release or draft):
   - With gh: `gh release view --repo Gidntsquia/claude-config --json tagName -q .tagName`
   - Without gh: `git -C "$REPO" ls-remote --tags --refs origin 'v*' | sed 's|.*/||' | grep -v -e '-' | sort -V | tail -1`
   Call it `$TAG`.
4. Read what changed: `git -C "$REPO" fetch --tags origin`, then `git -C "$REPO" show "$TAG:CHANGELOG.md" | head -60`. Tell the user the highlights in two or three lines.
5. Keep the user's changes: if `git -C "$REPO" status --porcelain` prints anything, run `git -C "$REPO" stash push --include-untracked -m "pre-update $(date +%F)"`. Note whether you stashed.
6. Move to the release. If the branch is `main` with no local commits (`git -C "$REPO" rev-list origin/main..HEAD` is empty): `git -C "$REPO" merge --ff-only "$TAG"`. If the user has local commits: `git -C "$REPO" merge "$TAG"`. If that conflicts, resolve each file by keeping the user's lines and adding the release's new lines (for `settings.json`, keep the user's values and add new keys); if you cannot tell which is right for a line, STOP and ask the user about that one line.
7. If you stashed: `git -C "$REPO" stash pop`. Resolve conflicts the same way.
8. Relink: `cd "$REPO" && ./install.sh`. It reapplies the choices saved in `~/.claude/claude-config.json` and is safe to rerun. It makes no backup copies. If one of the user's own agents, skills or commands has a repo name, theirs stays and the run prints `kept yours: <path> (repo's not installed)`; INSTALL.md step 5 says how to choose otherwise.
   - 1.2.0 → 1.2.1: run `./install.sh` and it reapplies your saved choices; if the file is missing, follow INSTALL.md's questions once (steps 3 to 5), then run `./install.sh --check`.
   - 1.2.1 → 1.3: first run `claude update` until `claude --version` prints 2.1.296 or newer (usage-guard needs it), and install `uv` if `command -v uv` prints nothing (`curl -LsSf https://astral.sh/uv/install.sh | sh`; the run-agent and assistant MCP servers start with it). The 1.3 pre-release is `v1.3.0-beta.5`, which step 3 skips, so to install it set `TAG=v1.3.0-beta.5` by hand and continue from step 4. Then run `./install.sh`: it registers the run-agent MCP server. If it printed that `claude` is not on PATH, run `claude mcp add --transport stdio --scope user run-agent -- ~/.claude/skills/run-agent/mcp/server.py` once `claude` is installed. If the saved choice is `--settings keep`, add `$REPO/mods/defer-artifact` to `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` (after any directories already there, `:`-separated) to load the defer-artifact mod. Then run `./install.sh --check`.
9. Verify: `cd "$REPO" && ./install.sh --check` ends with `all checks passed`, and `git -C "$REPO" describe --tags --exact-match` prints `$TAG`.
10. Tell the user: the old and new version, what you kept from their changes (and the stash name if a pop was skipped), and that running Claude Code sessions must be restarted to pick up the new agents and settings.

## Coming from an install before v1.3

An install from September 2026 linked whole folders (`~/.claude/agents`, `commands`, `hooks`) into the clone, and iTerm2 could be set to load its preferences from the clone's `iterm2/` folder, so iTerm2 rewrote files there. Do these three things in one go, with no new Claude session or terminal tab in between:

1. Discard the local `iterm2/` edits: `git -C "$REPO" restore iterm2/`. iTerm2 wrote them, the user did not, and the pull stops on them. This is the one place a discard is right; every other local change follows steps 5 to 7.
2. Pull: steps 3 to 7 above.
3. Run `cd "$REPO" && ./install.sh` at once. The pull moved or removed files the old links point at, the usage-guard hook among them, and a session started before the installer runs meets those broken links. The installer makes `~/.claude/hooks` a folder of its own, removes links to files the repo no longer has (it prints `removed <path>`), and tells iTerm2 to stop loading preferences from the clone. Restart iTerm2 afterwards.

Then `./install.sh --check`. A `WARN leftover from an older install` line names a `.pre-link` copy an older installer made; delete it once the user has looked at it.

## Moving the clone

Move the folder, then run the installer from the new path:

```
mv "$REPO" <new path>
cd <new path> && ./install.sh
```

The installer points every link under `~/.claude` at the new path and prints `relinked <path> (was <old target>, now missing)` for each, rewrites the paths in `~/.claude/settings.json` (unless the saved choice is `--settings keep`), and saves the new `repo` in `~/.claude/claude-config.json`. Run it before the next Claude session starts: until then the links, the hooks among them, point at the old path. Then `./install.sh --check`.

## What no test covers

The tests (`test/install-scenarios.sh`, `skills/run-agent/scripts/test.sh`, `test/real-usage.sh`, and the install workflow on ubuntu, macOS and Windows) run in throwaway homes on machines with no screen and no login. Four things can only be checked by hand on the real machine after an update:

- **The live login token and real usage numbers.** The tests read a fake Keychain item and get a 401 from the usage API. Check: `python3 ~/.claude/skills/run-agent/scripts/parse.py --window-reset` prints an epoch followed by `live`. `assumed (now + 5 h)` means the usage API gave no answer.
- **Sleep, wake or a reboot while a run is scheduled.** The tests never suspend the machine. Check: after waking, `run-agent.sh --jobs` still lists the run as `sleeping (pid N)`, and `--health` exits 0.
- **A Keychain dialog in a GUI session.** A CI runner cannot show one; the tests only prove every throwaway home has its own keychain and the real search list is unchanged. Check: run `bash test/install-scenarios.sh --terminal` at the Mac's own screen; no dialog should appear. If one does, press Cancel, never "Reset To Defaults".
- **iTerm2 showing the profile.** The tests check the profile file and its link, not the app. Check: iTerm2 → Settings → Profiles lists `claude-tmux`, and `./install.sh --check | grep iTerm2` prints a PASS line.

## Rules

- Never `git reset --hard`, `git checkout -- .`, `git clean`, or force-push. Nothing the user wrote may be lost.
- Do not push to the user's remote unless asked.
- To undo: `git -C "$REPO" checkout <old tag or commit>` then `./install.sh`. Note the old version (`git describe --tags`) before step 6.
- New settings in a release (for example denied tools) are listed in `CHANGELOG.md`. If one clashes with something the user turned on, keep the user's choice and mention it.
