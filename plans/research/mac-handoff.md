# Research: Mac handoff (2026-11-19, about 10:33 PM ET, two researchers, tier repo)

## Repo state
- main is clean and equal to origin/main at 44b2598. Local branches: main and pr2 only. No stashes, one worktree.
- All 10 local tags (pre-trim-2026-10-08, v1.2.1, v1.3.0-beta.1 to beta.4 among them) are on origin.
- pr2 (0b2cdaa) is an ancestor of main and is contained in origin/main and origin/release-1.2.1; `git cherry main pr2` prints nothing.
- Gidntsquia/claude-config is PUBLIC. gh is signed in as Gidntsquia with the repo scope.
- Install workflow run 44362499305 for tag v1.3.0-beta.4 (2026-11-18 12:47 PM ET): success on ubuntu, macos and windows. The workflow runs only on `release: published`.

## Local-only material inside the clone
- plans/ (git-ignored, 65 MB). Text the next round reads totals 720 KB: PLAN.md, EVAL.md, EVAL_NOTES.md, WORKER_NOTES.md, RELEASE_TRACE.md, HANDOFF.md, NOTE-run-agent-watchdog.md, STATUS-v1-3-1386430343.md, research/, archive/. The rest is eval output: phone 17M, eval_r37_view 10M, eval_r38_view 9.1M, eval_r24 7.2M, eval_r24b 7.1M, eval_r40/r39/r36_view about 3M each, and logs.
- archive/ (git-ignored, 48 KB, old prompt versions).
- wiki/ is its own clone of Gidntsquia/claude-config.wiki.git, even with origin/master, with one untracked file: AI-Tells.md.
- .claude/settings.local.json (93 bytes): only `permissions.allow`.
- Secret scan of plans/, archive/ and wiki/AI-Tells.md (patterns sk-ant-, gh*_, AKIA, key/password/secret/token assignments, .credentials; binary, image and 1 MB+ files skipped): 0 files matched.

## Sibling folders (user: all stay on this PC)
- ~/files/agent-eval-experiment: remote Gidntsquia/agent-eval-experiment; 16 commits not on the remote, 1 modified and 11 untracked files, 148 ignored entries; 4.1 GB, about 4.0 GB of it ignored.
- ~/files/assistant-agent: no remote; 77 commits only here; 34 MB. No tracked file or symlink in claude-config points at it (its files were copied into assistant/ for v1.3).
- Named in tracked files, exist, no origin remote: ai-sandbox, base-context-cleanup, curling_simulator, slay-the-spire-advisor, token-experiment.

## Home folder (~/.claude)
- Not links into the repo and in no git repo: claude-config.json, settings.json (a separate copy, settings mode "replace"), agent-archive (80K), feedback, jobs (8K), pre-migration-backup-20260828-184708, run-agent (476K, job state and logs), skills-archive (56K), ssh (4K), state (8K), skills/synced (4.8M), skills/.test-speedup-backup-2026-08-26 (44K), local-tools/evshow.state (412M), plus Claude Code's own runtime state (history, projects, sessions).
- Home settings.json has the same top-level keys as the repo copy; values differ in `env` (home adds CLAUDE_CODE_PLUGIN_DIRS, which install.sh sets), `permissions` (2 extra allow rules), `model` and `modelSettings`.
- ~/.claude.json mcpServers: user scope has run-agent; the claude-config project scope has none.
- ~/.claude/claude-config.json choices: projects /home/jaxon/files, terminal true, defaultProfile true, statusline squid, settings replace.
- Memory: 4 files, 2791 bytes, at ~/.claude/projects/-home-jaxon-files-claude-config/memory/ (MEMORY.md and 3 notes). The folder name is the clone's absolute path with "/" changed to "-", so a Mac clone gets a different folder name.
- No scheduled run-agent jobs are waiting (~/.claude/run-agent/jobs is empty).
- Usage-guard state is in ~/.cache/claude-guard/, per machine, made on first use; nothing to copy (hooks/usage-guard/README.md:96-109).

## What the Mac needs
- Already tracked, so a clone has them: skills/write-readme/SKILL.md, skills/write-readme/references/style.md, docs/agent-style.md, agents/, assistant/.
- Tools: git, python3 (test.sh calls it 54 times), tmux (`brew install tmux`), gh, uv (the MCP servers start with it, UPDATING.md:23), Claude Code 2.1.296 or newer. test.sh uses no node, bun, playwright or starship.
- install.sh on macOS (install.sh:33 sets OS=mac): skips wsl/local-tools and CLAUDE.local.md (567-569, WSL only; on a Mac it keeps whatever CLAUDE.local.md exists, 303-304); adds an iTerm2 "Claude tmux" profile only when /Applications/iTerm.app exists (298-299, 536-553); asks for `brew install tmux` (489) and `brew install --cask font-jetbrains-mono-nerd-font` (551). No macOS version of CLAUDE.local.md exists in the repo.
- Release notes "Known issues" name no macOS check failure. beta.3 failed on macOS (`setsid: command not found`), fixed in beta.4 with a Python `os.setsid` fallback.
- On this PC's real home, `--check` shows a PermissionDenied FAIL that comes from the user's own settings; a scratch-HOME check passes.

## Promotion to the full release (work for the Mac, not for this plan's worker)
- Open item from the 2026-11-18 eval (verdict ship): reread the notes against the style file; RELEASE_NOTES.md:34 "`test.sh` can no longer touch a live tmux pane." uses "touch", which skills/write-readme/references/style.md:26 flags. User: "Fine for now as the beta release. We will need a closer look when we do the full release".
- No v1.3 or v1.3.0 tag exists. UPDATING.md step 3 skips pre-releases, so the full release needs a non-beta tag.
- CI runs only when a release is published, so a macOS fix needs a new published release to get a macOS CI run.
- Known issue kept: with `--agent-clash keep`, the assistant copy cannot find its MCP server.
- test.sh on b616b19: 315 passed, 0 failed.

## Transport options
- Public repo, so a branch or release asset there is public. Options found: private GitHub repos, an orphan branch in the same repo, a release asset, a cloud-drive archive, a secret gist. The researcher recommended private repos; the user chose a branch in the public repo.

## Proof options
- From this PC: a scratch-HOME fresh clone with `./install.sh` and `--check` (as the last eval did), plus beta.4's green macOS CI.
- Only on the Mac: the iTerm2 profile and fonts, Homebrew tmux/uv/gh, `--check` on the real path, run-agent scheduling under a real macOS session.
