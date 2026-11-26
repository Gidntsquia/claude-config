#!/bin/bash
# usage: open-streak.sh [n=10] [firefox|page ...]
# Proof that hidden opens end in a real, loaded, visible window. Per app (firefox, then page), n times:
#   firefox: a token page ost-<tok>.html -> win-app.sh --hidden --title ost-<tok> firefox
#   page:    a token ost-<tok>.md -> file-page.sh (the file page every .md, log and source file is shown as) -> its `page:` line's
#            html and title -> win-app.sh --hidden --title "<title>" firefox "<html>"
#   then win.sh showcheck "ost-<tok>" 1030 0 1530 1400
#   (= show + the checks, one process) -> win.sh close HWND + close-cloaked.
# Checks: the shown: rect is the asked one (within 16 px), the HWND has cloaked=0 and the token in its title, and a
# capture of the window's content area (the rect less 170 px on top, 50 below, 20 at the sides: the app's own bars would make an
# empty window look painted) is under 98 % one colour.
# Prints one line per open:
#   open N <app>: shown HWND L T W H title-ok cloaked=0 nonblank <p>%     (p = share of the content area that is NOT its main colour)
#   open N <app>: FAIL <stage>: <reason>          stage = build (file-page.sh's `not built:` line) | open | show | rect | list | blank | close; reason = the helper's own line
# and last `streak: firefox <k>/<n> shown, page <k>/<n> shown`. Exit 0 only when every open of every app was shown.
# While a full-screen game runs: `not run: a full-screen game is running`, exit 3 (GAME_GUARD_CMD=<script> replaces game-guard.sh).
# OST_KEEP=<dir> keeps each content-area capture as <dir>/<app>-<N>.png and the helper's show-note:/show-tries: lines in <dir>/notes.txt. A window that is covered, minimized or closed by someone
# else between `show` and the capture fails stage `show` with that reason, the age of the last user input and the focused window.
# Every line is also appended, with its ET time, to ~/.cache/claude-config/open-streak.log (OST_LOG=<file> replaces it).
# Uses its own state dir, so it never touches an evaluator session's windows. The windows appear at the right of the screen
# for about a second each, topmost, without taking focus, and mouse clicks pass through them to the window underneath
# (so it can run while you use the screen: a click of yours cannot minimize or close a test window).
set -u
n=10; case "${1:-}" in ''|*[!0-9]*) ;; *) n=$1; shift;; esac
apps=("$@"); [ ${#apps[@]} -gt 0 ] || apps=(firefox page)
T="$HOME/.claude/local-tools"
grep -qi microsoft /proc/version 2>/dev/null || { echo "open-streak.sh: WSL only (this is $(uname))" >&2; exit 1; }
"${GAME_GUARD_CMD:-$T/game-guard.sh}" >/dev/null 2>&1 && { echo "not run: a full-screen game is running"; exit 3; }
S="$(mktemp -d)"; export EVSHOW_STATE="$S/state"; mkdir -p "$EVSHOW_STATE"; trap 'rm -rf "$S"' EXIT
X=1030; Y=0; W=1530; H=1400
one() {  # one open of app $1, number $2; prints the line, returns 0 when shown
  local app=$1 i=$2 tok f out line hwnd l t w h z p rc k sv tries pg
  tok="$(tr -dc a-z0-9 </dev/urandom | head -c6)"
  if [ "$app" = firefox ]; then f="$S/ost-$tok.html"
    { echo "<!doctype html><title>ost-$tok</title><body style='margin:0;font:28px sans-serif'><h1>ost-$tok</h1>"
      for k in $(seq 1 30); do echo "<div style='height:24px;margin:14px 0;background:#2a6f97'></div>"; done; } > "$f"
    out=$("$T/win-app.sh" --hidden --title "ost-$tok" firefox -new-window "$f" 2>&1 | tr -d '\r'); rc=${PIPESTATUS[0]}   # a Linux path on purpose: the helper makes it a file:/// URL
  else f="$S/ost-$tok.md"
    { echo "# ost-$tok"; for k in $(seq 1 70); do echo "- line $k of ost-$tok: the quick brown fox jumps over the lazy dog, $k times, and comes back again"; done; } > "$f"
    pg=$("$T/file-page.sh" "$f" 2>&1); rc=$?
    case "$pg" in "page: "*"|"*) ;; *) echo "open $i $app: FAIL build: ${pg:-exit $rc}"; return 1;; esac
    [ "$rc" -eq 0 ] || { echo "open $i $app: FAIL build: exit $rc: $pg"; return 1; }
    pg=${pg#page: }; out=$("$T/win-app.sh" --hidden --title "${pg#*|}" firefox "${pg%%|*}" 2>&1 | tr -d '\r'); rc=${PIPESTATUS[0]}
  fi
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$out" | grep -q '^hidden: '; then
    line=$(printf '%s\n' "$out" | grep '^not hidden: ' | tail -1); echo "open $i $app: FAIL open: ${line:-exit $rc: $(printf '%s\n' "$out" | grep -v '^hide-log' | tail -1)}"; return 1; fi
  # show + every check in ONE process, so the window is on screen for about a second (less time for a click meant for another window to land on it)
  sv=""; [ -n "${OST_KEEP:-}" ] && { mkdir -p "$OST_KEEP"; sv="$(wslpath -w "$OST_KEEP")\\$app-$i.png"; }
  out=$("$T/win.sh" showcheck "ost-$tok" $X $Y $W $H 20 "$sv" 2>&1 | tr -d '\r'); rc=${PIPESTATUS[0]}
  [ -n "${OST_KEEP:-}" ] && printf '%s\n' "$out" | grep '^show-note: \|^show-tries: ' | sed "s/^/open $i $app: /" >> "$OST_KEEP/notes.txt"
  line=$(printf '%s\n' "$out" | grep '^shown: ' | tail -1); tries=$(printf '%s\n' "$out" | grep '^show-tries: ' | tail -1)
  if [ "$rc" -ne 0 ] || [ -z "$line" ]; then echo "open $i $app: FAIL show: $(printf '%s\n' "$out" | grep '^not shown: ' | tail -1 | grep . || echo "exit $rc: $(printf '%s\n' "$out" | tail -1)")"; return 1; fi   # a failed show hid its window again; close-cloaked (below) closes it
  hwnd=$(echo "$line" | awk '{print $2}'); read -r l t w h <<<"$(echo "$line" | awk '{print $(NF-3), $(NF-2), $(NF-1), $NF}')"
  near() { local d=$(( $1 - $2 )); [ "${d#-}" -le 16 ]; }
  # from here the window is on screen: every failure closes it (fail() below), nothing of this script stays visible
  fail() { "$T/win.sh" untop "$hwnd" >/dev/null 2>&1; "$T/win.sh" close "$hwnd" >/dev/null 2>&1; echo "open $i $app: FAIL $1${tries:+ ($tries)}"; return 1; }
  if ! { near "$l" $X && near "$t" $Y && near "$w" $W && near "$h" $H; }; then fail "rect: at $l $t $w $h, asked $X $Y $W $H"; return 1; fi
  p=$(printf '%s\n' "$out" | sed -n 's/^check: //p' | tail -1)
  case "$p" in window\ *) fail "show: $p"; return 1;; ''|*[!0-9.]*) fail "blank: capture failed: ${p:-$(printf '%s\n' "$out" | tail -1)}"; return 1;; esac
  z=$(printf '%s\n' "$out" | sed -n 's/^z: //p' | tail -1)
  case "$z" in "$hwnd|"?"|0|"*"ost-$tok"*) ;; *) fail "list: window state is '${z:-no line for $hwnd}' (want cloaked=0 and ost-$tok in the title)"; return 1;; esac
  if ! awk -v p="$p" 'BEGIN{exit !(p > 2.0)}'; then fail "blank: content area is $(awk -v p="$p" 'BEGIN{printf "%.1f", 100-p}')% one colour (window $hwnd)"; return 1; fi
  "$T/win.sh" untop "$hwnd" >/dev/null 2>&1; out=$("$T/win.sh" close "$hwnd" 2>&1 | tr -d '\r'); rc=$?
  for k in $(seq 1 25); do "$T/win.sh" list-all 2>/dev/null | tr -d '\r' | grep -q "^$hwnd " || break; sleep 0.2; done
  if [ "$rc" -ne 0 ] || [ "$k" -ge 25 ]; then echo "open $i $app: FAIL close: ${out:-window $hwnd still open}"; return 1; fi
  echo "open $i $app: shown $hwnd $l $t $w $h title-ok cloaked=0 nonblank $p%"; return 0
}
sum=""; bad=0
# every line of every run is also kept in ~/.cache/claude-config/open-streak.log (a caller that prints only the last lines loses the FAIL reasons)
LOG="${OST_LOG:-$HOME/.cache/claude-config/open-streak.log}"; mkdir -p "$(dirname "$LOG")"
exec > >(while IFS= read -r l; do printf '%s\n' "$l"; printf '%s ET  %s\n' "$(TZ=America/New_York date '+%F %T')" "$l" >> "$LOG"; done)
for app in "${apps[@]}"; do
  case "$app" in firefox|page) ;; *) echo "open-streak.sh: unknown app $app (firefox, page)" >&2; exit 2;; esac
  ok=0
  for i in $(seq 1 "$n"); do
    one "$app" "$i" && ok=$((ok + 1))
    "$T/win.sh" close-cloaked >/dev/null 2>&1; sleep 1
  done
  [ "$ok" -eq "$n" ] || bad=1
  sum="${sum:+$sum, }$app $ok/$n shown"
done
echo "streak: $sum"
exec >&-; wait   # the log writer has the last line before this exits
exit $bad
