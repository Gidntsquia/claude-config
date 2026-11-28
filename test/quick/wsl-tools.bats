#!/usr/bin/env bats
# The WSL tools, checked off Windows: stand-in cmd.exe, powershell.exe, wslpath and tmux on PATH, a stand-in grep that
# decides what /proc/version says, and wt-profile.py on a copy of a fixture Windows Terminal settings file.

load ../helpers/common

U=Users  # the Windows folder name, apart from its slashes: the personal-path check reads this file too

FX="$REPO/test/fixtures/wsl-tools"
FONT="Test Nerd Font"

setup() {
  temp_home
  unset XDG_CACHE_HOME GAME_GUARD GAME_GUARD_PROCS GAME_GUARD_CMD GAME_DEFERRED_LOG TERM_OPEN_PROFILE WSL_DISTRO_NAME
  unset WSLENV WIN_HOME WIN_HOME_W WIN_LOCALAPPDATA WIN_PROGRAMFILES TMUX TMUX_PANE EVSHOW_TERMHWND CLAUDE_CODE_SESSION_ID
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  : > "$STUB_LOG"
  T="$TEST_HOME/.claude/local-tools"
  DEFERRED="$TEST_HOME/.cache/claude-config/game-deferred.log"
  WT="$BATS_TEST_TMPDIR/windows-terminal.json"
  cp "$FX/windows-terminal.json" "$WT"
}

