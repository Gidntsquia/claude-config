#!/bin/bash
# usage: flash-test.sh firefox|code|wt [launches=20]
# Does a `win-app.sh --hidden` launch ever paint a frame? For each launch one PowerShell captures the whole display at >=30 fps for
# 2 s (Graphics.CopyFromScreen, 1/4 scale) starting just before the launch; a frame counts when more than 1 % of its pixels differ
# from the first frame (a 1200x1100 window is ~36 % of a 2560x1440 screen; cursor and clock stay far below 1 %). The cloaked
# window is closed (`win.sh close-cloaked`) after each launch. Prints per launch `launch N: hidden <k> ms, frames <n>, taskbar <t>` and at
# the end `frames: <n> over <L> launches, max hide <k> ms, taskbar frames <t>` (hidden = the hidden: line's exposure, hidden-ms - visible-ms;
# taskbar = frames where > 2 % of the taskbar strip changed, a new button). R4 of the plan: any app with frames >= 1 opens its items as tabs.
# Noise: this terminal's own repaints and other windows' animations (a tmux pet, spinners) are masked by the 1 s baseline when they
# move within it; what they change after that stays under 3 %, so a frame counts at > 5 % (the smallest of these windows is > 15 %
# of a 2560x1440 screen). Do not print to the terminal and do not open anything while it runs.
# Refuses while a full-screen game runs (game-guard.sh). Needs the session state dir (evsession.sh / EVSHOW_STATE).
set -u
app="${1:?usage: flash-test.sh firefox|code|wt [launches]}"; n="${2:-20}"
T="$HOME/.claude/local-tools"
"$T/game-guard.sh" "flash-test.sh $app" >/dev/null && { echo "not run: a full-screen game is running"; exit 3; }
. "$T/evsession.sh"; ev_export || { echo "no session state dir (set EVSHOW_STATE)"; exit 1; }
D=$(ev_state_dir create); S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
case "$app" in
  firefox) args=(-new-window "FILE") ;;   # a file: page (Firefox never loads a top-level data: URL from the command line: the title stays "Mozilla Firefox")
  code)    args=(-n "$S/flash-test-TOKEN.md") ;;
  wt)      args=(-w new --title flash-test-TOKEN wsl.exe -d "${WSL_DISTRO_NAME:-Ubuntu}" -- sleep 60) ;;
  *) echo "unknown app $app"; exit 2 ;;
esac
cap="$S/cap.ps1"
cat > "$cap" <<'PS'
param([double]$secs, [string]$marker)
# capture + compare in compiled C# (a PowerShell per-pixel loop runs at ~1 fps); 1/4-scale, every 4th pixel compared against frame 0
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class Cap {   // GDI: StretchBlt the screen DC into a 1/4-scale memory bitmap (~8 ms at 2560x1440), compare every 4th pixel to frame 0
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int n);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
  [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr h);
  [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr h, ref BMI b, uint u, out IntPtr bits, IntPtr s, uint o);
  [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr h, IntPtr o);
  [DllImport("gdi32.dll")] static extern int SetStretchBltMode(IntPtr h, int m);
  [DllImport("gdi32.dll")] static extern bool StretchBlt(IntPtr d, int x, int y, int w, int h, IntPtr s, int sx, int sy, int sw, int sh, uint rop);
  [DllImport("gdi32.dll")] static extern bool GdiFlush();
  [DllImport("user32.dll")] static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out ABD r);
  [StructLayout(LayoutKind.Sequential)] struct ABD { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] struct BMI { public uint size; public int w, h; public ushort planes, bpp; public uint comp, img; public int xp, yp; public uint used, imp; public uint c0; }
  public static string Run(double secs, string marker) {
    SetProcessDPIAware(); int W = GetSystemMetrics(0), H = GetSystemMetrics(1); int w = W / 4, h = H / 4;
    IntPtr sdc = GetDC(IntPtr.Zero), mdc = CreateCompatibleDC(sdc); var bi = new BMI(); bi.size = 44; bi.w = w; bi.h = -h; bi.planes = 1; bi.bpp = 32;
    IntPtr bits; IntPtr bmp = CreateDIBSection(mdc, ref bi, 0, out bits, IntPtr.Zero, 0); SelectObject(mdc, bmp); SetStretchBltMode(mdc, 3);   // COLORONCOLOR
    int n = w * h * 4; var b = new byte[n]; var f = new byte[n];
    Func<byte[], bool> grab = (a) => { bool ok = StretchBlt(mdc, 0, 0, w, h, sdc, 0, 0, W, H, 0x00CC0020 | 0x40000000); GdiFlush(); Marshal.Copy(bits, a, 0, n); return ok; };   // SRCCOPY|CAPTUREBLT
    // baseline (1 s): any 80x80 px cell holding a pixel that changes on its own (animations, clock, this terminal's spinner) is masked out whole
    grab(b); var cell = new bool[(w / 20 + 1) * (h / 20 + 1)]; var mask = new bool[n]; int cw = w / 20 + 1; var bw = System.Diagnostics.Stopwatch.StartNew();
    while (bw.ElapsedMilliseconds < 1000) { grab(f); for (int i = 0; i < n; i += 16) if (Math.Abs(f[i] - b[i]) > 24 || Math.Abs(f[i+1] - b[i+1]) > 24 || Math.Abs(f[i+2] - b[i+2]) > 24) { int px = (i / 4) % w, py = (i / 4) / w; cell[(py / 20) * cw + px / 20] = true; } }
    int noisy = 0; for (int i = 0; i < n; i += 16) { int px = (i / 4) % w, py = (i / 4) / w; if (cell[(py / 20) * cw + px / 20]) { mask[i] = true; noisy++; } }
    grab(b); System.IO.File.WriteAllText(marker, "go");
    // taskbar strip (Shell_TrayWnd rect), its clock/tray end (rightmost 320 px) left out: a new button is ~0.05 % of the screen, so it gets
    // its own count: a frame counts when > 2 % of the strip's unmasked pixels changed
    ABD abd; GetWindowRect(FindWindow("Shell_TrayWnd", null), out abd); int tL = abd.L / 4, tT = abd.T / 4, tR = Math.Max(abd.L, abd.R - 320) / 4, tB = abd.B / 4; int tbTot = 0;
    for (int i = 0; i < n; i += 16) { int px = (i / 4) % w, py = (i / 4) / w; if (!mask[i] && px >= tL && px < tR && py >= tT && py < tB) tbTot++; }
    var sw = System.Diagnostics.Stopwatch.StartNew(); int frames = 0, changed = 0, tbChanged = 0; double worst = 0, tbWorst = 0; long worstAt = 0, tbAt = 0; string box = "";
    while (sw.Elapsed.TotalSeconds < secs) { grab(f); frames++; int diff = 0, tot = 0, tb = 0, x0 = w, y0 = h, x1 = -1, y1 = -1;
      for (int i = 0; i < n; i += 16) { tot++; if (!mask[i] && (Math.Abs(f[i] - b[i]) > 24 || Math.Abs(f[i+1] - b[i+1]) > 24 || Math.Abs(f[i+2] - b[i+2]) > 24)) { diff++; int px = (i / 4) % w, py = (i / 4) / w; if (px < x0) x0 = px; if (px > x1) x1 = px; if (py < y0) y0 = py; if (py > y1) y1 = py; if (px >= tL && px < tR && py >= tT && py < tB) tb++; } }
      double pct = 100.0 * diff / (tot - noisy); if (pct > worst) { worst = pct; worstAt = sw.ElapsedMilliseconds; box = (x0 * 4) + "," + (y0 * 4) + "-" + (x1 * 4 + 3) + "," + (y1 * 4 + 3); } if (pct > 5.0) changed++;
      double tp = tbTot > 0 ? 100.0 * tb / tbTot : 0; if (tp > tbWorst) { tbWorst = tp; tbAt = sw.ElapsedMilliseconds; } if (tp > 2.0) tbChanged++; }
    return "capture: " + frames + " frames in " + sw.ElapsedMilliseconds + " ms, " + changed + " changed (>5%), worst " + Math.Round(worst, 2) + "% at " + worstAt + " ms in " + box + ", masked " + Math.Round(100.0 * noisy / (n / 16), 2) + "%, taskbar " + tbChanged + " changed (>2%), worst " + Math.Round(tbWorst, 2) + "% at " + tbAt + " ms of " + (abd.R - abd.L - 320) + "x" + (abd.B - abd.T); } }
