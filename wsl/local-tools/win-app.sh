#!/bin/bash
# usage: win-app.sh firefox|code|wt [args...]   Runs the Windows program, found from %ProgramFiles% / %LOCALAPPDATA%
# (via winenv.sh) or PATH, so no user name is written anywhere. `win-app.sh --path <app>` prints the path instead.
#   win-app.sh --hidden [--title "<t>"] firefox|code|wt [args...]
#        Opens the window cloaked from its first moment: ONE PowerShell process registers a WinEvent hook (CREATE/SHOW/
#        FOREGROUND/NAMECHANGE; no polling, it sleeps in its message loop), launches the app, and on every new top-level window
#        of the app's process family sets DWMWA_CLOAK=1, moves it to -6000,0 and gives the foreground back if it was taken.
#        Prints `hidden: HWND <create-ms> <cloak-ms> <title>` per window (ms since launch), registers the HWND in this
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
if [ "$app" = code ]; then   # bin/code is the Remote-WSL launcher script (it starts Code.exe with --remote and Linux paths): run it through wsl.exe, hook Code.exe's windows
  args="$(q -d "${WSL_DISTRO_NAME:-Ubuntu}" -e "$exe" "$@")"; exe=/mnt/c/Windows/System32/wsl.exe
else args="$(q "$@")"; fi
out=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")" \
      "hidden|$app|$(wslpath -w "$exe")|${args# }|$title|${EVSHOW_HIDE_TIMEOUT:-20}"); rc=$?
printf '%s\n' "$out" | tr -d '\r'
printf '%s\n' "$out" | tr -d '\r' | grep '^hidden: ' | sed "s/^/$(TZ=America/New_York date +%T.%N | cut -c1-12) /" >> "$D/hidden"
exit $rc
