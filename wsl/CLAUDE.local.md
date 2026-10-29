## Environment
This is WSL2: Windows programs and GUI apps can be run and screenshotted from here via `powershell.exe` and `/mnt/c`.

## Opening things for the user (WSL2)
Web pages, HTML files, running apps and GitHub-hosted docs open in Firefox; `.md`, logs, text and source open in VS Code. One tab/window per item. A `.md` that exists on GitHub (README, wiki) opens as its GitHub URL in Firefox. Never use bare `firefox.exe`, `wslview`, `explorer.exe`, `xdg-open` or `code`; they have failed to open anything here.
- Game guard: while Deadlock runs (`~/.claude/local-tools/game-guard.sh` exits 0), win-app.sh, win.sh show/start/next/front/place and term-open.sh refuse (exit 3) and log to `~/.cache/claude-config/game-deferred.log`. Open nothing on screen then; wait or leave the item path in your reply.
- WSL Firefox (file): `~/.claude/local-tools/win-app.sh firefox "$(wslpath -w "<abs path>")" &`
- WSL Firefox (URL): `~/.claude/local-tools/win-app.sh firefox "<url>" &`
- WSL VS Code: `~/.claude/local-tools/win-app.sh code "<path>"` (finds VS Code under %LOCALAPPDATA%)
- macOS: `open -a Firefox "<path or url>"` / `open -a "Visual Studio Code" "<path>"`
