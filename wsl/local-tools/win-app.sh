#!/bin/bash
# usage: win-app.sh firefox|wt [args...]   Runs the Windows program, found from %ProgramFiles% / %LOCALAPPDATA%
# (via winenv.sh) or PATH, so no user name is written anywhere. `win-app.sh --path <app>` prints the path instead.
#   win-app.sh code ...   (any mode) prints `not opened: VS Code is retired; use file-page.sh "<path>"`, exit 2, starts nothing:
#        .md, logs, text and source are shown as a page in Firefox (file-page.sh builds it).
#   win-app.sh --hidden [--title "<t>"] firefox|wt [args...]
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
#        exits when the title is loaded (it contains --title, which is required) or after 20 s.
#        Failure is ONE line `not hidden: <cause>`; exit 1 unless noted:
#          title not loaded within Ns (want '<t>'; hidden N window(s): '<titles seen>')   the page/file did not load under that title
#          <App> dialog: <its text>                      the app answered with a dialog; it is closed, never shown
#          a full-screen game is running                 exit 3; also appended to ~/.cache/claude-config/game-deferred.log
#          error: <PowerShell message> | <exe> not found | --title is required (exit 2)
#        A new window is this run's when its process is the launched pid, a descendant, or an image under the app's install folder.
#        firefox (both modes): an argument that is an existing Linux path becomes a file:/// URL (Firefox cannot load a bare
#          Linux path); --hidden adds -new-window when it is missing (a tab in a running window would be nothing new to hide).
#        `win.sh show|start|next` un-cloak and place; `win.sh close-cloaked` closes leftovers.
#        GAME_GUARD_CMD=<script> replaces game-guard.sh, GAME_DEFERRED_LOG=<file> the log (tests).
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/winenv.sh"
p=""; hidden=""; title=""
while :; do case "${1:-}" in
  --path) p=1; shift;; --hidden) hidden=1; shift;; --title) title="${2:-}"; shift 2;; *) break;; esac; done
app="${1:?usage: win-app.sh [--path] [--hidden [--title t]] firefox|wt [args...]}"; shift
[ "$app" = code ] && { echo 'not opened: VS Code is retired; use file-page.sh "<path>"'; exit 2; }
case "$app" in
  firefox) c=("${WIN_PROGRAMFILES:-/mnt/c/Program Files}/Mozilla Firefox/firefox.exe" "/mnt/c/Program Files (x86)/Mozilla Firefox/firefox.exe" "$(command -v firefox.exe)") ;;
  wt)      c=("$(command -v wt.exe)" "${WIN_LOCALAPPDATA:-/nonexistent}/Microsoft/WindowsApps/wt.exe") ;;
  *)       echo "win-app.sh: unknown app $app (firefox, wt)" >&2; exit 2 ;;
esac
for x in "${c[@]}"; do [ -n "$x" ] && [ -x "$x" ] && { exe="$x"; break; }; done
[ -n "${exe:-}" ] || { echo "win-app.sh: $app not found (tried: ${c[*]})" >&2; exit 1; }
[ -n "$p" ] && { echo "$exe"; exit 0; }
if g=$("${GAME_GUARD_CMD:-$HOME/.claude/local-tools/game-guard.sh}" 2>/dev/null); then   # a full-screen game has the screen: open nothing, say so, log it
  gl="${GAME_DEFERRED_LOG:-$HOME/.cache/claude-config/game-deferred.log}"; mkdir -p "$(dirname "$gl")"
  echo "$(TZ=America/New_York date '+%F %T') ET  game=${g#game: }  refused: win-app.sh ${hidden:+--hidden }${title:+--title $title }$app $*  -> not hidden: a full-screen game is running" >> "$gl"
  echo "not hidden: a full-screen game is running"; exit 3
fi
if [ "$app" = firefox ]; then   # an existing Linux path becomes a file:/// URL (\\wsl.localhost\... -> file://///wsl.localhost/...)
  m=(); for a in "$@"; do case "$a" in /*) [ -e "$a" ] && a=$(python3 -I -c 'import sys, urllib.parse as u; print("file:///" + u.quote(sys.argv[1].replace("\\", "/"), safe="/:"))' "$(wslpath -w "$a")");; esac; m+=("$a"); done
  set -- "${m[@]}"
fi
# Firefox opens its "Troubleshoot Mode" prompt instead of the page when Shift is down at launch; this makes it ignore the key
[ "$app" = firefox ] && export MOZ_DISABLE_SAFE_MODE_KEY=1 WSLENV="${WSLENV:+$WSLENV:}MOZ_DISABLE_SAFE_MODE_KEY"
[ -z "$hidden" ] && exec "$exe" "$@"
grep -qi microsoft /proc/version 2>/dev/null || { echo "win-app.sh: --hidden is WSL only" >&2; exit 1; }
. "$HOME/.claude/local-tools/evsession.sh"
ev_export || { echo "not hidden: no session state dir (set EVSHOW_STATE)"; exit 1; }
[ -n "$title" ] || { echo "not hidden: --title is required (a window counts as loaded only when its title holds it)"; exit 2; }
D=$(ev_state_dir)
q() { for a in "$@"; do case "$a" in *" "*|"") printf ' "%s"' "$a";; *) printf ' %s' "$a";; esac; done; }
if [ "$app" = firefox ]; then case " $* " in *" -new-window "*|*" --new-window "*) ;; *) set -- -new-window "$@";; esac; fi
args="$(q "$@")"
out=$(WSLENV="${WSLENV:+$WSLENV:}WINCTL_LINE" WINCTL_LINE="hidden|$app|$(wslpath -w "$exe")|${args# }|$title|${EVSHOW_HIDE_TIMEOUT:-20}" \
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")"); rc=$?
printf '%s\n' "$out" | tr -d '\r'
printf '%s\n' "$out" | tr -d '\r' | grep '^hidden: ' | sed "s/^/$(TZ=America/New_York date +%T.%N | cut -c1-12) /" >> "$D/hidden"
# linger: for ${EVSHOW_LINGER_MS:-6000} ms a detached winctl keeps each hidden window off the taskbar and hidden on events only
# (WT registers its taskbar button ~1.7 s in, Firefox moves its window back ~1 s in; both after the title loaded and this exited)
for h in $(printf '%s\n' "$out" | tr -d '\r' | awk '/^hidden: /{print $2}'); do
  WSLENV="${WSLENV:+$WSLENV:}WINCTL_LINE" WINCTL_LINE="linger|$h|1|${EVSHOW_LINGER_MS:-6000}" setsid nohup \
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/winctl.ps1")" >/dev/null 2>&1 < /dev/null &
done
exit $rc
