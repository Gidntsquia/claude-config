Installing this setup is now one sentence to Claude, and the install adds to what you already have instead of replacing it. Everything since v1.2.0 (2026-10-25) is here.

## Highlights ✨

- Paste `Install https://github.com/Gidntsquia/claude-config following its INSTALL.md` into Claude Code. Claude clones the repo to `~/.claude-config`, asks four questions (projects folder, terminal setup, status line, settings), runs the install, checks it and gives a five-step tour that ends with your first project.
- iTerm2 no longer crashes on a Mac that isn't mine. Older installs pointed iTerm2's whole preferences at this repo, with profiles for folders only my Mac has. The install now adds one "Claude tmux" profile and undoes the old setting.
- Your files win by default. `settings.json` is merged (your values stay, lists like `permissions.deny` are combined, the original is kept as `settings.json.pre-link`), your CLAUDE.md is left alone, and an agent or skill with the same name as one of mine stops the install so you choose: keep yours, use mine, or skip.
- Every push runs the install on Ubuntu, macOS and Windows in GitHub Actions, in an empty `~/.claude` and in one that already has its own settings, CLAUDE.md and planner agent. `test/docker-install.sh` runs the same two cases on a fresh Ubuntu, and `test/windows-sandbox/` on a clean Windows with WSL.

## Install 🧰

- `install.sh` takes `--projects`, `--terminal`, `--default-profile`, `--statusline squid|plane|keep`, `--settings merge|keep|replace` and `--agent-clash keep|replace|skip` (or per name, `planner=keep`). `--theme` still works.
- Choices are saved in `~/.claude/claude-config.json`. Running `./install.sh` with no flags reapplies them and prints "reusing saved choices".
- `./install.sh --check` prints one PASS, FAIL or SKIP line per installed item, including `claude doctor`, the status line preview, tmux, the Windows Terminal or iTerm2 profile and the volume task, and exits 1 on any FAIL.
- Terminal setup is a choice now. Without `--terminal` the install leaves tmux, starship, `.tmux.conf` and terminal profiles alone. With `--default-profile` it also makes the tmux profile the one new windows open with, and prints how to undo it.
- Native Windows without WSL installs the agents, skills, settings and CLAUDE.md from Git Bash and says what it skipped (status line, tmux, terminal setup).
- tmux-quad moved to `bin/` and opens its panes in your projects folder, falling back to your home folder.
- No file in the repo names my home folder anymore. Windows paths come from `%USERPROFILE%` and `%LOCALAPPDATA%`, and `wsl/local-tools/win-app.sh` finds Firefox, VS Code and Windows Terminal.

## Agents 🤖

- report-writer finds Playwright through `$PLAYWRIGHT_DIR`, the project's `node_modules`, your projects folder or the global npm folder, and says what to install when none has it.
- evaluator opens Firefox and VS Code through `win-app.sh`, and helper starts your first project in your projects folder, instead of using paths from my PC.

## Settings ⚙️

- The default model in `settings.json` is Sonnet. With the merge, your own `model` stays.
- `UPDATING.md` finds the clone through `~/.claude/claude-config.json`, so it works when `settings.json` is merged rather than linked.

## Known issues

- The Windows Sandbox test needs nested virtualization for WSL inside the Sandbox, which some PCs don't have.

## Agent versions 📄

- planner.md at 19ecb18 (2026-10-23)
- worker.md at 8206204 (2026-10-24)
- evaluator.md at 36b2e06 (2026-10-26)
- helper.md at 36b2e06 (2026-10-26)
- report-writer.md at 36b2e06 (2026-10-26)
- report-checker.md at 06a0875 (2026-10-25)
