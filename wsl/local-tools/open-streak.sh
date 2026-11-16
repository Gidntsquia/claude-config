#!/bin/bash
# usage: open-streak.sh [n=10] [firefox|code ...]
# Proof that hidden opens end in a real, loaded, visible window. Per app (firefox, then code), n times:
#   a token file (ost-<tok>.html / .md) -> win-app.sh --hidden --title ost-<tok> -> win.sh show "ost-<tok>" 1030 0 1530 1400
#   -> checks -> win.sh close HWND + close-cloaked.
# Checks: the shown: rect is the asked one (within 16 px), list-z has the HWND with cloaked=0 and the token in its title, and a
# capture of the window's content area (the rect less 170 px on top, 50 below, 20 at the sides: the app's own bars would make an
# empty window look painted) is under 98 % one colour.
# Prints one line per open:
#   open N <app>: shown HWND L T W H title-ok cloaked=0 nonblank <p>%     (p = share of the content area that is NOT its main colour)
#   open N <app>: FAIL <stage>: <reason>          stage = open | show | rect | list | blank | close; reason = the helper's own line
# and last `streak: firefox <k>/<n> shown, code <k>/<n> shown`. Exit 0 only when every open of every app was shown.
# While a full-screen game runs: `not run: a full-screen game is running`, exit 3 (GAME_GUARD_CMD=<script> replaces game-guard.sh).
# OST_KEEP=<dir> keeps each content-area capture as <dir>/<app>-<N>.png. A window that is covered, minimized or closed by someone
# else between `show` and the capture fails stage `show` with that reason (run it while nobody uses the right half of the screen).
# Uses its own state dir, so it never touches an evaluator session's windows. The windows appear at the right of the screen
# for about a second each, topmost, without taking focus.
set -u
n=10; case "${1:-}" in ''|*[!0-9]*) ;; *) n=$1; shift;; esac
apps=("$@"); [ ${#apps[@]} -gt 0 ] || apps=(firefox code)
T="$HOME/.claude/local-tools"
grep -qi microsoft /proc/version 2>/dev/null || { echo "open-streak.sh: WSL only (this is $(uname))" >&2; exit 1; }
"${GAME_GUARD_CMD:-$T/game-guard.sh}" >/dev/null 2>&1 && { echo "not run: a full-screen game is running"; exit 3; }
S="$(mktemp -d)"; export EVSHOW_STATE="$S/state"; mkdir -p "$EVSHOW_STATE"; trap 'rm -rf "$S"' EXIT
X=1030; Y=0; W=1530; H=1400
cat > "$S/blank.ps1" <<'PS'
param([long]$hw, [string]$save = '')
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Text; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public class Blank { [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] struct R { public int L, T, Rt, B; } [StructLayout(LayoutKind.Sequential)] struct PT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out R r); [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h); [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(PT p); [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  // state and pixels in one go: the window must exist, not be minimized and be the top window at five points of its rect at the moment of the capture
  static string State(IntPtr h, out R r) { r = new R(); if (!IsWindow(h)) return "window " + h.ToInt64() + " is gone (closed by someone else after it was shown)";
    if (IsIconic(h)) return "window " + h.ToInt64() + " was minimized after it was shown (not by this script)"; GetWindowRect(h, out r); int w = r.Rt - r.L, t = r.B - r.T;
    double[] fx = { 0.5, 0.25, 0.75, 0.25, 0.75 }, fy = { 0.5, 0.3, 0.3, 0.75, 0.75 };
    for (int i = 0; i < 5; i++) { PT p; p.X = r.L + (int)(w * fx[i]); p.Y = r.T + (int)(t * fy[i]); IntPtr a = GetAncestor(WindowFromPoint(p), 2);
      if (a != h) { var s = new StringBuilder(200); GetWindowText(a, s, 200); return "window " + h.ToInt64() + " is covered by " + a.ToInt64() + " '" + s + "'"; } } return ""; }
  public static string Run(long hw, string save) { SetProcessDPIAware(); IntPtr h = (IntPtr)hw; R r; string st = State(h, out r); if (st.Length > 0) return st;
    int x = r.L + 20, y = r.T + 170, w = r.Rt - r.L - 40, ht = r.B - r.T - 220;
    using (var bmp = new Bitmap(w, ht, PixelFormat.Format32bppArgb)) { using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(x, y, 0, 0, bmp.Size);
      st = State(h, out r); if (st.Length > 0) return st;
      var d = bmp.LockBits(new Rectangle(0, 0, w, ht), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb); var px = new int[w * ht]; Marshal.Copy(d.Scan0, px, 0, px.Length); bmp.UnlockBits(d); if (save.Length > 0) bmp.Save(save, ImageFormat.Png);
      var c = new Dictionary<int, int>(); int top = 0, tot = 0; for (int i = 0; i < px.Length; i += 3) { int k; c.TryGetValue(px[i], out k); c[px[i]] = ++k; if (k > top) top = k; tot++; }
      return (100.0 - 100.0 * top / tot).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture); } } }
"@
[Blank]::Run($hw, $save)
PS
BL="$(wslpath -w "$S/blank.ps1")"
one() {  # one open of app $1, number $2; prints the line, returns 0 when shown
  local app=$1 i=$2 tok f out line hwnd l t w h z p rc k sv
  tok="$(tr -dc a-z0-9 </dev/urandom | head -c6)"
  if [ "$app" = firefox ]; then f="$S/ost-$tok.html"
    { echo "<!doctype html><title>ost-$tok</title><body style='margin:0;font:28px sans-serif'><h1>ost-$tok</h1>"
      for k in $(seq 1 30); do echo "<div style='height:24px;margin:14px 0;background:#2a6f97'></div>"; done; } > "$f"
    out=$("$T/win-app.sh" --hidden --title "ost-$tok" firefox -new-window "$f" 2>&1 | tr -d '\r'); rc=${PIPESTATUS[0]}   # a Linux path on purpose: the helper makes it a file:/// URL
  else f="$S/ost-$tok.md"
    { echo "# ost-$tok"; for k in $(seq 1 70); do echo "- line $k of ost-$tok: the quick brown fox jumps over the lazy dog, $k times, and comes back again"; done; } > "$f"
    out=$("$T/win-app.sh" --hidden --title "ost-$tok" code -n "$f" 2>&1 | tr -d '\r'); rc=${PIPESTATUS[0]}
  fi
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$out" | grep -q '^hidden: '; then
    line=$(printf '%s\n' "$out" | grep '^not hidden: ' | tail -1); echo "open $i $app: FAIL open: ${line:-exit $rc: $(printf '%s\n' "$out" | grep -v '^hide-log' | tail -1)}"; return 1; fi
  out=$("$T/win.sh" show "ost-$tok" $X $Y $W $H 20 2>&1 | tr -d '\r'); rc=$?
  line=$(printf '%s\n' "$out" | grep '^shown: ' | tail -1)
  if [ "$rc" -ne 0 ] || [ -z "$line" ]; then hwnd=$(printf '%s\n' "$out" | sed -n 's/^not shown: window \([0-9]*\) .*/\1/p' | tail -1); [ -n "$hwnd" ] && { "$T/win.sh" untop "$hwnd"; "$T/win.sh" close "$hwnd"; } >/dev/null 2>&1; echo "open $i $app: FAIL show: $(printf '%s\n' "$out" | grep '^not shown: ' | tail -1 | grep . || echo "exit $rc: $(printf '%s\n' "$out" | tail -1)")"; return 1; fi
  hwnd=$(echo "$line" | awk '{print $2}'); read -r l t w h <<<"$(echo "$line" | awk '{print $(NF-3), $(NF-2), $(NF-1), $NF}')"
  near() { local d=$(( $1 - $2 )); [ "${d#-}" -le 16 ]; }
  # from here the window is on screen: every failure closes it (fail() below), nothing of this script stays visible
  fail() { "$T/win.sh" untop "$hwnd" >/dev/null 2>&1; "$T/win.sh" close "$hwnd" >/dev/null 2>&1; echo "open $i $app: FAIL $1"; return 1; }
  if ! { near "$l" $X && near "$t" $Y && near "$w" $W && near "$h" $H; }; then fail "rect: at $l $t $w $h, asked $X $Y $W $H"; return 1; fi
  sleep 0.8   # the first frame after the un-cloak
  sv=""; [ -n "${OST_KEEP:-}" ] && { mkdir -p "$OST_KEEP"; sv="$(wslpath -w "$OST_KEEP")\\$app-$i.png"; }
  p=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$BL" "$hwnd" "$sv" 2>&1 | tr -d '\r' | tail -1)   # state + capture in one process: the pixels are this window's only while it is the top one
  case "$p" in window\ *) fail "show: $p"; return 1;; ''|*[!0-9.]*) fail "blank: capture failed: $p"; return 1;; esac
  z=$("$T/win.sh" list-z 2>&1 | tr -d '\r' | grep "^$hwnd|")
  case "$z" in "$hwnd|"?"|0|"*"ost-$tok"*) ;; *) fail "list: list-z has '${z:-no line for $hwnd}' (want cloaked=0 and ost-$tok in the title)"; return 1;; esac
  if ! awk -v p="$p" 'BEGIN{exit !(p > 2.0)}'; then fail "blank: content area is $(awk -v p="$p" 'BEGIN{printf "%.1f", 100-p}')% one colour (window $hwnd)"; return 1; fi
  "$T/win.sh" untop "$hwnd" >/dev/null 2>&1; out=$("$T/win.sh" close "$hwnd" 2>&1 | tr -d '\r'); rc=$?
  for k in $(seq 1 25); do "$T/win.sh" list-all 2>/dev/null | tr -d '\r' | grep -q "^$hwnd " || break; sleep 0.2; done
  if [ "$rc" -ne 0 ] || [ "$k" -ge 25 ]; then echo "open $i $app: FAIL close: ${out:-window $hwnd still open}"; return 1; fi
  echo "open $i $app: shown $hwnd $l $t $w $h title-ok cloaked=0 nonblank $p%"; return 0
}
sum=""; bad=0
for app in "${apps[@]}"; do
  case "$app" in firefox|code) ;; *) echo "open-streak.sh: unknown app $app (firefox, code)" >&2; exit 2;; esac
  ok=0
  for i in $(seq 1 "$n"); do
    one "$app" "$i" && ok=$((ok + 1))
    "$T/win.sh" close-cloaked >/dev/null 2>&1; sleep 1
  done
  [ "$ok" -eq "$n" ] || bad=1
  sum="${sum:+$sum, }$app $ok/$n shown"
done
echo "streak: $sum"
exit $bad
