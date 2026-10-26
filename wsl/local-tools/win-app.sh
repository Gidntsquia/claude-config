#!/bin/bash
# usage: win-app.sh firefox|code|wt [args...]   Runs the Windows program, found from %ProgramFiles% / %LOCALAPPDATA%
# (via winenv.sh) or PATH, so no user name is written anywhere. `win-app.sh --path <app>` prints the path instead.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/winenv.sh"
p=""; [ "$1" = "--path" ] && { p=1; shift; }
app="${1:?usage: win-app.sh [--path] firefox|code|wt [args...]}"; shift
case "$app" in
  firefox) c=("${WIN_PROGRAMFILES:-/mnt/c/Program Files}/Mozilla Firefox/firefox.exe" "/mnt/c/Program Files (x86)/Mozilla Firefox/firefox.exe" "$(command -v firefox.exe)") ;;
  code)    c=("${WIN_LOCALAPPDATA:-/nonexistent}/Programs/Microsoft VS Code/bin/code" "${WIN_PROGRAMFILES:-/mnt/c/Program Files}/Microsoft VS Code/bin/code" "$(command -v code)") ;;
  wt)      c=("$(command -v wt.exe)" "${WIN_LOCALAPPDATA:-/nonexistent}/Microsoft/WindowsApps/wt.exe") ;;
  *)       echo "win-app.sh: unknown app $app (firefox, code, wt)" >&2; exit 2 ;;
esac
for x in "${c[@]}"; do [ -n "$x" ] && [ -x "$x" ] && { [ -n "$p" ] && { echo "$x"; exit 0; }; exec "$x" "$@"; }; done
echo "win-app.sh: $app not found (tried: ${c[*]})" >&2; exit 1
