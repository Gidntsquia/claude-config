#!/usr/bin/env python3
"""Offline replay of real Agent-tool launches through usage-guard (the Oct 25-31 Spire fan-out by default).

Each Agent tool_use found in the project's logs goes to the hook as a worker's call, with the clock set to the
call's own timestamp, a temp HOME, and a PATH holding only a fake `claude` that exits 99 and leaves a marker (the
replay fails if it is ever run). An allowed launch is then started and stopped at the times the real subagent ran
(SubagentStart / SubagentStop), so the "3 running" rule sees the same overlap the real session had.

  replay_agents.py [log dir] [--from 2026-10-25] [--to 2026-10-31]      dates are ET, both included
Prints one row per call: time (ET), verdict, count after, type sent -> type run, model asked -> model the forced
subagent model gives, description, and the block reason.
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.realpath(__file__))
ET = ZoneInfo("America/New_York")
FORCED = "sonnet"   # CLAUDE_CODE_SUBAGENT_MODEL, set with ..._FORCE=1 by run-agent for a worker
DEFAULT = os.path.expanduser("~/.claude/projects/-home-jaxon-files-slay-the-spire-advisor")


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def collect(logdir, first, last):
    calls, ends = {}, {}
    for path in glob.glob(os.path.join(logdir, "**", "*.jsonl"), recursive=True):
        sub = os.path.basename(os.path.dirname(path)) == "subagents"
        if sub:   # when did this subagent finish: its last record
            try:
                meta = json.load(open(path[:-6] + ".meta.json"))
                lines = open(path, errors="ignore").read().splitlines()
                stamps = [json.loads(l).get("timestamp") for l in (lines[0], lines[-1])]
                if meta.get("toolUseId") and stamps[1]:
                    ends[meta["toolUseId"]] = ts(stamps[1])
            except (OSError, ValueError, IndexError):
                pass
        for line in open(path, errors="ignore"):
            if '"tool_use"' not in line and '"tool_result"' not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            content = (rec.get("message") or {}).get("content")
            for b in content if isinstance(content, list) else []:
                if not isinstance(b, dict) or not rec.get("timestamp"):
                    continue
                if b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task") and "prompt" in (b.get("input") or {}):
                    calls.setdefault(b["id"], (ts(rec["timestamp"]), rec.get("sessionId") or "", rec.get("cwd") or "", b["input"]))
                elif b.get("type") == "tool_result" and b.get("tool_use_id") in calls:
                    # a foreground subagent ends at its tool_result; a background one returns at once and ends
                    # with its transcript (set above), so keep the later of the two
                    i = b["tool_use_id"]
                    ends[i] = max(ends.get(i, 0), ts(rec["timestamp"]))
    rows = []
    for i, (t, session, cwd, inp) in calls.items():
        day = datetime.fromtimestamp(t, ET).strftime("%Y-%m-%d")
        if first <= day <= last:
            rows.append((t, i, session, cwd, inp, max(ends.get(i, t + 600), t + 1)))
    return sorted(rows)


def main():
    argv = sys.argv[1:]
    opt = {"--from": "2026-10-25", "--to": "2026-10-31"}
    pos = []
    while argv:
        a = argv.pop(0)
        if a in opt:
            opt[a] = argv.pop(0)
        else:
            pos.append(a)
    logdir = pos[0] if pos else DEFAULT
    rows = collect(logdir, opt["--from"], opt["--to"])
    tmp = tempfile.mkdtemp()
    os.makedirs(os.path.join(tmp, "bin"))
    os.makedirs(os.path.join(tmp, "slay-the-spire-advisor", ".git"))
    marker = os.path.join(tmp, "claude-called")
    with open(os.path.join(tmp, "bin", "claude"), "w") as f:
        f.write(f"#!/bin/sh\necho called >> '{marker}'\nexit 99\n")
    os.chmod(os.path.join(tmp, "bin", "claude"), 0o755)
    env = {"HOME": tmp, "PATH": os.path.join(tmp, "bin")}
    cwd = os.path.join(tmp, "slay-the-spire-advisor")

    def hook(data, now):
        return subprocess.run([sys.executable, os.path.join(HERE, "usage_guard.py"), "--now", str(now), "--live", "0"],
                              input=json.dumps(data), capture_output=True, text=True, env=env)

    running, allowed, blocked, why = [], 0, 0, {}
    print(f"{'time (ET)':16} {'verdict':7} {'count':>5}  {'type sent -> run':27} {'model asked -> run':20} description")
    for t, tid, session, _, inp, end in rows:
        for e, s, i in sorted(running):
            if e <= t:
                hook({"hook_event_name": "SubagentStop", "session_id": s, "agent_id": i, "cwd": cwd}, e)
        running = [r for r in running if r[0] > t]
        p = hook({"hook_event_name": "PreToolUse", "tool_name": "Agent", "agent_type": "worker", "session_id": session,
                  "cwd": cwd, "tool_use_id": tid, "tool_input": inp}, t)
        when = datetime.fromtimestamp(t, ET).strftime("%b %d %I:%M %p")
        st, model = inp.get("subagent_type") or "(default)", inp.get("model") or "(inherit)"
        count = "?"
        try:
            count = open(os.path.join(tmp, ".cache", "claude-guard", "slay-the-spire-advisor",
                                      datetime.fromtimestamp(t, ET).strftime("%Y-%m-%d") + ".count")).read().strip()
        except OSError:
            count = "0"
        desc = " ".join((inp.get("description") or inp.get("prompt") or "").split())[:44]
        if p.returncode == 0:
            allowed += 1
            hook({"hook_event_name": "SubagentStart", "session_id": session, "agent_id": tid, "agent_type": "helper", "cwd": cwd}, t)
            running.append((end, session, tid))
            print(f"{when:16} {'ALLOW':7} {count + '/30':>5}  {st + ' -> helper':27} {model + ' -> ' + FORCED:20} {desc}")
        elif p.returncode == 2:
            blocked += 1
            reason = p.stderr.strip().replace("blocked by usage-guard: ", "")
            kind = "duplicate" if "already dispatched" in reason else "3 running" if "subagents running" in reason else "daily cap" if "launches used" in reason else "other"
            why[kind] = why.get(kind, 0) + 1
            print(f"{when:16} {'BLOCK':7} {count + '/30':>5}  {st + ' -> -':27} {model + ' -> -':20} {desc}\n{'':24}{reason}")
        else:
            print(f"{when:16} ERROR {p.returncode}: {p.stderr.strip()[:200]}")
            why["hook error"] = why.get("hook error", 0) + 1
    called = os.path.exists(marker)
    print(f"\n{len(rows)} Agent calls, {opt['--from']} to {opt['--to']} ET: {allowed} allowed, {blocked} blocked {dict(sorted(why.items()))}; "
          f"every allowed launch runs as helper on {FORCED}; " + ("FAKE CLAUDE WAS RUN" if called else "fake claude never run"))
    subprocess.run(["rm", "-rf", tmp])
    return 1 if called or "hook error" in why else 0


if __name__ == "__main__":
    sys.exit(main())
