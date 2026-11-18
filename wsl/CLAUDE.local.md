## Environment
This is WSL2: Windows programs and GUI apps can be run and screenshotted from here via `powershell.exe` and `/mnt/c`.

## Opening things for the user (WSL2)
Web pages, HTML files, running apps and GitHub-hosted docs open in Firefox; `.md`, logs, text and source open as a file page in Firefox (`file-page.sh` builds the HTML page; a `.md` is rendered, anything else is numbered text). One tab/window per item. A `.md` that exists on GitHub (README, wiki) opens as its GitHub URL in Firefox. Never use bare `firefox.exe`, `wslview`, `explorer.exe`, `xdg-open` or `code`; they have failed to open anything here.
- Game guard: while Deadlock runs (`~/.claude/local-tools/game-guard.sh` exits 0), win-app.sh, win.sh show/start/next/front/place and term-open.sh refuse (exit 3) and log to `~/.cache/claude-config/game-deferred.log`. Open nothing on screen then; wait or leave the item path in your reply.
- WSL Firefox (file): `~/.claude/local-tools/win-app.sh firefox "$(wslpath -w "<abs path>")" &`
- WSL Firefox (URL): `~/.claude/local-tools/win-app.sh firefox "<url>" &`
- WSL file page (`.md`, log, text, source): `p=$(~/.claude/local-tools/file-page.sh "<path>") && p=${p#page: } && ~/.claude/local-tools/win-app.sh firefox "${p%%|*}" &` (`file-page.sh "<path>" A-B` shows only those lines; on `not built: <reason>` give the path instead). `win-app.sh code` opens nothing: it prints `not opened: VS Code is retired; use file-page.sh "<path>"`.
- macOS: `open -a Firefox "<path or url>"` / `open -a "Visual Studio Code" "<path>"`
