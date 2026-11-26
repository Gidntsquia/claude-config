#!/bin/bash
# macOS opener of the evaluator; same command line, output-line prefixes and exit codes as the WSL win-app.sh.
#   win-app.sh --hidden --title "<t>" firefox [-new-window] "<abs path or url>"
#        Records the item and puts NOTHING on screen; prints `hidden: <id> 0 0 <t> (deferred)`. `win.sh show "<t>" ...`
#        (the watcher, on the answer) shows it:
#          a page file-page.sh built  -> its SOURCE file in `less -R`, inside your terminal (a pane or a tab: win.sh)
#          an http(s) URL, a .html file, anything else -> `open "<it>"`: your default browser or app, never scripted or closed
#        No browser is started by this tool. Failure is ONE line, exit 1: `not hidden: no such file: <path>` |
#        `not hidden: no session state dir (set EVSHOW_STATE)`. Exit 2: usage (`--title is required`, unknown app).
#   win-app.sh code ...       prints `not opened: VS Code is retired; use file-page.sh "<path>"`, exit 2, starts nothing.
#   win-app.sh --path firefox prints `open` (web items go to the default browser).
#   win-app.sh firefox <args> (no --hidden) runs `open` on them; the evaluator never uses it.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$here/maclib.sh"
p=""; hidden=""; title=""
while :; do case "${1:-}" in
  --path) p=1; shift;; --hidden) hidden=1; shift;; --title) title="${2:-}"; shift; [ $# -gt 0 ] && shift;; *) break;; esac; done
app="${1:-}"; [ -n "$app" ] || { echo "usage: win-app.sh [--path] [--hidden --title t] firefox [args...]" >&2; exit 2; }
shift
[ "$app" = code ] && { echo 'not opened: VS Code is retired; use file-page.sh "<path>"'; exit 2; }
[ "$app" = firefox ] || { echo "win-app.sh: unknown app $app (firefox)" >&2; exit 2; }
if [ -n "$p" ]; then echo open; exit 0; fi
target=""; for a in "$@"; do case "$a" in -*) ;; *) target="$a";; esac; done
if [ -z "$hidden" ]; then exec "$OPEN_BIN" ${target:+"$target"}; fi
[ -n "$title" ] || { echo "not hidden: --title is required (the item is found by it)"; exit 2; }
[ -n "$target" ] || { echo "not hidden: no path or url given"; exit 2; }
mac_state || { echo "not hidden: no session state dir (set EVSHOW_STATE)"; exit 1; }
kind=web; line=""
case "$target" in
  /*|~/*|./*|../*) f="$target"; case "$f" in "~/"*) f="$HOME/${f#\~/}";; esac
      [ -e "$f" ] || { echo "not hidden: no such file: $target"; exit 1; }
      target="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
      if [ -s "$target.src" ]; then   # a file-page.sh page: its source is what is shown
        src=$(sed -n 1p "$target.src"); line=$(sed -n 2p "$target.src")
        [ -f "$src" ] || { echo "not hidden: no such file: $src (the source of $target)"; exit 1; }
        kind=file; target=$src
      fi;;
esac
id=$(inew "$kind" "$title" "$target")
[ -n "$line" ] && iset "$id" line "$line"
line="hidden: $id 0 0 $title (deferred)"
echo "$(et) $line" >> "$D/hidden"
echo "$line"
