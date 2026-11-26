# Repo facts

- `~/.claude` files are symlinks into this clone, made by `./install.sh`. `./install.sh --check` prints a PASS or FAIL line per link.
- Evaluator tools: `local-tools/common/` links on every OS, `local-tools/wsl/` on WSL, `local-tools/macos/` on a Mac. `CLAUDE_CONFIG_INSTALL_OS=linux|wsl|mac|windows` overrides the OS for a test install in a scratch HOME.
- macOS tools: bash 3.2, `osascript` and `python3` only. Openers only record an item; `win.sh show` opens the window. Web items open in a Firefox on its own profile in the run's state dir. The user's own Firefox is never scripted, moved or closed.
- Safari will not load a `file://` page from AppleScript (the document stays "Untitled"); `open -a Safari <file>` does.
- Tests: `test/evaluator-tools.sh` (no window; `--live` on a Mac opens real ones), `test/owner-text.sh`, `test/install-scenarios.sh` (`SCN_ONLY=<case>`), `test/stock-mac.sh`, `test/rehearsal.sh` (Docker). Test overrides are the `EVSHOW_*` variables read in `local-tools/macos/maclib.sh` and `local-tools/common/evshow.sh`.
- `wiki/` is its own git repo (the GitHub wiki). After changing a line of `agents/*.md` that the wiki quotes, run `helper-mcp/stamp-wiki` and `helper-mcp/check-wiki-quotes`, and commit inside `wiki/`.
- `settings.json` cannot be edited from a Claude session: the usage guard blocks writes to it. The user edits it.
- No file that installs into `~/.claude` names the author's own repos or projects; `test/owner-text.sh` checks it.
