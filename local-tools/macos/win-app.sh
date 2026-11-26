#!/bin/bash
# macOS opener of the evaluator; same command line, output-line prefixes and exit codes as the WSL win-app.sh.
#   win-app.sh --hidden --title "<t>" firefox [-new-window] "<abs path or url>"
#        Records the item and opens NO window (macOS cannot open a window out of sight); prints
#        `hidden: <id> 0 0 <t> (deferred)`. `win.sh show "<t>" ...` (the watcher, on the answer) opens it in this run's Firefox,
#        or in Safari when /Applications/Firefox.app is missing. The page <title> or file name must hold <t>.
#        An existing path becomes a file:// URL. Failure is ONE line, exit 1: `not hidden: no such file: <path>` |
#        `not hidden: no session state dir (set EVSHOW_STATE)`. Exit 2: usage (`--title is required`, unknown app).
#   win-app.sh code ...       prints `not opened: VS Code is retired; use file-page.sh "<path>"`, exit 2, starts nothing.
#   win-app.sh --path firefox prints the browser the show step will use (the Firefox binary, or `Safari`).
#   win-app.sh firefox <args> (no --hidden) opens them in the user's own browser with `open -a`; the evaluator never uses it.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
. "$here/maclib.sh"
p=""; hidden=""; title=""
while :; do case "${1:-}" in
  --path) p=1; shift;; --hidden) hidden=1; shift;; --title) title="${2:-}"; shift; [ $# -gt 0 ] && shift;; *) break;; esac; done
app="${1:-}"; [ -n "$app" ] || { echo "usage: win-app.sh [--path] [--hidden --title t] firefox [args...]" >&2; exit 2; }
shift
[ "$app" = code ] && { echo 'not opened: VS Code is retired; use file-page.sh "<path>"'; exit 2; }
[ "$app" = firefox ] || { echo "win-app.sh: unknown app $app (firefox)" >&2; exit 2; }
if [ -n "$p" ]; then if have_firefox; then echo "$FFBIN"; else echo Safari; fi; exit 0; fi
target=""; for a in "$@"; do case "$a" in -*) ;; *) target="$a";; esac; done
if [ -z "$hidden" ]; then
  if have_firefox; then exec open -a "$FFAPP" ${target:+"$target"}; else exec open -a Safari ${target:+"$target"}; fi
fi
[ -n "$title" ] || { echo "not hidden: --title is required (a window counts as loaded only when its title holds it)"; exit 2; }
[ -n "$target" ] || { echo "not hidden: no path or url given"; exit 2; }
mac_state || { echo "not hidden: no session state dir (set EVSHOW_STATE)"; exit 1; }
case "$target" in
  /*|~/*|./*|../*) f="$target"; case "$f" in "~/"*) f="$HOME/${f#\~/}";; esac
      [ -e "$f" ] || { echo "not hidden: no such file: $target"; exit 1; }
      target=$(file_url "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")");;
esac
id=$(inew web "$title" "$target")
line="hidden: $id 0 0 $title (deferred)"
echo "$(et) $line" >> "$D/hidden"
echo "$line"
