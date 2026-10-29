#!/bin/bash
# usage: flash-test.sh firefox|code|wt [launches=20]
# Does a `win-app.sh --hidden` launch ever paint a frame? For each launch one PowerShell captures the whole display at >=30 fps for
# 2 s (Graphics.CopyFromScreen, 1/4 scale) starting just before the launch; a frame counts when more than 1 % of its pixels differ
# from the first frame (a 1200x1100 window is ~36 % of a 2560x1440 screen; cursor and clock stay far below 1 %). The cloaked
# window is closed (`win.sh close-cloaked`) after each launch. Prints per launch `launch N: hidden <k> ms, frames <n>` and at the end
# `frames: <n> over <L> launches, max hide <k> ms`. R4 of the plan: any app with frames >= 1 opens its items as tabs instead.
# Refuses while a full-screen game runs (game-guard.sh). Needs the session state dir (evsession.sh / EVSHOW_STATE).
set -u
app="${1:?usage: flash-test.sh firefox|code|wt [launches]}"; n="${2:-20}"
T="$HOME/.claude/local-tools"
"$T/game-guard.sh" "flash-test.sh $app" >/dev/null && { echo "not run: a full-screen game is running"; exit 3; }
. "$T/evsession.sh"; ev_export || { echo "no session state dir (set EVSHOW_STATE)"; exit 1; }
D=$(ev_state_dir create); S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
case "$app" in
  firefox) args=(-new-window "data:text/html,<title>flash-test-TOKEN</title>flash") ;;
  code)    args=(-n "$S/flash-test-TOKEN.md") ;;
  wt)      args=(-w new --title flash-test-TOKEN wsl.exe -d "${WSL_DISTRO_NAME:-Ubuntu}" -- sleep 60) ;;
  *) echo "unknown app $app"; exit 2 ;;
esac
cap="$S/cap.ps1"
cat > "$cap" <<'PS'
param([double]$secs, [string]$marker)
Add-Type -AssemblyName System.Drawing
[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $w = [int]($b.Width / 4); $h = [int]($b.Height / 4)
$full = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($full)
$small = New-Object System.Drawing.Bitmap $w, $h; $gs = [System.Drawing.Graphics]::FromImage($small)
$gs.InterpolationMode = 'NearestNeighbor'
function Grab { $g.CopyFromScreen(0, 0, 0, 0, $full.Size); $gs.DrawImage($full, 0, 0, $w, $h)
  $d = $small.LockBits((New-Object System.Drawing.Rectangle 0, 0, $w, $h), 'ReadOnly', 'Format32bppArgb')
  $n = $d.Stride * $h; $a = New-Object byte[] $n; [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $a, 0, $n); $small.UnlockBits($d); $a }
$base = Grab; [IO.File]::WriteAllText($marker, 'go')   # the launcher waits for this file, so frame 0 precedes the launch
$sw = [Diagnostics.Stopwatch]::StartNew(); $frames = 0; $changed = 0; $worst = 0.0
while ($sw.Elapsed.TotalSeconds -lt $secs) {
  $f = Grab; $frames++; $diff = 0; $tot = $f.Length / 4
  for ($i = 0; $i -lt $f.Length; $i += 16) { if ([Math]::Abs([int]$f[$i] - [int]$base[$i]) -gt 24 -or [Math]::Abs([int]$f[$i+1] - [int]$base[$i+1]) -gt 24 -or [Math]::Abs([int]$f[$i+2] - [int]$base[$i+2]) -gt 24) { $diff++ } }
  $pct = 100.0 * $diff / ($tot / 4); if ($pct -gt $worst) { $worst = $pct }; if ($pct -gt 1.0) { $changed++ } }
"capture: $frames frames in $([int]$sw.Elapsed.TotalMilliseconds) ms, $changed changed (>1%), worst $([math]::Round($worst, 2))%"
PS
total=0; maxhide=0; fps_low=""
for i in $(seq 1 "$n"); do
  tok="$(tr -dc a-z0-9 </dev/urandom | head -c6)"; a=("${args[@]/TOKEN/$tok}")
  [ "$app" = code ] && echo "# flash-test $tok" > "$S/flash-test-$tok.md"
  marker="$S/go-$i"; rm -f "$marker"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$cap")" 2.5 "$(wslpath -w "$marker")" > "$S/cap-$i.out" 2>&1 &
  cpid=$!
  for _ in $(seq 1 100); do [ -e "$marker" ] && break; sleep 0.1; done
  out=$("$T/win-app.sh" --hidden --title "flash-test-$tok" "$app" "${a[@]}" 2>&1 | tr -d '\r')
  wait "$cpid"; capl=$(tr -d '\r' < "$S/cap-$i.out" | grep '^capture:' | tail -1)
  hide=$(printf '%s\n' "$out" | awk '/^hidden: /{d=$4-$3; if(d>m)m=d} END{print m+0}')
  fr=$(printf '%s\n' "$capl" | sed -n 's/.* ms, \([0-9]*\) changed.*/\1/p'); fr=${fr:-?}
  fps=$(printf '%s\n' "$capl" | awk '/^capture:/{printf "%d", $2*1000/$5}'); [ -n "$fps" ] && [ "$fps" -lt 30 ] && fps_low="$fps_low $fps"
  printf 'launch %d: hidden %s ms, frames %s  (%s)\n' "$i" "$hide" "$fr" "${capl:-no capture: $(tail -1 "$S/cap-$i.out")}"
  printf '%s\n' "$out" | grep -v '^hidden: \|^hide-log' | sed 's/^/   /'
  [ "$fr" != "?" ] && total=$((total + fr)); [ "$hide" -gt "$maxhide" ] 2>/dev/null && maxhide=$hide
  "$T/win.sh" close-cloaked >/dev/null 2>&1; sleep 1
done
[ -n "$fps_low" ] && echo "warning: capture ran under 30 fps on some launches:$fps_low"
echo "frames: $total over $n launches, max hide $maxhide ms"
