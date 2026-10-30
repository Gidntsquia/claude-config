# See win.sh. One argument: "action|arg|arg|..." (negative numbers must not be separate -File args). The callers pass it in
# $env:WINCTL_LINE (via WSLENV) because WSL interop rejects some argv strings with "Invalid argument" (e.g. "hidden|wt|C:\x\wt.exe|-w new|t|3").
param([string]$Line)
if ($env:WINCTL_LINE) { $Line = $env:WINCTL_LINE }
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
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("kernel32.dll")] public static extern uint GetTickCount();
  public static int SetCloak(IntPtr h, int on) { return DwmSetWindowAttribute(h, 13, ref on, 4); }   // DWMWA_CLOAK (E_ACCESSDENIED on another process's window here; kept as a logged attempt)
  public static uint Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }
  [DllImport("user32.dll")] public static extern IntPtr GetPropW(IntPtr h, string n);
  [DllImport("user32.dll")] public static extern bool SetPropW(IntPtr h, string n, IntPtr v);
  [DllImport("user32.dll")] public static extern IntPtr FindWindowW(string c, string t);
  [DllImport("user32.dll", EntryPoint="SetWindowLongW")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  // the shell's own hook runs before ours, so a window created visible is already in its app's taskbar button group; without DeleteTab
  // the shell drops it ~1 s later (title change) and rebuilds the button with a visible width animation (seen in a taskbar capture)
  [ComImport, Guid("56FDF342-FD6D-11d0-958A-006097C9A090"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] public interface ITaskbarList { void HrInit(); void AddTab(IntPtr h); void DeleteTab(IntPtr h); void ActivateTab(IntPtr h); void SetActiveAlt(IntPtr h); }
  [ComImport, Guid("56FDF344-FD6D-11d0-958A-006097C9A090")] public class TaskbarList { }
  static ITaskbarList tbl;
  public static void DeleteTab(IntPtr h) { try { if (tbl == null) { tbl = (ITaskbarList)new TaskbarList(); tbl.HrInit(); } tbl.DeleteTab(h); } catch (Exception) { } }
  [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
  [DllImport("user32.dll")] public static extern bool GetLayeredWindowAttributes(IntPtr h, out uint key, out byte alpha, out uint flags);
  public static HashSet<IntPtr> Reg = new HashSet<IntPtr>();   // this session's registered windows: listed even while hidden
  // "cloaked" = hidden by --hidden: not WS_VISIBLE (a registered window), or layered with alpha 0, or DWM-cloaked
  public static bool Hidden(IntPtr h) { if (Reg.Contains(h) && (GetWindowLong(h, -20) & 0x80) != 0 && (OffScreen(h) || EmptyRgn(h))) return true; int ex = GetWindowLong(h, -20); if ((ex & 0x80000) != 0) { uint k, f; byte a; if (GetLayeredWindowAttributes(h, out k, out a, out f) && (f & 2) != 0 && a == 0) return true; }
    return Cloaked(h) != 0; }
  // hide: layered alpha 0 (DWM composes nothing of it) + tool window (no taskbar button) + off-screen; it stays WS_VISIBLE so the
  // app keeps loading (VS Code's workbench waits for a frame; a SW_HIDE'd window never gets one, so its title never loads)
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int a, int b, int c, int d);
  [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
  [DllImport("user32.dll")] public static extern int GetWindowRgn(IntPtr h, IntPtr rgn);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
  // mode 1 (Firefox, WT): layered alpha 0 + tool window (no taskbar button) + off-screen (-6000,0).
  // mode 2 (EVSHOW_CODE_REGION=1, VS Code only; was the default): on screen with an EMPTY window region + tool window. Dropped as
  //   default: ~1 s in, VS Code moves the window back AND resets its region in one go (fully visible ~100 ms, 3 frames at 35 fps).
  //   With the off-screen move first, mode 1 loads the workbench fine and VS Code paints normally after Unhide (checked 2026-10-29).
  public static string hideT = "";
  public static void Hide(IntPtr h, bool layered) { int ex = GetWindowLong(h, -20); var w = System.Diagnostics.Stopwatch.StartNew(); long p, a, b;
    // off-screen FIRST: SetWindowPos with SWP_NOSENDCHANGING changes the position in the kernel before any message reaches the app's
    // (busy) thread, so a ShowWindow that races the style change shows the window at -6000,0; SetWindowLong/SetWindowRgn below wait for
    // that thread (WM_STYLECHANGING): 30-140 ms while Firefox/Code start up
    SetWindowPos(h, IntPtr.Zero, -6000, 0, 0, 0, 0x0415); p = w.ElapsedMilliseconds;   // NOSIZE|NOZORDER|NOACTIVATE|NOSENDCHANGING
    DeleteTab(h);
    if (layered) { SetWindowLong(h, -20, ex | 0x80080); a = w.ElapsedMilliseconds; SetLayeredWindowAttributes(h, 0, 0, 2); b = w.ElapsedMilliseconds; if (!OffScreen(h)) SetWindowPos(h, IntPtr.Zero, -6000, 0, 0, 0, 0x0015); }
    else { SetWindowLong(h, -20, ex | 0x80); a = w.ElapsedMilliseconds; SetWindowRgn(h, CreateRectRgn(0, 0, 0, 0), false); b = w.ElapsedMilliseconds; }
    hideT = "pos " + p + " style " + (a - p) + " attr " + (b - a) + " repos " + (w.ElapsedMilliseconds - b); }
  public static bool OffScreen(IntPtr h) { R r; GetWindowRect(h, out r); return r.Rt <= -3000; }
  public static bool Invisible(IntPtr h) { if (OffScreen(h) || EmptyRgn(h)) return true; if ((GetWindowLong(h, -20) & 0x80000) != 0) { uint k, f; byte a; if (GetLayeredWindowAttributes(h, out k, out a, out f) && (f & 2) != 0 && a == 0) return true; } return false; }   // nothing of it can be on a monitor
  public static bool EmptyRgn(IntPtr h) { IntPtr g = CreateRectRgn(0, 0, 1, 1); int k = GetWindowRgn(h, g); DeleteObject(g); return k == 1; }   // NULLREGION
  public static void Unhide(IntPtr h) { SetPropW(h, "evshow-shown", (IntPtr)1); int ex = GetWindowLong(h, -20); if ((ex & 0x80000) != 0) SetLayeredWindowAttributes(h, 0, 255, 2); SetWindowLong(h, -20, ex & ~(0x80000 | 0x80)); if (EmptyRgn(h)) SetWindowRgn(h, IntPtr.Zero, true); }
  public static int Cloaked(IntPtr h) { int v = 0; DwmGetWindowAttribute(h, 14, out v, 4); return v; }
  public static string Title(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
  public static List<IntPtr> All() {
    var r = new List<IntPtr>();
    EnumWindows((h, l) => { if ((IsWindowVisible(h) || Reg.Contains(h)) && Title(h).Length > 0) r.Add(h); return true; }, IntPtr.Zero);
    return r; }
}

public class Hider {
  // One WinEvent hook (out of context, no polling): every NEW top-level captioned window of the app's processes is cloaked
  // (DWMWA_CLOAK) and moved to -6000,0 inside the CREATE/SHOW handler; FOREGROUND steals are given back to the previous
  // foreground window; NAMECHANGE tells us when the title has loaded. The thread sleeps in GetMessage between events.
  public delegate void WinEventDelegate(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
  [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventDelegate cb, uint pid, uint tid, uint flags);
  [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int px, py; }
  [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint min, uint max);
  [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
  [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);
  [DllImport("user32.dll")] static extern UIntPtr SetTimer(IntPtr h, UIntPtr id, uint ms, IntPtr fn);
  [DllImport("user32.dll")] static extern bool KillTimer(IntPtr h, UIntPtr id);
  static WinEventDelegate keep;
  public HashSet<uint> pids = new HashSet<uint>();
  public string[] names; public string want; public string[] generic;
  public Dictionary<IntPtr, string> hidden = new Dictionary<IntPtr, string>();   // hwnd -> "create-ms hidden-ms" (hidden-ms: first ms off-screen/transparent, else hide-done)
  public Dictionary<IntPtr, long> shown = new Dictionary<IntPtr, long>(), vis0 = new Dictionary<IntPtr, long>();   // first SHOW event ms; CREATE ms when created already visible
  // exposure: "<visible-ms> <hidden-ms>": from the moment the window first had WS_VISIBLE (CREATE if created visible, else its first
  // SHOW) to the moment the hide (layered alpha 0 / empty region + off-screen) was in place; hidden before ever visible = "<show> <show>" (0 ms)
  public string Exposure(IntPtr h) { string[] cc = hidden[h].Split(' '); long cl; if (!long.TryParse(cc[1], out cl)) return hidden[h];
    long v; if (vis0.TryGetValue(h, out v)) return v + " " + Math.Max(v, cl); if (shown.TryGetValue(h, out v)) return v + " " + Math.Max(v, cl); return hidden[h]; }
  public List<string> log = new List<string>();
  public bool debug = false; public bool layered = true; public int moved; public int pending; public IntPtr fg0; public bool done; public uint t0; public long lastRefresh = -1000; public int fgRestored;
  public System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint acc, bool inh, uint pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h, uint fl, System.Text.StringBuilder sb, ref int n);
  public Dictionary<uint, bool> fam = new Dictionary<uint, bool>();   // pid -> is it the app family (by image name; Firefox/WT hand the window to an already running process)
  public void Refresh() { foreach (var n in names) foreach (var pr in System.Diagnostics.Process.GetProcessesByName(n)) { fam[(uint)pr.Id] = true; pr.Dispose(); } lastRefresh = sw.ElapsedMilliseconds; }
  bool Mine(IntPtr h) {   // one OpenProcess+QueryFullProcessImageName per NEW pid (~0.1 ms); nothing per event once known
    uint p = W.Pid(h); bool r; if (fam.TryGetValue(p, out r)) return r; lock (pids) if (pids.Contains(p)) return fam[p] = true;
    IntPtr hp = OpenProcess(0x1000, false, p); r = false;
    if (hp != IntPtr.Zero) { var sb = new System.Text.StringBuilder(1024); int n = 1024; if (QueryFullProcessImageName(hp, 0, sb, ref n)) {
        string f = System.IO.Path.GetFileNameWithoutExtension(sb.ToString()); foreach (var nm in names) if (string.Equals(f, nm, StringComparison.OrdinalIgnoreCase)) r = true; } CloseHandle(hp); }
    fam[p] = r; return r; }
  bool Captioned(IntPtr h) { int st = W.GetWindowLong(h, -16); return (st & 0x00C00000) == 0x00C00000; }   // WS_CAPTION: a real app window, not a tooltip/popup
  bool Loaded(string t) { if (t.Length == 0) return false; if (want.Length > 0) return t.IndexOf(want, StringComparison.OrdinalIgnoreCase) >= 0;
    foreach (var g in generic) if (string.Equals(t.Trim(), g, StringComparison.OrdinalIgnoreCase)) return false; return true; }
  void Cb(IntPtr hook, uint ev, IntPtr h, int idObject, int idChild, uint thread, uint time) {
    if (idObject != 0 || idChild != 0 || h == IntPtr.Zero) return;
    if (ev == 0x8000 || ev == 0x8002) {   // CREATE / SHOW
      if (hidden.ContainsKey(h)) { if (ev == 0x8002) { lock (hidden) if (!shown.ContainsKey(h)) shown[h] = (long)(time - t0); W.Hide(h, layered); } return; }   // the app showed it: note the first SHOW time; hide again (layered alpha 0 and off-screen meanwhile)
      if (W.GetAncestor(h, 2) != h) return;
      if (debug) log.Add("debug " + (ev == 0x8000 ? "CREATE" : "SHOW") + " " + h.ToInt64() + " pid " + W.Pid(h) + " mine " + Mine(h) + " captioned " + Captioned(h) + " style " + W.GetWindowLong(h, -16).ToString("X") + " vis " + W.IsWindowVisible(h) + " title " + W.Title(h));
      if (!Captioned(h) || !Mine(h)) return;
      long cr = (long)(time - t0); string kind = ev == 0x8000 ? "CREATE" : "SHOW"; bool vis = W.IsWindowVisible(h);
      lock (hidden) { hidden[h] = cr + " ?"; if (vis) vis0[h] = cr; }
      // the hide itself runs on a pool thread per window: SetWindowLong/SetWindowRgn synchronise with the window's own thread, and a
      // helper window of a busy thread (Firefox: 137 ms, Code: 254 ms) must not hold up the hook thread when the real window appears
      System.Threading.Interlocked.Increment(ref pending);
      System.Threading.ThreadPool.QueueUserWorkItem(_ => { try {
        // observer (measurement only, lives for this one hide): the first ms at which the window is off-screen / transparent / empty-region
        // as the kernel sees it; SetWindowPos/SetWindowLong return only after the app's thread has taken their messages, so their return
        // times overstate the moment the window stopped being showable
        long off = -1; var ow = new System.Threading.ManualResetEvent(false);
        System.Threading.ThreadPool.QueueUserWorkItem(__ => { for (int i = 0; i < 3000; i++) { if (W.Invisible(h)) { off = (long)(W.GetTickCount() - t0); break; } System.Threading.Thread.Sleep(1); } ow.Set(); });
        W.Hide(h, layered); var cw = System.Diagnostics.Stopwatch.StartNew(); int hr = W.SetCloak(h, 1); string ht = W.hideT + " cloak " + cw.ElapsedMilliseconds;
        long cl = (long)(W.GetTickCount() - t0);   // same clock as the event stamp (1 ms after timeBeginPeriod)
        ow.WaitOne(3100); long hid = off >= 0 && off < cl ? off : cl;
        lock (hidden) { hidden[h] = cr + " " + hid; long sh; string sv = shown.TryGetValue(h, out sh) ? " show-ms " + sh : ""; log.Add("event " + kind + " " + h.ToInt64() + " create-ms " + cr + " off-ms " + off + " cloak-ms " + cl + sv + " sw-ms " + sw.ElapsedMilliseconds + " vis " + vis + " cloak-hr " + hr + " [" + ht + "]"); }
      } finally { System.Threading.Interlocked.Decrement(ref pending); } });
      if (Loaded(W.Title(h))) done = true; return; }
    if (ev == 0x800B && hidden.ContainsKey(h) && !layered) { if (!W.EmptyRgn(h)) { W.Hide(h, false); moved++; } return; }   // the app reset its region (resize): empty it again
    if (ev == 0x800B && hidden.ContainsKey(h) && !W.OffScreen(h)) { W.SetWindowPos(h, IntPtr.Zero, -6000, 0, 0, 0, 0x0015); moved++; return; }   // LOCATIONCHANGE: the app put it back on screen (Firefox does ~1 s in)
    if (ev == 0x0003 && hidden.ContainsKey(h)) { if (fg0 != IntPtr.Zero && fg0 != h) { W.SetForegroundWindow(fg0); fgRestored++; } return; }   // FOREGROUND
    if (ev == 0x800C && hidden.ContainsKey(h)) { string t = W.Title(h); log.Add("event NAMECHANGE " + h.ToInt64() + " at-ms " + sw.ElapsedMilliseconds + " vis " + W.IsWindowVisible(h) + " title " + t); if (Loaded(t)) done = true; return; }   // NAMECHANGE
  }
  [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
  public static uint Period1() { return timeBeginPeriod(1); }
  // linger: after the hidden: line, keep ONE window hidden and off the taskbar for a few seconds on events only (no polling): the
  // app's own late setup (WT ~1.7 s: taskbar registration; Firefox ~1 s: moves the window back) comes after the title has loaded
  // and the launcher has exited. Hooks: explorer's CREATE..REORDER (a taskbar button being added) and the window's LOCATION/NAMECHANGE.
  IntPtr lh; bool llay; public int redid, deltabs;
  public int Linger(IntPtr h, bool layered, int ms) {
    lh = h; llay = layered; keep = new WinEventDelegate(LCb); IntPtr tray = W.FindWindowW("Shell_TrayWnd", null); uint shell = W.Pid(tray), app = W.Pid(h);
    var hks = new List<IntPtr> { SetWinEventHook(0x8000, 0x8004, IntPtr.Zero, keep, shell, 0, 0x0002), SetWinEventHook(0x8000, 0x800C, IntPtr.Zero, keep, app, 0, 0x0002) };   // the app's own object events (its pid only: cheap)
    SetTimer(IntPtr.Zero, UIntPtr.Zero, 250, IntPtr.Zero); sw.Restart(); MSG m;
    while (sw.ElapsedMilliseconds < ms && W.IsWindow(h) && W.GetPropW(h, "evshow-shown") == IntPtr.Zero && GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { TranslateMessage(ref m); DispatchMessage(ref m); }
    foreach (var x in hks) UnhookWinEvent(x); return 0; }
  void LCb(IntPtr hook, uint ev, IntPtr h, int obj, int child, uint tid, uint time) {
    if (!W.IsWindow(lh) || W.GetPropW(lh, "evshow-shown") != IntPtr.Zero) return;
    uint pid = W.Pid(h); if (pid == W.Pid(lh)) { if (h == lh || obj == 0) { if ((W.GetWindowLong(lh, -20) & 0x80) == 0 || !W.Invisible(lh)) { W.Hide(lh, llay); redid++; llog.Add("rehid on " + ev.ToString("X") + " " + h.ToInt64() + " at " + sw.ElapsedMilliseconds); } } return; }
    if (ev >= 0x8000 && ev <= 0x8004) { W.DeleteTab(lh); deltabs++; } }   // something changed in the shell's windows: make sure our button is gone
  public List<string> llog = new List<string>();
  public int Run(string exe, string args, int timeoutMs) {
    timeBeginPeriod(1); System.Threading.Thread.CurrentThread.Priority = System.Threading.ThreadPriority.Highest;
    fg0 = W.GetForegroundWindow(); Refresh();
    // warm up: JIT every method and load each native stub now, not inside the first event
    foreach (var t in new[] { typeof(Hider), typeof(W) }) foreach (var mi in t.GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly))
      if (!mi.IsAbstract && !mi.ContainsGenericParameters) System.Runtime.CompilerServices.RuntimeHelpers.PrepareMethod(mi.MethodHandle);
    W.Cloaked(fg0); W.Pid(fg0); W.GetAncestor(fg0, 2); W.GetWindowLong(fg0, -16); W.Title(fg0); W.IsWindowVisible(fg0); W.SetCloak(IntPtr.Zero, 1); W.Hide(IntPtr.Zero, true); W.Hide(IntPtr.Zero, false); W.Unhide(IntPtr.Zero); W.OffScreen(fg0); W.EmptyRgn(fg0); Loaded("warm"); Mine(fg0);
    System.Threading.ThreadPool.SetMinThreads(8, 8); for (int i = 0; i < 4; i++) System.Threading.ThreadPool.QueueUserWorkItem(_ => { W.OffScreen(IntPtr.Zero); });   // pool threads exist before the first event
    keep = new WinEventDelegate(Cb);
    // five narrow hooks (FOREGROUND, CREATE, SHOW, LOCATIONCHANGE, NAMECHANGE), not one 0x0003-0x800C range: the wide range queued
    // every focus/state/value event of every app in front of a CREATE (26 ms of delivery latency seen)
    var hks = new List<IntPtr>(); foreach (uint e in new uint[] { 0x0003, 0x8000, 0x8002, 0x800B, 0x800C }) hks.Add(SetWinEventHook(e, e, IntPtr.Zero, keep, 0, 0, 0x0002));   // OUTOFCONTEXT|SKIPOWNPROCESS
    IntPtr hk = hks[1]; foreach (var x in hks) if (x == IntPtr.Zero) hk = IntPtr.Zero;
    if (hk == IntPtr.Zero) { log.Add("hook failed"); return 2; }
    t0 = W.GetTickCount(); sw.Restart();
    // the launch runs on its own thread: ShellExecute can take hundreds of ms (VS Code), and the hook thread must be in GetMessage for every event
    string fail = null; var th = new System.Threading.Thread(() => { try { var psi = new System.Diagnostics.ProcessStartInfo(exe, args); psi.UseShellExecute = true;
      if (exe.EndsWith("wsl.exe", StringComparison.OrdinalIgnoreCase)) psi.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;   // console launcher: no console window
      var pr = System.Diagnostics.Process.Start(psi); lock (pids) pids.Add((uint)pr.Id); } catch (Exception e) { fail = e.Message; done = true; } });
    th.Start();
    SetTimer(IntPtr.Zero, UIntPtr.Zero, 100, IntPtr.Zero);   // WM_TIMER wakes GetMessage so the deadline is checked; no work is done on it
    MSG m; while (!done && sw.ElapsedMilliseconds < timeoutMs && GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { TranslateMessage(ref m); DispatchMessage(ref m); }
    foreach (var x in hks) UnhookWinEvent(x); for (int i = 0; i < 200 && pending > 0; i++) System.Threading.Thread.Sleep(10);   // let the last hide finish (its log line and cloak-ms)
    if (fail != null) { log.Add("launch failed: " + fail); return 3; } return done ? 0 : 1; }
}
"@
Add-Type -TypeDefinition $Src
[W]::SetProcessDPIAware() | Out-Null
$Reg = if ($env:EVSHOW_LAUNCHED) { $env:EVSHOW_LAUNCHED } else { Join-Path $PSScriptRoot 'launched.txt' }   # per-session registry (win.sh sets it)
if (Test-Path $Reg) { foreach ($l in Get-Content $Reg) { $n = 0L; if ([int64]::TryParse($l.Split('|')[0], [ref]$n)) { [void][W]::Reg.Add([IntPtr]$n) } } }
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
      if ([W]::Hidden($h)) {
        # A --hidden window: place it and set its z-order while it is still invisible (alpha 0), un-hide last, so its first frame is in place.
        if (-not [W]::IsWindowVisible($h)) { [W]::ShowWindow($h, 4) | Out-Null }
        PutWin $h $px $py $pw $ph; if ($Behind) { Bottom $h } else { Top $h $true }; Start-Sleep -Milliseconds 100; PutWin $h $px $py $pw $ph
        [W]::Unhide($h); [W]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, 0, 0, 0x0037) | Out-Null   # FRAMECHANGED|NOMOVE|NOSIZE|NOZORDER|NOACTIVATE: style change takes effect
      } else {
        if (-not [W]::IsIconic($h)) { [W]::ShowWindow($h, 6) | Out-Null; Start-Sleep -Milliseconds 300 }
        Unmin $h; Start-Sleep -Milliseconds 300; PutWin $h $px $py $pw $ph; if ($Behind) { Bottom $h } else { Top $h $true } }
      if ([W]::Cloaked($h) -ne 0) { [W]::SetCloak($h, 0) | Out-Null }; Start-Sleep -Milliseconds $pause
      $r = New-Object W+R; [W]::GetWindowRect($h, [ref]$r) | Out-Null; $why = @()
      if ([W]::IsIconic($h)) { $why += 'minimized' }
      if ([W]::Hidden($h)) { $why += 'cloaked' }
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

function Register($h, $tok) { if (-not [W]::Reg.Contains($h)) { Add-Content -Path $Reg -Value "$([int64]$h)|$tok" }; [void][W]::Reg.Add($h) }   # once per HWND
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
  'unhide' { $h = Hw $p[0]; [W]::Unhide($h); "unhidden $([int64]$h) (still at $(Rect $h); place it)" }   # harness stand-ins opened hidden
  'wininfo' { $h = Hw $p[0]; "$([int64]$h) $(Rect $h) $([int][W]::IsZoomed($h))" }   # same shape as a `term` line: HWND L T W H MAX
  'bottom' { $h = Owned $p[0]; Bottom $h; "bottom: $([W]::Title($h))" }
  'front' { $h = Owned $p[0]; Unmin $h; if ($Behind) { Bottom $h } else { Top $h $true }
    if ([W]::IsIconic($h)) { "error: window $($p[0]) still minimized"; exit 1 }; "front: $([W]::Title($h)) $(Rect $h)" }
  'untop' { $h = Hw $p[0]; Top $h $false; "untop: $([W]::Title($h))" }
  'close' { $h = Owned $p[0]; $t = [W]::Title($h); [W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; "closed: $t" }
  'place' { $h = Owned $p[0]; Unmin $h; PutWin $h $p[1] $p[2] $p[3] $p[4]; "placed: $([W]::Title($h)) $(Rect $h)" }
  'list-all' { [W]::All() | ForEach-Object { "$([int64]$_) $([W]::Title($_))" } }
  'list-z' { [W]::All() | ForEach-Object { "$([int64]$_)|$([int](([W]::GetWindowLong($_, -20) -band 8) -ne 0))|$([int][W]::Hidden($_))|$([W]::Title($_))" } }   # z-order top to bottom
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
    if ([W]::Hidden($h)) { "prepped: $([int64]$h) $([W]::Title($h)) (cloaked)"; exit 0 }   # a --hidden window: already invisible, never minimized
    for ($i = 0; $i -lt 8 -and -not [W]::IsIconic($h); $i++) { [W]::ShowWindow($h, 6) | Out-Null; Start-Sleep -Milliseconds 250 }
    if (-not [W]::IsIconic($h)) { "not prepped: window $([int64]$h) would not minimize"; exit 1 }
    "prepped: $([int64]$h) $([W]::Title($h))"; exit 0 }
  'min' { $h = Owned $p[0]; [W]::ShowWindow($h, 6) | Out-Null; "minimized: $([W]::Title($h))" }
  'linger' { # linger|HWND|layered(1/0)|ms : see Hider.Linger (win-app.sh --hidden starts it detached after the hidden: line)
    $hd = New-Object Hider; $h = Hw $p[0]; [void]$hd.Linger($h, ($p[1] -eq '1'), [int]$p[2]); "linger done: rehid $($hd.redid) deltab $($hd.deltabs)"; $hd.llog | ForEach-Object { "linger: $_" } }
  'hidden' { # hidden|app|exe|args|title|timeout-s : WinEvent hook, launch, cloak every new top-level window of the app family from its CREATE event.
    $app = $p[0]; $exe = $p[1]; $args = $p[2]; $want = if ($p.Count -gt 3) { $p[3] } else { '' }; $to = if ($p.Count -gt 4 -and $p[4]) { [double]$p[4] } else { 20 }
    $hd = New-Object Hider; $hd.want = $want; $hd.debug = ($env:EVSHOW_HIDE_DEBUG -eq '1'); $hd.layered = -not ($app -eq 'code' -and $env:EVSHOW_CODE_REGION -eq '1')   # mode 1 for every app; EVSHOW_CODE_REGION=1 = old mode 2 for VS Code
    switch ($app) { 'firefox' { $hd.names = @('firefox') }; 'code' { $hd.names = @('Code') }; 'wt' { $hd.names = @('WindowsTerminal', 'wt', 'OpenConsole') }; default { $hd.names = @($app) } }
    $hd.generic = @('Mozilla Firefox', 'Visual Studio Code', 'Windows Terminal', 'Firefox', 'Code')
    $rc = $hd.Run($exe, $args, [int]($to * 1000))
    foreach ($kv in $hd.hidden.GetEnumerator()) { $h = $kv.Key; $t = [W]::Title($h); $tok = if ($want) { $want } else { $t }   # helper windows (never visible, no title) are cloaked too but not reported
      if ([W]::IsWindow($h) -and $t.Length -gt 0 -and ($want -eq '' -or $t.IndexOf($want, [StringComparison]::OrdinalIgnoreCase) -ge 0)) { Register $h $tok; "hidden: $([int64]$h) $($hd.Exposure($h)) $t (create $($kv.Value))" } }
    $hd.log | ForEach-Object { "hide-log: $_" }; if ($hd.fgRestored) { "hide-log: foreground given back $($hd.fgRestored)x" }; if ($hd.moved) { "hide-log: moved back off-screen $($hd.moved)x" }
    if ($rc -ne 0) { foreach ($h in $hd.hidden.Keys) { $r = New-Object W+R; [W]::GetWindowRect($h, [ref]$r) | Out-Null   # register what was hidden anyway, so close-cloaked can clean it up
        if ([W]::IsWindow($h) -and ($r.Rt - $r.L) -gt 300) { Register $h $(if ($want) { $want } else { 'hidden' }) } }
      $why = switch ($rc) { 1 { "title not loaded within ${to}s (want '$want'; hidden $($hd.hidden.Count) window(s))" } 2 { 'SetWinEventHook failed' } 3 { $hd.log[-1] } }
      "not hidden: $why"; exit 1 }
    exit 0 }
  'me' { # me|marker : exactly one Windows Terminal window whose title holds the marker, else one whose terminal TEXT holds it (UI
    # Automation TextPattern on WT's TermControl: a tab renamed by hand ignores application titles, so win.sh also shows the marker
    # as a tmux status message) -> "me: HWND L T W H MAX"; else "not found" + candidates (exit 1)
    $m = @(Matches $p[0]); if ($m.Count -eq 1) { "me: $([int64]$m[0]) $(Rect $m[0]) $([int][W]::IsZoomed($m[0]))"; exit 0 }
    if ($m.Count -eq 0) { Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
      $cw = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'CASCADIA_HOSTING_WINDOW_CLASS')
      $cc = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'TermControl')
      foreach ($w in [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cw)) {
        foreach ($d in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cc)) {
          try { $tp = $d.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern); if ($tp.DocumentRange.GetText(400000).Contains($p[0])) { $m += [IntPtr]$w.Current.NativeWindowHandle; break } } catch { } } }
      if ($m.Count -eq 1) { "me: $([int64]$m[0]) $(Rect $m[0]) $([int][W]::IsZoomed($m[0])) (text marker)"; exit 0 } }
    $c = @([W]::All() | Where-Object { $t = [W]::Title($_); $t -match 'Terminal|Ubuntu|WSL|bash|claude|tmux' })
    "not found: $($m.Count) windows hold '$($p[0])'; candidates:`n$(Cands $c)"; exit 1 }
  'close-cloaked' { # close every window this session registered that still exists and is cloaked (never shown): nothing cloaked is left behind
    if (Test-Path $Reg) { foreach ($l in Get-Content $Reg) { $n = 0L; if ([int64]::TryParse($l.Split('|')[0], [ref]$n)) { $h = [IntPtr]$n
      if ([W]::IsWindow($h) -and [W]::Hidden($h)) { $t = [W]::Title($h); [W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; "closed cloaked: $([int64]$h) $t" } } } } }
  'zlog' { # zlog|seconds : every 100 ms one block "t <ET time>" then "HWND|topmost|cloaked|iconic|L T W H|title" per visible titled window, top to bottom
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time'); $end = (Get-Date).AddSeconds([double]$p[0])
    [void][Hider]::Period1(); $clock = [Diagnostics.Stopwatch]::StartNew(); $n = 0   # 1 ms timer so Sleep lands within ~1 ms; absolute schedule so cost never drifts the rate
    while ((Get-Date) -lt $end) {
      $t0 = Get-Date; $now = [TimeZoneInfo]::ConvertTime($t0, $tz); $o = New-Object System.Text.StringBuilder; [void]$o.Append("t $($now.ToString('HH:mm:ss.fff'))`n")
      foreach ($h in [W]::All()) { $r = New-Object W+R; [W]::GetWindowRect($h, [ref]$r) | Out-Null
        [void]$o.Append("$([int64]$h)|$([int](([W]::GetWindowLong($h, -20) -band 8) -ne 0))|$([int][W]::Hidden($h))|$([int][W]::IsIconic($h))|$($r.L) $($r.T) $($r.Rt-$r.L) $($r.B-$r.T)|$([W]::Title($h))`n") }
      [Console]::Out.Write($o.ToString()); [Console]::Out.Flush()
      $n++; $rest = $n * 100 - $clock.ElapsedMilliseconds; if ($rest -gt 0) { Start-Sleep -Milliseconds $rest } } }   # 10 samples/s whatever the enumeration costs
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
    if ($p[0] -and $p[0] -ne '0') { $n0 = 0L; [void][int64]::TryParse($p[0], [ref]$n0)
      if (-not [W]::IsWindow([IntPtr]$n0)) { "old window $($p[0]) already gone (never shown or closed): nothing to close" }   # a failed previous item is not an error here
      else { $o = Owned $p[0]; Top $o $false; $ot = [W]::Title($o); [W]::PostMessage($o, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; "closed: $ot" } }
    $r = @(ShowIt $p[1] $p[2] $p[3] $p[4] $p[5] ([double]$p[6]) $term)
    if ($p.Count -gt 8 -and $p[8] -and [int]$r[-1] -eq 0) { Capture $p[8] }   # 9th arg: capture path, taken right after shown
    Done $r }
  default { "error: unknown action '$Action'"; exit 1 }
}
