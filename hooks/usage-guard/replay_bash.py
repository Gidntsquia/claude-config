#!/usr/bin/env python3
"""Offline replay for usage-guard: feed the Bash/Monitor commands a worker really ran through the hook and count
what it would have allowed and blocked. Nothing is launched: temp HOME, PATH holding only a fake `claude` that exits
99 and leaves a marker (the replay fails if it is ever run), the clock set to each command's own timestamp.

  replay_bash.py <claude project log dir> [--all] [-v]
Default: the commands that mention agent-replay's run.sh, scene.sh or drive.py (the Nov 5-7 assistant-agent runs).
--all: every Bash/Monitor command in the logs (the false-block check); -v prints one row per command.
Exit 1 when under 90% of the full-suite `run.sh -j >=3` commands are blocked, or when the fake claude was run.
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime

HERE = os.path.dirname(os.path.realpath(__file__))
PICK = re.compile(r"\b(run\.sh|scene\.sh|drive\.py)\b")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1.*?\n\2\b", re.S)


def commands(logdir):
    seen, rows = set(), []
    for path in sorted(glob.glob(os.path.join(logdir, "**", "*.jsonl"), recursive=True)):
        for line in open(path, errors="ignore"):
            if '"tool_use"' not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            content = (rec.get("message") or {}).get("content")
            for b in content if isinstance(content, list) else []:
                if b.get("type") == "tool_use" and b.get("name") in ("Bash", "Monitor") and b.get("id") not in seen:
                    seen.add(b.get("id"))
                    cmd = (b.get("input") or {}).get("command") or ""
                    if cmd and rec.get("timestamp"):
                        rows.append((rec["timestamp"], rec.get("cwd") or "", b["name"], cmd, b["input"]))
    return sorted(rows, key=lambda r: r[0])


def full_suite_j(cmd, cwd=""):
    """N when the command itself runs the whole suite at -j N >= 3 (run.sh with -j N, or no -j: the script's default
    of 3, and no scene names), outside heredoc text and comments; else 0"""
    text = HEREDOC.sub("", cmd)
    text = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
    best = 0
    for seg in re.split(r"[;&|\n()]+", text):
        words = seg.split(">")[0].split()
        while words and (words[0] in ("time", "nohup", "bash", "sh", "do", "then", "-x") or re.fullmatch(r"\w+=\S*", words[0])):
            words = words[1:]
        if not words or not re.search(r"(agent-replay/|^\./|^)run\.sh$", words[0].strip("\"'")):
            continue
        if "agent-replay" not in words[0] and "agent-replay" not in text.split(seg)[0] and not cwd.endswith("agent-replay"):
            continue
        args, j, names, i = words[1:], 3, 0, 0
        while i < len(args):
            if args[i] == "-j" and i + 1 < len(args) and args[i + 1].isdigit():
                j = int(args[i + 1]); i += 2; continue
            if re.fullmatch(r"-j\d+", args[i]):
                j = int(args[i][2:])
            elif not args[i].startswith("-") and not args[i][0].isdigit():
                names += 1
            i += 1
        if names == 0 and j >= 3:
            best = max(best, j)
    return best


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    every, verbose = "--all" in sys.argv, "-v" in sys.argv
    rows = commands(args[0])
    if not every:
        rows = [r for r in rows if PICK.search(r[3])]
    tmp = tempfile.mkdtemp()
    os.makedirs(os.path.join(tmp, "bin"))
    marker = os.path.join(tmp, "claude-called")
    with open(os.path.join(tmp, "bin", "claude"), "w") as f:
        f.write(f"#!/bin/sh\necho called >> '{marker}'\nexit 99\n")
    os.chmod(os.path.join(tmp, "bin", "claude"), 0o755)
    py = os.path.dirname(sys.executable)
    env = {"HOME": tmp, "PATH": os.path.join(tmp, "bin") + os.pathsep + py + ":/usr/bin:/bin"}
    allowed = blocked = suites = suites_blocked = 0
    why, worst = {}, 0.0
    for ts, cwd, tool, cmd, ti in rows:
        epoch = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
        data = {"hook_event_name": "PreToolUse", "tool_name": tool, "agent_type": "worker", "session_id": "replay",
                "cwd": cwd if os.path.isdir(cwd) else tmp, "tool_input": ti}
        t0 = datetime.now()
        p = subprocess.run([sys.executable, os.path.join(HERE, "usage_guard.py"), "--now", str(epoch), "--live", "0"],
                           input=json.dumps(data), capture_output=True, text=True, env=env)
        worst = max(worst, (datetime.now() - t0).total_seconds())
        n = full_suite_j(cmd, cwd)
        suites += bool(n)
        if p.returncode == 2:
            blocked += 1
            suites_blocked += bool(n)
            m = re.search(r"usage-guard: (\d+ parallel|\d+/\d+ (?:headless )?launches|guard state|.*lacks)", p.stderr)
            kind = {"p": "R3 parallel", "l": "R5 daily cap", "g": "R6 guard state"}.get((m.group(1).split()[-1][0] if m else "?"), "R4 flags")
            if m and "lacks" in m.group(1):
                kind = "R4 flags"
            why[kind] = why.get(kind, 0) + 1
        elif p.returncode == 0:
            allowed += 1
        else:
            print(f"hook error {p.returncode}: {p.stderr.strip()[:300]}\n  on: {cmd[:200]!r}")
            blocked += 1
            why["hook error"] = why.get("hook error", 0) + 1
        if verbose or (n and p.returncode != 2):
            flag = "BLOCK" if p.returncode == 2 else "allow"
            print(f"{flag}  {ts[:16]}  {'suite -j %d' % n if n else '':11} {' '.join(cmd.split())[:110]}")
            if verbose and p.returncode == 2:
                print(f"       {p.stderr.strip()[:150]}")
    called = os.path.exists(marker)
    days = sorted({r[0][:10] for r in rows})
    print(f"replayed {len(rows)} commands ({days[0] if days else '-'} to {days[-1] if days else '-'} UTC): "
          f"{allowed} allowed, {blocked} blocked " + (str(dict(sorted(why.items()))) if why else ""))
    print(f"full-suite runs at -j >= 3: {suites_blocked}/{suites} blocked"
          + (f" ({100 * suites_blocked / suites:.0f}%)" if suites else "") + f"; slowest hook call {worst * 1000:.0f} ms"
          + ("; FAKE CLAUDE WAS RUN" if called else "; fake claude never run"))
    subprocess.run(["rm", "-rf", tmp])
    if called or (not every and suites and suites_blocked / suites < 0.9):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
