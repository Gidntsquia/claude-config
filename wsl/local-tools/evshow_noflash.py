#!/usr/bin/env python3
"""evshow_noflash.py <state dir>  -> one line "no-flash: PASS (...)" / "no-flash: FAIL (...)", exit 1 on FAIL.
Reads this session's files: `hidden` (win-app.sh --hidden lines: "<ET time> hidden: HWND <create-ms> <cloak-ms> <title>"),
`zlog` (win.sh zlog: blocks "t HH:MM:SS.fff" then "HWND|topmost|cloaked|iconic|L T W H|title"), `history` (evshow.sh: "show-start
HH:MM:SS.fff" then "shown: HWND title L T W H" per item). A run window (any HWND in `hidden` or `launched.txt`) counts as
flashed when a zlog sample before its own show-start (or before the first show-start, if it was never shown) has it
un-cloaked, not minimized, wider than 300 px and with its left edge above -1000 (on-screen). A hidden: line with
cloak-ms - create-ms > 16 is a FAIL too (one composed frame is possible)."""
import re, sys
from pathlib import Path

def t2s(t):
    h, m, s = t.split(":"); return int(h) * 3600 + int(m) * 60 + float(s)

def analyze(d):
    """-> (ok, line, zlog samples, zlog span in s)"""
    d = Path(d)
    hidden = [l for l in (d / "hidden").read_text().splitlines() if "hidden: " in l] if (d / "hidden").exists() else []
    hid = {}   # hwnd -> (create, cloak, title)
    for l in hidden:
        m = re.search(r"hidden: (\d+) (\d+) (\d+) ?(.*)$", l)
        if m: hid[m.group(1)] = (int(m.group(2)), int(m.group(3)), m.group(4))
    run = set(hid)
    lp = d / "launched.txt"
    if lp.exists():
        run |= {l.split("|", 1)[0] for l in lp.read_text().splitlines() if "|" in l and not l.split("|", 1)[1].startswith("evstandin")}
    hist = (d / "history").read_text().splitlines() if (d / "history").exists() else []
    shows, cur = {}, None   # hwnd -> show-start seconds
    first = None
    for l in hist:
        m = re.match(r"show-start (\d\d:\d\d:\d\d\.\d+)", l)
        if m: cur = t2s(m.group(1)); first = cur if first is None else min(first, cur); continue
        m = re.match(r"shown: (\d+) ", l)
        if m and cur is not None: shows[m.group(1)] = cur
    samples, bad, tmin, tmax = 0, [], None, None
    z = d / "zlog"
    if z.exists():
        t = None
        for l in z.read_text(errors="replace").splitlines():
            if l.startswith("t "):
                t = t2s(l[2:].strip()); samples += 1
                tmin = t if tmin is None else min(tmin, t); tmax = t if tmax is None else max(tmax, t); continue
            f = l.split("|")
            if t is None or len(f) < 6 or f[0] not in run: continue
            hwnd, cloaked, iconic = f[0], f[2], f[3]
            try: L, T, W, H = map(int, f[4].split())
            except ValueError: continue
            limit = shows.get(hwnd, first)
            if limit is None or t >= limit: continue
            if cloaked == "0" and iconic == "0" and W > 300 and L > -1000:
                bad.append(f"{hwnd} on-screen at {f[4]} before its show (sample t={t:.3f}s, show-start {limit:.3f}s)")
    slow = [f"{h} hide {c - a} ms ({a}->{c})" for h, (a, c, _) in hid.items() if c - a > 16]
    maxhide = max([c - a for a, c, _ in hid.values()], default=0)
    span = (tmax - tmin) if samples > 1 else 0.0
    if not hidden and not z.exists():
        return False, "no-flash: FAIL (no hidden log and no zlog in this session's state dir)", samples, span
    if bad or slow:
        return False, "no-flash: FAIL (" + "; ".join(bad[:3] + slow[:3]) + f"; {samples} zlog samples)", samples, span
    return True, (f"no-flash: PASS ({len(hid)} window(s) cloaked from creation, max hide {maxhide} ms, {samples} zlog samples over "
                  f"{span:.1f} s, {len(run)} run window(s) never on-screen before their show)"), samples, span

def main(d):
    ok, line, _, _ = analyze(d); print(line); return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
