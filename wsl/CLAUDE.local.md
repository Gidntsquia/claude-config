## Environment
This is WSL2: Windows programs and GUI apps can be run and screenshotted from here via `powershell.exe` and `/mnt/c`.

## Opening things for the user (WSL2)
Web pages, HTML files, running apps and GitHub-hosted docs open in Firefox; `.md`, logs, text and source open in VS Code. One tab/window per item. A `.md` that exists on GitHub (README, wiki) opens as its GitHub URL in Firefox. Never use bare `firefox.exe`, `wslview`, `explorer.exe`, `xdg-open` or `code`; they have failed to open anything here.
- WSL Firefox (file): `"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "$(wslpath -w "<abs path>")" &`
- WSL Firefox (URL): `"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "<url>" &`
- WSL VS Code: `"/mnt/c/Users/Jaxon/AppData/Local/Programs/Microsoft VS Code/bin/code" "<path>"`
- macOS: `open -a Firefox "<path or url>"` / `open -a "Visual Studio Code" "<path>"`
