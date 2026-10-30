#!/bin/bash
# usage: win-app.sh firefox|code|wt [args...]   Runs the Windows program, found from %ProgramFiles% / %LOCALAPPDATA%
# (via winenv.sh) or PATH, so no user name is written anywhere. `win-app.sh --path <app>` prints the path instead.
#   win-app.sh --hidden [--title "<t>"] firefox|code|wt [args...]
#        Opens the window cloaked from its first moment: ONE PowerShell process registers a WinEvent hook (CREATE/SHOW/
#        FOREGROUND/NAMECHANGE; no polling, it sleeps in its message loop), launches the app, and on every new top-level window
#        of the app's process family hides it before its first paint (DWMWA_CLOAK is tried but another process gets
#        E_ACCESSDENIED, so: off-screen first, then WS_EX_LAYERED alpha 0 + WS_EX_TOOLWINDOW + taskbar DeleteTab), moves it to
#        -6000,0 and gives the foreground back if it was taken.
#        Prints `hidden: HWND <visible-ms> <hidden-ms> <title> (create <create-ms> <hide-done-ms>)` per window (ms since launch):
#        visible-ms = when the window first had WS_VISIBLE (its SHOW event; CREATE if created visible), hidden-ms = when the hide
#        was in place (= visible-ms when it was hidden before it was ever visible); the difference bounds the time a frame could
#        have been composed. The `hide-log:` lines carry every event. Registers the HWND in this
#        session's launched.txt (token = --title if given, else the loaded title), appends the lines to <state>/hidden, and
#        exits when the title is loaded (contains --title, or is not the bare app name) or after 20 s with
#        `not hidden: <reason>` (exit 1). `win.sh show|start|next` un-cloak and place; `win.sh close-cloaked` closes leftovers.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/winenv.sh"
p=""; hidden=""; title=""
while :; do case "${1:-}" in
  --path) p=1; shift;; --hidden) hidden=1; shift;; --title) title="${2:-}"; shift 2;; *) break;; esac; done
app="${1:?usage: win-app.sh [--path] [--hidden [--title t]] firefox|code|wt [args...]}"; shift
case "$app" in
  firefox) c=("${WIN_PROGRAMFILES:-/mnt/c/Program Files}/Mozilla Firefox/firefox.exe" "/mnt/c/Program Files (x86)/Mozilla Firefox/firefox.exe" "$(command -v firefox.exe)") ;;
  code)    c=("${WIN_LOCALAPPDATA:-/nonexistent}/Programs/Microsoft VS Code/bin/code" "${WIN_PROGRAMFILES:-/mnt/c/Program Files}/Microsoft VS Code/bin/code" "$(command -v code)") ;;
  wt)      c=("$(command -v wt.exe)" "${WIN_LOCALAPPDATA:-/nonexistent}/Microsoft/WindowsApps/wt.exe") ;;
  *)       echo "win-app.sh: unknown app $app (firefox, code, wt)" >&2; exit 2 ;;
esac
for x in "${c[@]}"; do [ -n "$x" ] && [ -x "$x" ] && { exe="$x"; break; }; done
[ -n "${exe:-}" ] || { echo "win-app.sh: $app not found (tried: ${c[*]})" >&2; exit 1; }
[ -n "$p" ] && { echo "$exe"; exit 0; }
"$HOME/.claude/local-tools/game-guard.sh" "win-app.sh ${hidden:+--hidden }$app $*" >/dev/null && exit 3   # a full-screen game has the screen: open nothing
[ -z "$hidden" ] && exec "$exe" "$@"
grep -qi microsoft /proc/version 2>/dev/null || { echo "win-app.sh: --hidden is WSL only" >&2; exit 1; }
. "$HOME/.claude/local-tools/evsession.sh"
ev_export || { echo "not hidden: no session state dir (set EVSHOW_STATE)"; exit 1; }
D=$(ev_state_dir)
q() { for a in "$@"; do case "$a" in *" "*|"") printf ' "%s"' "$a";; *) printf ' %s' "$a";; esac; done; }
if [ "$app" = code ]; then   # Code.exe itself, not bin/code (the Remote-WSL launcher needs ~/.vscode-server for the running VS Code version and fails
  # after a VS Code update until a WSL window is opened by hand); Linux paths are passed as \\wsl.localhost\... paths
  exe="${exe%/bin/code}/Code.exe"; [ -x "$exe" ] || { echo "not hidden: $exe not found"; exit 1; }
  m=(); for a in "$@"; do case "$a" in /*) [ -e "$a" ] && a=$(wslpath -w "$a");; esac; m+=("$a"); done
  case " $* " in *" -n "*|*" --new-window "*) ;; *) m=(-n "${m[@]}");; esac   # a running VS Code would otherwise open the file in ITS window (nothing new to hide)
  args="$(q "${m[@]}")"
else args="$(q "$@")"; fi
out=$(WSLENV="${WSLENV:+$WSLENV:}WINCTL_LINE" WINCTL_LINE="hidden|$app|$(wslpath -w "$exe")|${args# }|$title|${EVSHOW_HIDE_TIMEOUT:-20}" \
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")"); rc=$?
printf '%s\n' "$out" | tr -d '\r'
printf '%s\n' "$out" | tr -d '\r' | grep '^hidden: ' | sed "s/^/$(TZ=America/New_York date +%T.%N | cut -c1-12) /" >> "$D/hidden"
# linger: for ${EVSHOW_LINGER_MS:-6000} ms a detached winctl keeps each hidden window off the taskbar and hidden on events only
# (WT registers its taskbar button ~1.7 s in, Firefox moves its window back ~1 s in; both after the title loaded and this exited)
lay=1; [ "$app" = code ] && [ "${EVSHOW_CODE_REGION:-}" = 1 ] && lay=0
for h in $(printf '%s\n' "$out" | tr -d '\r' | awk '/^hidden: /{print $2}'); do
  WSLENV="${WSLENV:+$WSLENV:}WINCTL_LINE" WINCTL_LINE="linger|$h|$lay|${EVSHOW_LINGER_MS:-6000}" setsid nohup \
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")" >/dev/null 2>&1 < /dev/null &
done
exit $rc
