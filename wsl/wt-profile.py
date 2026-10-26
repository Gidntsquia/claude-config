#!/usr/bin/env python3
"""Point the Windows Terminal profile for this WSL distro at tmux-quad, in a Nerd Font.

Usage: wt-profile.py <settings.json> <distro> <commandline> <font face> [--default]
       wt-profile.py --check <settings.json> <distro> <commandline>

--default also makes that profile the one new Windows Terminal windows open with (defaultProfile).
--check exits 0 when the distro's profile runs <commandline>, 1 otherwise; it changes nothing.
"""
import json, shutil, sys

args = sys.argv[1:]
check = "--check" in args
make_default = "--default" in args
args = [a for a in args if a not in ("--check", "--default")]
if len(args) < (3 if check else 4):
    sys.exit(__doc__)
path, distro, cmd = args[:3]
font = None if check else args[3]
try:
    with open(path, encoding="utf-8-sig") as f:
        s = json.load(f)
except json.JSONDecodeError:
    sys.exit(f"{path} has comments or is not plain JSON; add \"commandline\": \"{cmd}\" to the {distro} profile by hand")

hits = [p for p in s.get("profiles", {}).get("list", [])
        if p.get("source") == "Microsoft.WSL" and p.get("name") == distro]
if check:
    ok = any(p.get("commandline") == cmd for p in hits)
    print(f"Windows Terminal {distro} profile {'runs' if ok else 'does not run'} tmux-quad")
    sys.exit(0 if ok else 1)
if not hits:
    sys.exit(f"no Windows Terminal profile for WSL distro {distro!r}")
guid = hits[0].get("guid")
done = all(p.get("commandline") == cmd and p.get("font", {}).get("face") == font for p in hits)
if done and (not make_default or s.get("defaultProfile") == guid):
    print(f"Windows Terminal {distro} profile already runs tmux-quad in {font}" + (" and is the default" if make_default else ""))
    sys.exit()

shutil.copy(path, path + ".pre-link")
for p in hits:
    p["commandline"] = cmd
    p.setdefault("font", {})["face"] = font
old_default = s.get("defaultProfile")
if make_default and guid:
    s["defaultProfile"] = guid
with open(path, "w", encoding="utf-8") as f:
    json.dump(s, f, indent=4)
    f.write("\n")
print(f"Windows Terminal {distro} profile now runs tmux-quad in {font} (backup: settings.json.pre-link)")
if make_default and guid and old_default != guid:
    print(f"  and is the default profile; to undo, pick your old default in Windows Terminal > Settings > Startup (was {old_default})")
