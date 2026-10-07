# Sets Windows Terminal to a fixed volume in the Windows volume mixer, once per logon.
# Windows resets it to 100% after reboots. The mixer entry only exists after Terminal first plays a sound,
# so this waits (idle, event-driven) for that, sets $Level, and exits.
param([int]$Level = 18, [string]$Process = 'WindowsTerminal')
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Diagnostics; using System.Threading;
[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"), ComImport] class MMDeviceEnumerator {}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDeviceEnumerator { int NotImpl1(); int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ep); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionManager2 { int a(); int b(); int GetSessionEnumerator(out IAudioSessionEnumerator e); int RegisterSessionNotification(IAudioSessionNotification n); int UnregisterSessionNotification(IAudioSessionNotification n); }
[Guid("641DD20B-4D41-49CC-ABA3-174B9477BB08"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown), ComVisible(true)] public interface IAudioSessionNotification { [PreserveSig] int OnSessionCreated([MarshalAs(UnmanagedType.IUnknown)] object s); }
[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionEnumerator { int GetCount(out int c); int GetSession(int i, out IAudioSessionControl2 s); }
[Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionControl2 { int a(); int b(); int c(); int d(); int e(); int f(); int g(); int h(); int i(); int j(); int k(); int GetProcessId(out uint pid); }
[Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface ISimpleAudioVolume { int SetMasterVolume(float l, ref Guid g); }
[ComVisible(true)] public class TermVol : IAudioSessionNotification {
  string proc; float level; ManualResetEvent done = new ManualResetEvent(false);
  TermVol(string p, float l) { proc = p; level = l; }
  bool TrySet(object o) {
    var s = (IAudioSessionControl2)o; uint pid; s.GetProcessId(out pid);
    try { if (Process.GetProcessById((int)pid).ProcessName != proc) return false; } catch { return false; }
    var g = Guid.Empty; ((ISimpleAudioVolume)s).SetMasterVolume(level, ref g); return true;
  }
  public int OnSessionCreated(object s) { try { if (TrySet(s)) done.Set(); } catch {} return 0; }
  public static void Run(string proc, float level) {
    var me = new TermVol(proc, level);
    var en = (IMMDeviceEnumerator)(new MMDeviceEnumerator()); IMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
    var iid = typeof(IAudioSessionManager2).GUID; object o; dev.Activate(ref iid, 23, IntPtr.Zero, out o);
    var mgr = (IAudioSessionManager2)o;
    mgr.RegisterSessionNotification(me);
    IAudioSessionEnumerator se; mgr.GetSessionEnumerator(out se); int n; se.GetCount(out n);
    for (int i = 0; i < n; i++) { IAudioSessionControl2 s; se.GetSession(i, out s); if (me.TrySet(s)) me.done.Set(); }
    me.done.WaitOne();
    mgr.UnregisterSessionNotification(me);
  }
}
"@
[TermVol]::Run($Process, $Level / 100.0)