"@
[Cap]::Run($secs, $marker)
PS
total=0; maxhide=0; tbtotal=0; fps_low=""
for i in $(seq 1 "$n"); do
  tok="$(tr -dc a-z0-9 </dev/urandom | head -c6)"; a=("${args[@]/TOKEN/$tok}")
  [ "$app" = code ] && echo "# flash-test $tok" > "$S/flash-test-$tok.md"
  [ "$app" = firefox ] && { echo "<title>flash-test-$tok</title><h1>flash-test-$tok</h1>" > "$S/flash-test-$tok.html"; a=(-new-window "$(wslpath -w "$S/flash-test-$tok.html")"); }
  marker="$S/go-$i"; rm -f "$marker"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$cap")" 2.5 "$(wslpath -w "$marker")" > "$S/cap-$i.out" 2>&1 </dev/null &
  cpid=$!
  for _ in $(seq 1 100); do [ -e "$marker" ] && break; sleep 0.1; done
  out=$("$T/win-app.sh" --hidden --title "flash-test-$tok" "$app" "${a[@]}" 2>&1 | tr -d '\r')
  wait "$cpid"; capl=$(tr -d '\r' < "$S/cap-$i.out" | grep '^capture:' | tail -1)
  hide=$(printf '%s\n' "$out" | awk '/^hidden: /{d=$4-$3; if(d>m)m=d} END{print m+0}')
  fr=$(printf '%s\n' "$capl" | sed -n 's/.* ms, \([0-9]*\) changed.*/\1/p'); fr=${fr:-?}
  tb=$(printf '%s\n' "$capl" | sed -n 's/.*taskbar \([0-9]*\) changed.*/\1/p'); tbtotal=$((tbtotal + ${tb:-0}))
  fps=$(printf '%s\n' "$capl" | awk '/^capture:/{printf "%d", $2*1000/$5}'); [ -n "$fps" ] && [ "$fps" -lt 30 ] && fps_low="$fps_low $fps"
  printf 'launch %d: hidden %s ms, frames %s, taskbar %s  (%s)\n' "$i" "$hide" "$fr" "${tb:-?}" "${capl:-no capture: $(tail -1 "$S/cap-$i.out")}"
  printf '%s\n' "$out" | grep -v '^hidden: \|^hide-log' | sed 's/^/   /'
  [ "$fr" != "?" ] && total=$((total + fr)); [ "$hide" -gt "$maxhide" ] 2>/dev/null && maxhide=$hide
  "$T/win.sh" close-cloaked >/dev/null 2>&1; sleep 1
done
[ -n "$fps_low" ] && echo "warning: capture ran under 30 fps on some launches:$fps_low"
echo "frames: $total over $n launches, max hide $maxhide ms, taskbar frames $tbtotal"
