# See win.sh. One argument: "action|arg|arg|..." (negative numbers must not be separate -File args).
param([string]$Line)
$a = $Line.Split('|'); $Action = $a[0]; $p = @($a | Select-Object -Skip 1)
$Src = @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class W {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", EntryPoint="GetWindowLongW")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int n);
  public static int Cloaked(IntPtr h) { int v = 0; DwmGetWindowAttribute(h, 14, out v, 4); return v; }
  public static string Title(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
  public static List<IntPtr> All() {
    var r = new List<IntPtr>();
    EnumWindows((h, l) => { if (IsWindowVisible(h) && Title(h).Length > 0) r.Add(h); return true; }, IntPtr.Zero);
    return r; }
}
"@
Add-Type -TypeDefinition $Src
[W]::SetProcessDPIAware() | Out-Null
function Rect($h) { $r = New-Object W+R; [W]::GetWindowRect($h, [ref]$r) | Out-Null; "$($r.L) $($r.T) $($r.Rt-$r.L) $($r.B-$r.T)" }
function Hw($s) { $n = 0L; if (-not [int64]::TryParse($s, [ref]$n) -or $n -le 1) { "error: '$s' is not an HWND (title lookup is only in find/show)"; exit 1 }
  $h = [IntPtr]$n; if (-not [W]::IsWindow($h)) { "error: window $s no longer exists"; exit 1 }; $h }
function Matches($t) { @([W]::All() | Where-Object { [W]::Title($_).IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
function Cands($m) { ($m | ForEach-Object { "  $([int64]$_) $([W]::Title($_))" }) -join "`n" }
$Behind = ($env:EVSHOW_BEHIND -eq '1')   # behind mode (tests): windows are placed and un-minimized but sent to the very bottom of the z-order (HWND_BOTTOM), never topmost/front
function Bottom($h) { Top $h $false; 1..3 | ForEach-Object { [W]::SetWindowPos($h, [IntPtr]1, 0, 0, 0, 0, 0x0013) | Out-Null; Start-Sleep -Milliseconds 120 } }   # HWND_BOTTOM (below every other window, not topmost, no activation), NOMOVE|NOSIZE|NOACTIVATE
function Unmin($h) { foreach ($c in 4, 9, 1) { if (-not [W]::IsIconic($h) -and -not [W]::IsZoomed($h)) { break }
    [W]::ShowWindow($h, $c) | Out-Null; if ($Behind) { Bottom $h }
    for ($i = 0; $i -lt 8 -and [W]::IsIconic($h); $i++) { Start-Sleep -Milliseconds 125 } } }
function Top($h, $on) { $z = if ($on) { -1 } else { -2 }; [W]::SetWindowPos($h, [IntPtr]$z, 0, 0, 0, 0, 0x0053) | Out-Null }
function PutWin($h, $x, $y, $w, $ht) { [W]::SetWindowPos($h, [IntPtr]::Zero, [int]$x, [int]$y, [int]$w, [int]$ht, 0x0054) | Out-Null }  # NOZORDER|NOACTIVATE|SHOWWINDOW
function OnScreen($h) { $r = New-Object W+R; [W]::GetWindowRect($h, [ref]$r) | Out-Null
  (-not [W]::IsIconic($h)) -and $r.L -ge -16 -and $r.T -ge -16 -and ($r.Rt-$r.L) -gt 100 -and ($r.B-$r.T) -gt 100 }

function ShowIt($t, $px, $py, $pw, $ph, $to, $term) {
    $end = (Get-Date).AddSeconds($to); $m = @()
    while ($true) { $m = Matches $t; if ($m.Count -ge 1 -or (Get-Date) -gt $end) { break }; Start-Sleep -Milliseconds 200 }
    if ($m.Count -eq 0) { "not shown: no window matches '$t' after ${to}s"; return 1 }
    if ($m.Count -gt 1) { "not shown: $($m.Count) windows match '$t':`n$(Cands $m)"; return 1 }
    $h = $m[0]; Register $h $t; $x = [int]$px
    $why = ''; $trace = @()
    foreach ($pause in 250, 750, 1500) {
      # A fresh window (e.g. a new browser window) ignores TOPMOST until it has been minimized and restored; a prepped one is already minimized.
      if (-not [W]::IsIconic($h)) { [W]::ShowWindow($h, 6) | Out-Null; Start-Sleep -Milliseconds 300 }
      Unmin $h; Start-Sleep -Milliseconds 300; PutWin $h $px $py $pw $ph; if ($Behind) { Bottom $h } else { Top $h $true }; Start-Sleep -Milliseconds $pause
      $r = New-Object W+R; [W]::GetWindowRect($h, [ref]$r) | Out-Null; $why = @()
      if ([W]::IsIconic($h)) { $why += 'minimized' }
      if (-not (OnScreen $h)) { $why += 'off screen' }
      if ($r.L -lt $x - 16) { $why += "L=$($r.L) < $x" }
      if (-not $Behind -and ([W]::GetWindowLong($h, -20) -band 8) -eq 0) { $why += 'not topmost' }
      if ($term) { $tr = New-Object W+R; [W]::GetWindowRect($term, [ref]$tr) | Out-Null
        if ($r.L -lt $tr.Rt -and $r.Rt -gt $tr.L -and $r.T -lt $tr.B -and $r.B -gt $tr.T) { $why += 'overlaps terminal' } }
      if ($why.Count -eq 0) { if ($trace.Count) { "show-tries: $($trace -join '; ')" }; "shown: $([int64]$h) $([W]::Title($h)) $(Rect $h)"; return 0 }
      $trace += ($why -join ',') }
    "not shown: window $([int64]$h) $($why -join ', ') ($(Rect $h)); tries: $($trace -join '; ')"; return 1 }
function Capture($out) { # whole-display PNG (DPI aware already); prints "capture <path>"
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  "capture $out $($b.Width)x$($b.Height)" }
function Done($r) { $r = @($r); if ($r.Count -gt 1) { $r[0..($r.Count-2)] | Write-Output }; exit [int]$r[-1] }

$Reg = if ($env:EVSHOW_LAUNCHED) { $env:EVSHOW_LAUNCHED } else { Join-Path $PSScriptRoot 'launched.txt' }   # per-session registry (win.sh sets it)
function Register($h, $tok) { Add-Content -Path $Reg -Value "$([int64]$h)|$tok" }
function Owned($s) { $h = Hw $s; $ok = $false
  if (Test-Path $Reg) { foreach ($l in Get-Content $Reg) { $a = $l.Split('|', 2)
    if ($a[0] -eq "$([int64]$h)" -and [W]::Title($h).IndexOf($a[1], [StringComparison]::OrdinalIgnoreCase) -ge 0) { $ok = $true } } }
  if (-not $ok) { "error: window $s was not launched by this evaluator (not registered by show/term-open, or its title changed); refusing"; exit 1 }
  $h }

switch ($Action) {
  'fgrect' { Rect ([W]::GetForegroundWindow()) }
  'fginfo' { $h = [W]::GetForegroundWindow(); "$([int64]$h) $(Rect $h) $([int][W]::IsZoomed($h))" }
  'placefg' { $h = [W]::GetForegroundWindow(); Unmin $h; PutWin $h $p[0] $p[1] $p[2] $p[3]; "placed foreground" }
  'setwin' { $h = Hw $p[0]; $mx = [int]$p[5]
    if ([W]::IsIconic($h) -or [W]::IsZoomed($h)) { [W]::ShowWindow($h, 4) | Out-Null }
    if ([W]::IsZoomed($h) -or [W]::IsIconic($h)) { [W]::ShowWindow($h, 9) | Out-Null }
    PutWin $h $p[1] $p[2] $p[3] $p[4]
    if ($mx -eq 1) { [W]::ShowWindow($h, 3) | Out-Null }
    "now $(Rect $h) $([int][W]::IsZoomed($h))" }
  'reg' { $h = Hw $p[0]; Register $h $p[1]; "registered $($p[0])" }
  'rect' { Rect (Hw $p[0]) }
  'bottom' { $h = Owned $p[0]; Bottom $h; "bottom: $([W]::Title($h))" }
  'front' { $h = Owned $p[0]; Unmin $h; if ($Behind) { Bottom $h } else { Top $h $true }
    if ([W]::IsIconic($h)) { "error: window $($p[0]) still minimized"; exit 1 }; "front: $([W]::Title($h)) $(Rect $h)" }
  'untop' { $h = Hw $p[0]; Top $h $false; "untop: $([W]::Title($h))" }
  'close' { $h = Owned $p[0]; $t = [W]::Title($h); [W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; "closed: $t" }
  'place' { $h = Owned $p[0]; Unmin $h; PutWin $h $p[1] $p[2] $p[3] $p[4]; "placed: $([W]::Title($h)) $(Rect $h)" }
  'list-all' { [W]::All() | ForEach-Object { "$([int64]$_) $([W]::Title($_))" } }
  'list-z' { [W]::All() | ForEach-Object { "$([int64]$_)|$([int](([W]::GetWindowLong($_, -20) -band 8) -ne 0))|$([int]([W]::Cloaked($_) -ne 0))|$([W]::Title($_))" } }   # z-order top to bottom
  'list-topmost' { [W]::All() | Where-Object { ([W]::GetWindowLong($_, -20) -band 8) -ne 0 } | ForEach-Object { "$([int64]$_) $([W]::Title($_))" } }
  'find' { $m = Matches $p[0]
    if ($m.Count -eq 1) { "$([int64]$m[0]) $([W]::Title($m[0]))"; exit 0 }
    if ($m.Count -eq 0) { "no window matches '$($p[0])'"; exit 1 }
    "$($m.Count) windows match '$($p[0])':`n$(Cands $m)"; exit 1 }
  'prep' { $t = $p[0]; $to = if ($p.Count -gt 1 -and $p[1]) { [double]$p[1] } else { 20 }
    $end = (Get-Date).AddSeconds($to); $m = @()
    while ($true) { $m = Matches $t; if ($m.Count -ge 1 -or (Get-Date) -gt $end) { break }; Start-Sleep -Milliseconds 250 }
    if ($m.Count -ne 1) { "not prepped: $($m.Count) windows match '$t'"; exit 1 }
    $h = $m[0]; Register $h $t
    for ($i = 0; $i -lt 8 -and -not [W]::IsIconic($h); $i++) { [W]::ShowWindow($h, 6) | Out-Null; Start-Sleep -Milliseconds 250 }
    if (-not [W]::IsIconic($h)) { "not prepped: window $([int64]$h) would not minimize"; exit 1 }
    "prepped: $([int64]$h) $([W]::Title($h))"; exit 0 }
  'min' { $h = Owned $p[0]; [W]::ShowWindow($h, 6) | Out-Null; "minimized: $([W]::Title($h))" }
  'show' { $to = if ($p.Count -gt 5 -and $p[5]) { [double]$p[5] } else { 15 }
    $term = $null; if ($p.Count -gt 6 -and $p[6]) { $term = Hw $p[6] }
    Done (ShowIt $p[0] $p[1] $p[2] $p[3] $p[4] $to $term) }
  'start' { # start "<title>" X Y W H timeout TX TY TW TH : fginfo + place the foreground (your terminal) + show, one process
    $h = if ($p.Count -gt 10 -and $p[10]) { Hw $p[10] } else { [W]::GetForegroundWindow() }   # 11th arg: terminal HWND override (tests)
    "fginfo $([int64]$h) $(Rect $h) $([int][W]::IsZoomed($h))"
    Unmin $h; PutWin $h $p[6] $p[7] $p[8] $p[9]; if ($Behind) { Bottom $h }; "placed foreground $(Rect $h)"
    $r = @(ShowIt $p[0] $p[1] $p[2] $p[3] $p[4] ([double]$p[5]) $h)
    if ($p.Count -gt 11 -and $p[11] -and [int]$r[-1] -eq 0) { Capture $p[11] }   # 12th arg: capture path, taken right after shown
    Done $r }
  'next' { # next OLDHWND "<title>" X Y W H timeout termHWND : untop + close the old item, show the new one, one process
    $term = $null; if ($p.Count -gt 7 -and $p[7]) { $term = Hw $p[7] }
    if ($p[0] -and $p[0] -ne '0') { $o = Owned $p[0]; Top $o $false; $ot = [W]::Title($o)
      [W]::PostMessage($o, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; "closed: $ot" }
    $r = @(ShowIt $p[1] $p[2] $p[3] $p[4] $p[5] ([double]$p[6]) $term)
    if ($p.Count -gt 8 -and $p[8] -and [int]$r[-1] -eq 0) { Capture $p[8] }   # 9th arg: capture path, taken right after shown
    Done $r }
  default { "error: unknown action '$Action'"; exit 1 }
}
