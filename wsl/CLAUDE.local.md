## Environment
This is WSL2: Windows programs and GUI apps can be run and screenshotted from here via `powershell.exe` and `/mnt/c`.

## Opening things for the user (WSL2)
Web pages, HTML files, running apps and GitHub-hosted docs open in Firefox; `.md`, logs, text and source open in VS Code. One tab/window per item. A `.md` that exists on GitHub (README, wiki) opens as its GitHub URL in Firefox. Never use bare `firefox.exe`, `wslview`, `explorer.exe`, `xdg-open` or `code`; they have failed to open anything here.
- WSL Firefox (file): `"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "$(wslpath -w "<abs path>")" &`
- WSL Firefox (URL): `"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" "<url>" &`
- WSL VS Code: `"/mnt/c/Users/Jaxon/AppData/Local/Programs/Microsoft VS Code/bin/code" "<path>"`
- macOS: `open -a Firefox "<path or url>"` / `open -a "Visual Studio Code" "<path>"`

### One window per item, then close it (verified on this box 2026-10-08)
Open each item in its own new window so it can be closed alone. Give the item a unique title word (HTML `<title>`, or the file name) and close by that title.
- Firefox new window (file): `"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" -new-window "$(wslpath -w "<abs path>")" &`
- Firefox new window (URL): `"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" -new-window "<url>" &`
- VS Code new window: `"/mnt/c/Users/Jaxon/AppData/Local/Programs/Microsoft VS Code/bin/code" -n "<path>"`
- Show (open → place → front, one command): `~/.claude/local-tools/win.sh show "<unique title text>" X Y W H [timeout-s]` polls (default 15 s) for exactly one visible window with that title, un-minimizes it, places it, sets topmost without focus, prints `shown: HWND title L T W H`; exit 1 `not shown: ...` otherwise (0 or 2+ matches list candidates with HWNDs: ask the user which is theirs). Keep the HWND; every later action takes the HWND.
- By HWND only: `win.sh front|untop|close <HWND>`, `win.sh place <HWND> X Y W H`, `win.sh rect <HWND>`, `win.sh find "<title>"` (one match or exit 1), `win.sh list-topmost`. Title-based front/place/close are errors. Clear topmost (`untop`) after the question is answered.
- Pre-open minimized: after launching an item, `win.sh prep "<unique title>" [timeout-s]` waits for exactly one match, registers it, minimizes it, prints `prepped: HWND title`. `win.sh min <HWND>` minimizes an item you launched (e.g. after `term-open.sh`).
- `win.sh show` takes an optional 7th arg, your terminal HWND: `show "<title>" X Y W H timeout-s <termHWND>`; it retries un-minimize/place/front 3 times and checks position (L >= X), topmost, and no overlap with the terminal before printing `shown:`.
- `show` minimizes and restores a window that is not already minimized before setting topmost (a fresh browser window ignores TOPMOST otherwise); on failure it prints `not shown: <HWND> <reasons>; tries: ...`.
- `win.sh start "<title>" X Y W H timeout-s TX TY TW TH [termHWND]`: one process that prints `fginfo ...` of the foreground window (your terminal), places it at TX TY TW TH, then shows the item; `win.sh next <oldHWND> "<title>" X Y W H timeout-s <termHWND>`: untop+close the old item and show the new one in one process; both take an optional last arg, a Windows path: a whole-display capture taken right after `shown:` (`capture <path>` line).
- Instant show on an answer: all items prepped minimized first, then `evshow.sh arm first "<title1>" "<title2>" ...` (every item's title in asking order, before the readiness question) starts a watcher on this session's transcript and a gate-capture loop (screen every ~2.5 s while the question is open); the moment the AskUserQuestion answer lands it runs `win.sh start` (first) or `win.sh next` (later items), captures the screen right after, and logs answer/shown times (ET), `elapsed N s` and `shown -> question N s`. After every answer run `evshow.sh wait` first: prints the log, copies the capture to this session's `shown.png` (and the gate capture to its `gate.png` after the readiness answer; paths from `evshow.sh path shown|gate`), and auto-arms the next queued title (exit 1 on `not shown`; fires the show itself if the watcher did not within 1.5 s). `evshow.sh arm next <currentHWND> "<title>"` re-arms by hand (e.g. after a reopen). `evshow.sh end` untops+closes the current item, restores the terminal from the saved `fginfo` line (prints `now`), disarms and prints `list-topmost`. `evshow.sh history` prints the whole run's log. Saved terminal line: `$(evshow.sh path dir)/term`.
- Per-session state: `win.sh`/`evshow.sh` keep `launched.txt` (the registry of windows you launched), `term`, `history`, `shown.png`, `gate.png` and the watcher under `~/.claude/local-tools/evshow.state/<session id>/` (your `$CLAUDE_CODE_SESSION_ID`; `EVSHOW_STATE=<dir>` overrides). `evshow.sh path shown|gate|dir` prints this session's paths. Two evaluator sessions never see each other's windows or terminal; `wait`/`end` with nothing armed print `no session`, exit 1.
- Tests only: `EVSHOW_BEHIND=1` makes `win.sh`/`evshow.sh` place and un-minimize windows at the very bottom of the z-order (`HWND_BOTTOM`, under every user window) without topmost or focus (a stand-in terminal via `EVSHOW_TERMHWND`, transcripts via `EVSHOW_TRANSCRIPTS`); unset = normal behavior. Used by `~/files/agent-eval-experiment/evaluator/`.
- Close: `~/.claude/local-tools/win.sh close <HWND>` (exit 1 if the window is gone).
- Wait about 6 s after opening before looking for the title. Pick title text that only your window has, so the user's own windows are never closed.

### Terminal programs in their own window (verified on this box 2026-10-08)
- Open: `~/.claude/local-tools/term-open.sh <Title> "<dir>" '<command>'` opens a new Windows Terminal window titled <Title>, attached to a tmux session named <Title> that you own, prints `opened <Title> HWND=<n>`, then runs the command; the shell stays open after it ends. Drive it only with `tmux send-keys -t <Title> ...` (e.g. a loop that re-triggers a short-lived state).
- Close: `~/.claude/local-tools/term-close.sh <Title> <HWND>` closes the window and kills that tmux session.
- `wt.exe -w new` alone is not enough: the window opens behind the active one, and `;` in its arguments splits into extra tabs.

### Proof on screen (verified on this box 2026-10-08)
- Capture: `~/.claude/local-tools/screen-capture.sh <name>` saves the whole display (2560x1440) and prints the WSL path of the PNG; read it with the Read tool. It is DPI-aware; a plain PowerShell `CopyFromScreen` here captures only the top-left 2048x1152 and misses windows outside it.
- A window title in a process list or taskbar is not proof the window is visible; only the capture is.

### Window placement (side by side with the question)
- `~/.claude/local-tools/win.sh fgrect` prints "L T W H" of the foreground window (your own terminal at start).
- `win.sh placefg X Y W H` moves/resizes the foreground window (your own terminal only). Pixels are real display pixels (2560x1440).
- `win.sh fginfo` prints "HWND L T W H MAX" of the foreground window (read once, at the very start, for your own terminal; MAX=1 rect is e.g. `-9 -9 2578 1408`). Restore: `win.sh setwin HWND L T W H MAX` (negatives OK; prints `now L T W H MAX`, equal to the saved line; never activates; exit 1 if the HWND is gone).
- Layout: terminal at 0 0 1020 1400; item windows at 1030 0 1530 1400.