# Put the stand-ins on PATH and act as a WSL machine, with the real tools linked where an install puts them.
as_wsl() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) skip "stand-in .exe scripts cannot run on Windows Git Bash" ;; esac
  export PATH="$FX/bin:$PATH" STUB_WSL=1 STUB_MNT="$BATS_TEST_TMPDIR/mnt/c"
  mkdir -p "$T"
  for f in "$REPO"/local-tools/wsl/* "$REPO"/local-tools/common/evsession.sh; do ln -s "$f" "$T/$(basename "$f")"; done
}

# Replace one installed tool with a stand-in (removes the link first, so the repo file is never written through it).
stand_in() { rm -f "$T/$1"; cp "$FX/$1" "$T/$1"; }

fake_firefox() {
  FIREFOX="$STUB_MNT/Program Files/Mozilla Firefox/firefox.exe"
  mkdir -p "$(dirname "$FIREFOX")"
  cp "$FX/app.exe" "$FIREFOX"
  export WIN_PROGRAMFILES="$STUB_MNT/Program Files"
}

# Windows python ends lines with CR LF; the CR is dropped and the python exit status kept.
wt_profile() { python3 "$REPO/wsl/wt-profile.py" "$@" 2>&1 | tr -d '\r'; return "${PIPESTATUS[0]}"; }

# json <python expression over s> : evaluate it on the edited Windows Terminal file
json() { python3 -c 'import json,sys; s=json.load(open(sys.argv[1], encoding="utf-8")); p={x["guid"]: x for x in s["profiles"]["list"]}; print(eval(sys.argv[2]))' "$WT" "$1" | tr -d '\r'; }

# bats test_tags=feature:wsl-tools
@test "every WSL shell script parses under /bin/bash" {
  count=0
  for f in "$REPO"/local-tools/wsl/*.sh; do
    run /bin/bash -n "$f"
    assert_success
    assert_output ""
    count=$((count + 1))
  done
  test "$count" -ge 9
}

# bats test_tags=feature:wsl-tools
@test "wt-profile sets tmux-quad and the font on this distro's WSL profile only" {
  run wt_profile "$WT" Ubuntu "wsl.exe -d Ubuntu -- tmux-quad" "$FONT"
  assert_success
  assert_output "Windows Terminal Ubuntu profile now runs tmux-quad in $FONT"
  run json 'p["{ubuntu-guid}"]["commandline"]'
  assert_output "wsl.exe -d Ubuntu -- tmux-quad"
  run json 'sorted(p["{ubuntu-guid}"]["font"].items())'
  assert_output "[('face', '$FONT'), ('size', 11)]"
  run json '"commandline" in p["{debian-guid}"], "font" in p["{debian-guid}"], p["{impostor-guid}"]["commandline"], p["{powershell-guid}"]["commandline"]'
  assert_output "(False, False, 'cmd.exe', 'powershell.exe')"
  run json 's["defaultProfile"], s["copyOnSelect"], s["schemes"]'
  assert_output "('{powershell-guid}', False, [])"
}

# bats test_tags=feature:wsl-tools
@test "wt-profile --default makes the profile the default and says what the old one was" {
  run wt_profile "$WT" Ubuntu "tmux-quad-cmd" "$FONT" --default
  assert_success
  assert_output --partial "and is the default profile"
  assert_output --partial "(was {powershell-guid})"
  run json 's["defaultProfile"]'
  assert_output "{ubuntu-guid}"
}

# bats test_tags=feature:wsl-tools
@test "wt-profile run twice leaves the file untouched the second time" {
  run wt_profile "$WT" Ubuntu "tmux-quad-cmd" "$FONT" --default
  assert_success
  cp "$WT" "$BATS_TEST_TMPDIR/first.json"
  run wt_profile "$WT" Ubuntu "tmux-quad-cmd" "$FONT" --default
  assert_success
  assert_output "Windows Terminal Ubuntu profile already runs tmux-quad in $FONT and is the default"
  run cmp "$WT" "$BATS_TEST_TMPDIR/first.json"
  assert_success
}

# bats test_tags=feature:wsl-tools
@test "wt-profile --check answers yes or no and changes nothing" {
  run wt_profile --check "$WT" Ubuntu "tmux-quad-cmd"
  assert_failure 1
  assert_output "Windows Terminal Ubuntu profile does not run tmux-quad"
  run cmp "$WT" "$FX/windows-terminal.json"
  assert_success
  run wt_profile "$WT" Ubuntu "tmux-quad-cmd" "$FONT"
  assert_success
  run wt_profile --check "$WT" Ubuntu "tmux-quad-cmd"
  assert_success
  assert_output "Windows Terminal Ubuntu profile runs tmux-quad"
}

# bats test_tags=feature:wsl-tools
@test "wt-profile says when the distro has no Windows Terminal profile" {
  run wt_profile "$WT" Fedora "tmux-quad-cmd" "$FONT"
  assert_failure 1
  assert_output "no Windows Terminal profile for WSL distro 'Fedora'"
  run cmp "$WT" "$FX/windows-terminal.json"
  assert_success
}

# bats test_tags=feature:wsl-tools
@test "wt-profile will not rewrite a settings file with comments and says what to add by hand" {
  printf '// my comment\n{"profiles": {"list": []}}\n' > "$WT"
  cp "$WT" "$BATS_TEST_TMPDIR/before.json"
  run wt_profile "$WT" Ubuntu "tmux-quad-cmd" "$FONT"
  assert_failure 1
  assert_output --partial "has comments or is not plain JSON"
  assert_output --partial 'add "commandline": "tmux-quad-cmd" to the Ubuntu profile by hand'
  run cmp "$WT" "$BATS_TEST_TMPDIR/before.json"
  assert_success
}

# bats test_tags=feature:wsl-tools
@test "wt-profile reads a settings file that starts with a byte order mark" {
  { printf '\357\273\277'; cat "$FX/windows-terminal.json"; } > "$WT"
  run wt_profile "$WT" Ubuntu "tmux-quad-cmd" "$FONT"
  assert_success
  run json 'p["{ubuntu-guid}"]["commandline"]'
  assert_output "tmux-quad-cmd"
}

# bats test_tags=feature:wsl-tools
@test "winenv prints the Windows user folders in Windows and WSL form" {
  as_wsl
  run /bin/bash "$T/winenv.sh"
  assert_success
  assert_output "WIN_HOME=$STUB_MNT/$U/Test User
WIN_HOME_W=C:\\Users\\Test User
WIN_LOCALAPPDATA=$STUB_MNT/$U/Test User/AppData/Local
WIN_PROGRAMFILES=$STUB_MNT/Program Files"
}

# bats test_tags=feature:wsl-tools
@test "winenv asks Windows once and answers from its cache afterwards" {
  as_wsl
  run /bin/bash "$T/winenv.sh"
  assert_success
  first="$output"
  assert_file_exist "$TEST_HOME/.cache/claude-config/winenv"
  : > "$STUB_LOG"
  run /bin/bash -c '. "$1"; printf "%s|%s\n" "$WIN_HOME_W" "$WIN_PROGRAMFILES"' _ "$T/winenv.sh"
  assert_success
  assert_output "C:\\Users\\Test User|$STUB_MNT/Program Files"
  run cat "$STUB_LOG"
  assert_output ""
}

# bats test_tags=feature:wsl-tools
@test "winenv says it is not on WSL when Windows gives no user folder, and caches nothing" {
  as_wsl
  export STUB_NO_PROFILE=1
  run /bin/bash "$T/winenv.sh"
  assert_failure 1
  assert_output "winenv.sh: cmd.exe gave no %USERPROFILE% (not WSL?)"
  assert_file_not_exist "$TEST_HOME/.cache/claude-config/winenv"
}

# bats test_tags=feature:wsl-tools
@test "game guard names a running game and logs the refused request" {
  as_wsl
  export STUB_GAME=deadlock
  run /bin/bash "$T/game-guard.sh" win.sh show Demo
  assert_success
  assert_output --partial "game: deadlock"
  assert_output --partial "deferred: deadlock is running; not touching any window."
  run cat "$DEFERRED"
  assert_a_line_matches '^[0-9-]+ [0-9:]+ ET  game=deadlock  refused: win\.sh show Demo$'
}

# bats test_tags=feature:wsl-tools
@test "game guard is silent and logs nothing when no game is running" {
  as_wsl
  run /bin/bash "$T/game-guard.sh" win.sh show Demo
  assert_failure 1
  assert_output ""
  assert_file_not_exist "$DEFERRED"
  run cat "$STUB_LOG"
  assert_output --partial "Get-Process -Name ('deadlock','project8')"
}

# bats test_tags=feature:wsl-tools
@test "game guard looks for the games named in GAME_GUARD_PROCS" {
  as_wsl
  export GAME_GUARD_PROCS="alpha beta gamma"
  run /bin/bash "$T/game-guard.sh"
  assert_failure 1
  run cat "$STUB_LOG"
  assert_output --partial "Get-Process -Name ('alpha','beta','gamma')"
}

# bats test_tags=feature:wsl-tools
@test "GAME_GUARD=off allows everything without asking Windows" {
  as_wsl
  export STUB_GAME=deadlock GAME_GUARD=off
  run /bin/bash "$T/game-guard.sh" win.sh show Demo
  assert_failure 1
  assert_output ""
  run cat "$STUB_LOG"
  assert_output ""
}

# bats test_tags=feature:wsl-tools
@test "game guard reports no game on a machine that is not WSL" {
  as_wsl
  export STUB_WSL=0 STUB_GAME=deadlock
  run /bin/bash "$T/game-guard.sh" win.sh show Demo
  assert_failure 1
  assert_output ""
  run cat "$STUB_LOG"
  assert_output ""
}

# bats test_tags=feature:wsl-tools
@test "the window tools refuse to run on a machine that is not WSL" {
  as_wsl
  export STUB_WSL=0
  for tool in win.sh term-open.sh term-close.sh screen-capture.sh open-streak.sh; do
    run /bin/bash "$T/$tool" Demo 1
    assert_failure 1
    assert_output --partial "$tool: WSL only (this is "
  done
  run cat "$STUB_LOG"
  assert_output ""
}

# bats test_tags=feature:wsl-tools
@test "win.sh hands the window request to PowerShell and returns its answer" {
  as_wsl
  export EVSHOW_STATE="$BATS_TEST_TMPDIR/state" STUB_PS_OUT="closed 123" STUB_PS_EXIT=7
  run /bin/bash "$T/win.sh" close 123 -4 "two words"
  assert_failure 7
  assert_output --partial "closed 123"
  run cat "$STUB_LOG"
  assert_output --partial "winctl.ps1"
  assert_output --partial "WINCTL_LINE=close|123|-4|two words"
}

# bats test_tags=feature:wsl-tools
@test "win.sh will not show a window while a game is running" {
  as_wsl
  export EVSHOW_STATE="$BATS_TEST_TMPDIR/state" STUB_GAME=project8
  run /bin/bash "$T/win.sh" show Demo 0 0 800 600
  assert_failure 3
  assert_output --partial "not shown: a full-screen game is running (game-guard.sh)"
  run cat "$STUB_LOG"
  refute_output --partial "winctl.ps1"
  run cat "$DEFERRED"
  assert_output --partial "refused: win.sh show Demo 0 0 800 600"
}

# bats test_tags=feature:wsl-tools
@test "win.sh will not move on to the next window while a game is running" {
  as_wsl
  export EVSHOW_STATE="$BATS_TEST_TMPDIR/state" STUB_GAME=project8
  run /bin/bash "$T/win.sh" next 1001 Demo
  assert_failure 3
  assert_output --partial "not shown: a full-screen game is running (game-guard.sh)"
  run cat "$STUB_LOG"
  refute_output --partial "winctl.ps1"
  run cat "$DEFERRED"
  assert_output --partial "refused: win.sh next 1001 Demo"
}

# bats test_tags=feature:wsl-tools
@test "win-app finds Firefox under the Windows Program Files folder" {
  as_wsl
  fake_firefox
  run /bin/bash "$T/win-app.sh" --path firefox
  assert_success
  assert_output "$FIREFOX"
}

# bats test_tags=feature:wsl-tools
@test "win-app gives Firefox a file URL for a Linux path, with the safe mode key disabled" {
  as_wsl
  fake_firefox
  page="$BATS_TEST_TMPDIR/my page.html"
  : > "$page"
  run /bin/bash "$T/win-app.sh" firefox -new-window "$page"
  assert_success
  url="file:///W:$(printf '%s' "$page" | sed 's/ /%20/g')"
  run cat "$STUB_LOG"
  assert_output --partial "app-arg -new-window
app-arg $url
WSLENV=MOZ_DISABLE_SAFE_MODE_KEY
MOZ_DISABLE_SAFE_MODE_KEY=1"
}

# bats test_tags=feature:wsl-tools
@test "win-app opens nothing while a game is running and logs the request" {
  as_wsl
  fake_firefox
  export STUB_GAME=deadlock
  run /bin/bash "$T/win-app.sh" firefox https://example.invalid/
  assert_failure 3
  assert_output "not hidden: a full-screen game is running"
  run cat "$STUB_LOG"
  refute_output --partial "app-arg"
  run cat "$DEFERRED"
  assert_output --partial "game=deadlock  refused: win-app.sh firefox https://example.invalid/"
}

# bats test_tags=feature:wsl-tools
@test "win-app --hidden asks for a hidden window by title and records its handle" {
  as_wsl
  fake_firefox
  export EVSHOW_STATE="$BATS_TEST_TMPDIR/state" STUB_PS_OUT="hidden: 4242 stub window"
  mkdir -p "$EVSHOW_STATE"
  run /bin/bash "$T/win-app.sh" --hidden firefox https://example.invalid/
  assert_failure 2
  assert_output --partial "not hidden: --title is required"
  run /bin/bash "$T/win-app.sh" --hidden --title mytitle firefox https://example.invalid/
  assert_success
  assert_output "hidden: 4242 stub window"
  run cat "$STUB_LOG"
  assert_output --partial "WINCTL_LINE=hidden|firefox|W:"
  assert_output --partial "firefox.exe|-new-window https://example.invalid/|mytitle|20"
  run cat "$EVSHOW_STATE/hidden"
  assert_a_line_matches 'hidden: 4242 stub window$'
}

# bats test_tags=feature:wsl-tools
@test "win-app says VS Code is retired and rejects an unknown app" {
  as_wsl
  run /bin/bash "$T/win-app.sh" code notes.md
  assert_failure 2
  assert_output 'not opened: VS Code is retired; use file-page.sh "<path>"'
  run /bin/bash "$T/win-app.sh" notepad
  assert_failure 2
  assert_output "win-app.sh: unknown app notepad (firefox, wt)"
}

# bats test_tags=feature:wsl-tools
@test "screen-capture asks PowerShell for a PNG in the Windows home and prints its WSL path" {
  as_wsl
  run /bin/bash "$T/screen-capture.sh" shot
  assert_success
  assert_output "$STUB_MNT/$U/Test User/shot.png"
  run cat "$STUB_LOG"
  assert_output --partial 'screen-capture.ps1 C:\Users\Test User\shot.png'
}

# bats test_tags=feature:wsl-tools
@test "screen-capture prints no path when PowerShell fails" {
  as_wsl
  export STUB_PS_EXIT=1
  run /bin/bash "$T/screen-capture.sh" shot
  assert_failure 1
  assert_output ""
}

# bats test_tags=feature:wsl-tools
@test "term-open starts a tmux session in a hidden terminal and types the command into it" {
  as_wsl
  stand_in win-app.sh
  run /bin/bash "$T/term-open.sh" demo-1 "$BATS_TEST_TMPDIR" echo hello world
  assert_success
  assert_output "opened demo-1 HWND=4242 (hidden: 4242 10 10 stub-title (create 5 12))"
  run cat "$STUB_LOG"
  assert_output --partial "tmux new-session -d -s demo-1 -c $BATS_TEST_TMPDIR -x 200 -y 50"
  assert_output --partial "win-app.sh --hidden --title demo-1 wt -w new -p Ubuntu --title demo-1 --suppressApplicationTitle wsl.exe -d Ubuntu -- tmux attach -t demo-1"
  assert_output --partial "tmux send-keys -t demo-1 C-u
tmux send-keys -t demo-1 -l echo hello world
tmux send-keys -t demo-1 Enter"
}

# bats test_tags=feature:wsl-tools
@test "term-open kills its tmux session when the window cannot be opened hidden" {
  as_wsl
  stand_in win-app.sh
  export STUB_APP_FAIL="title not loaded"
  run /bin/bash "$T/term-open.sh" demo-2 "$BATS_TEST_TMPDIR" echo hello
  assert_failure 1
  assert_output "not hidden: title not loaded"
  run cat "$STUB_LOG"
  assert_output --partial "tmux kill-session -t demo-2"
  refute_output --partial "send-keys"
}

# bats test_tags=feature:wsl-tools
@test "term-open fails when the opened window cannot be found" {
  as_wsl
  stand_in win-app.sh
  stand_in win.sh
  export STUB_APP_SILENT=1 STUB_WIN_EXIT=1
  run /bin/bash "$T/term-open.sh" demo-6 "$BATS_TEST_TMPDIR" echo hello
  assert_failure 1
  refute_output --partial "opened demo-6"
  run cat "$STUB_LOG"
  assert_output --partial "tmux kill-session -t demo-6"
  refute_output --partial "send-keys"
}

# bats test_tags=feature:wsl-tools
@test "term-open does nothing while a game is running" {
  as_wsl
  stand_in win-app.sh
  export STUB_GAME=deadlock
  run /bin/bash "$T/term-open.sh" demo-3 "$BATS_TEST_TMPDIR" echo hello
  assert_failure 3
  assert_output --partial "not opened: a full-screen game is running (game-guard.sh)"
  run cat "$STUB_LOG"
  refute_output --partial "tmux"
  refute_output --partial "win-app.sh --hidden"
}

# bats test_tags=feature:wsl-tools
@test "term-close closes the window, kills the session and reports a failed close" {
  as_wsl
  stand_in win.sh
  export STUB_WIN_EXIT=5
  run /bin/bash "$T/term-close.sh" demo-4 4242
  assert_failure 5
  run cat "$STUB_LOG"
  assert_output "win.sh close 4242
tmux kill-session -t demo-4"
}

# bats test_tags=feature:wsl-tools
@test "the terminal volume service runs the scheduled task the installer registers for an existing script" {
  unit="$REPO/wsl/terminal-volume.service"
  run grep -x 'ExecStart=/mnt/c/Windows/System32/schtasks.exe /run /tn "Pin Windows Terminal Volume"' "$unit"
  assert_success
  run grep -x 'WantedBy=default.target' "$unit"
  assert_success
  assert_file_exist "$REPO/wsl/terminal-volume.ps1"
  code="$BATS_TEST_TMPDIR/install-code"   # install.sh without its comment lines
  grep -v '^[[:space:]]*#' "$REPO/install.sh" > "$code"
  run grep -F "Register-ScheduledTask -TaskName 'Pin Windows Terminal Volume'" "$code"
  assert_success
  run grep -F 'cp "$R/wsl/terminal-volume.ps1" ' "$code"
  assert_success
  run grep -F -- '-File $WP\\Scripts\\terminal-volume.ps1' "$code"
  assert_success
  run grep -F 'link "$R/wsl/terminal-volume.service" ' "$code"
  assert_success
  run grep -F 'systemctl --user enable terminal-volume.service' "$code"
  assert_success
}
