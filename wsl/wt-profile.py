#!/usr/bin/env python3
"""Point the Windows Terminal profile for this WSL distro at tmux-quad.

Usage: wt-profile.py <settings.json> <distro> <commandline>
"""
import json, shutil, sys

path, distro, cmd = sys.argv[1:4]
try:
    with open(path, encoding="utf-8-sig") as f:
        s = json.load(f)
except json.JSONDecodeError:
    sys.exit(f"{path} has comments or is not plain JSON; add \"commandline\": \"{cmd}\" to the {distro} profile by hand")

hits = [p for p in s.get("profiles", {}).get("list", [])
        if p.get("source") == "Microsoft.WSL" and p.get("name") == distro]
if not hits:
    sys.exit(f"no Windows Terminal profile for WSL distro {distro!r}")
if all(p.get("commandline") == cmd for p in hits):
    print(f"Windows Terminal {distro} profile already runs tmux-quad")
    sys.exit()

shutil.copy(path, path + ".pre-link")
for p in hits:
    p["commandline"] = cmd
with open(path, "w", encoding="utf-8") as f:
    json.dump(s, f, indent=4)
    f.write("\n")
print(f"Windows Terminal {distro} profile now runs tmux-quad (backup: settings.json.pre-link)")
