# Repo facts

- `~/.claude` files are symlinks into this clone, made by `./install.sh`. `./install.sh --check` prints a PASS or FAIL line per link.
- Evaluator tools: `local-tools/common/` links on every OS, `local-tools/wsl/` on WSL, `local-tools/macos/` on a Mac. `CLAUDE_CONFIG_INSTALL_OS=linux|wsl|mac|windows` overrides the OS for a test install in a scratch HOME.
- macOS tools: bash 3.2, `tmux`, `osascript` and `python3` only. Openers only record an item; `win.sh show` opens it inside the user's iTerm2 as a tmux pane, an iTerm2 split or an iTerm2 tab (rotating; `EVSHOW_MAC_MODE` fixes one). No tool sets window bounds or starts a browser; a URL or `.html` goes to `open` and is never closed. `phone-shot.sh` alone uses headless Firefox.
- iTerm2 3.7 does not answer AppleScript `create tab … command` (and `split vertically … command` only sometimes), though the tab opens. `win.sh` sends both inside `ignoring application responses` and takes the item's pid file as the proof it started.
- An iTerm2 session stays open after its command ends, and `less` ignores SIGTERM: an item is closed with `kill -HUP` on its pid, then AppleScript `close` of the session on that pid's tty.
- Tests reach the Mac tools through `EVSHOW_TMUX`, `EVSHOW_OSASCRIPT`, `EVSHOW_OPEN` and `EVSHOW_ITERM_APP` (stand-ins); with `EVSHOW_OSASCRIPT` set no pid file is waited for.
- Tests: `test/evaluator-tools.sh` (no window; `--live` on a Mac opens real ones), `test/owner-text.sh`, `test/install-scenarios.sh` (`SCN_ONLY=<case>`), `test/stock-mac.sh`, `test/rehearsal.sh` (Docker). Test overrides are the `EVSHOW_*` variables read in `local-tools/macos/maclib.sh` and `local-tools/common/evshow.sh`.
- `wiki/` is its own git repo (the GitHub wiki). After changing a line of `agents/*.md` that the wiki quotes, run `helper-mcp/stamp-wiki` and `helper-mcp/check-wiki-quotes`, and commit inside `wiki/`.
- `settings.json` cannot be edited from a Claude session: the usage guard blocks writes to it. The user edits it.
- No file that installs into `~/.claude` names the author's own repos or projects; `test/owner-text.sh` checks it.
