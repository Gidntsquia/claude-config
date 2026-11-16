#!/usr/bin/env python3
"""matrix.py gen <items dir> <foreign job id>...  |  matrix.py csv <items dir> <results.csv> <out matrix.csv>
The command-shape matrix (plans/research/worker-self-replace.md): 13 ways an agent spells a run-agent call x 5 actions
(next, handoff, jobs, cancel of a job another pane made, schedule). gen writes one item per cell that exists
(cmd-<shape>_<action>.txt, mcp-<shape>_<action>.txt for the MCP shape) for replay.py; a shape that has no such
action (bin/run-agent has no next or handoff; launch.py no handoff; jobs.py only list and cancel) gets no item.
csv reads results.py's rows and writes shape,action,command,blocked,prompted,result: `pass` = the call was made as
written, was neither denied nor asked about, and its output carries the action's marker."""
import csv, json, os, sys, time

S = "~/.claude/skills/run-agent/scripts/run-agent.sh"
ABS = "/home/jaxon/files/claude-config/skills/run-agent/scripts/run-agent.sh"
ACTIONS = ["next", "handoff", "jobs", "cancel", "schedule"]
MARK = {"next": "/run-agent evaluator", "handoff": "Relaunch:", "jobs": ("#", "no scheduled runs"), "cancel": "cancelled",
        "schedule": "scheduled #"}
SHAPES = [("s01", "~ path"), ("s02", "absolute path"), ("s03", '"$HOME" path'), ("s04", "relative after cd"),
          ("s05", "bash wrapper"), ("s06", "run-agent"), ("s07", "python3 launch.py"), ("s08", "python3 jobs.py"),
          ("s09", "cd proj && ..."), ("s10", "...; git status"), ("s11", "... 2>&1 | head -20"),
          ("s12", "heredoc then call"), ("s13", "MCP tool")]
PRINTF = "printf 'Done: matrix cell\\nIn progress: none\\nNext: none\\n' | "


def call(prog, action, jid, at):
    """the run-agent.sh call for an action, prog = how the script is spelled"""
    if action == "next":
        return f'{prog} --next evaluator "."'
    if action == "handoff":
        return f'{PRINTF}{prog} --handoff worker "." -- --model haiku'
    if action == "jobs":
        return f"{prog} --jobs"
    if action == "cancel":
        return f"{prog} --cancel {jid}"
    return f'{prog} worker "." --at {at} -- --model haiku'


def gen(d, ids):
    os.makedirs(d, exist_ok=True)
    ids = list(ids); at = int(time.time()) + 10 * 3600
    jid = lambda: ids.pop(0)
    cells = {}
    for sid, _ in SHAPES:
        for a in ACTIONS:
            j = "J"
            if sid == "s01": c = call(S, a, j, at)
            elif sid == "s02": c = call(ABS, a, j, at)
            elif sid == "s03": c = call('"$HOME/.claude/skills/run-agent/scripts/run-agent.sh"', a, j, at)
            elif sid == "s04": c = "cd ~/.claude/skills/run-agent/scripts && " + call("./run-agent.sh", a, j, at)
            elif sid == "s05": c = call("bash " + S, a, j, at)
            elif sid == "s06":
                c = {"jobs": "run-agent jobs", "cancel": "run-agent cancel J", "schedule": 'run-agent worker "." haiku in 600 min'}.get(a)
            elif sid == "s07":
                L = "python3 ~/.claude/skills/run-agent/scripts/launch.py"
                c = {"next": L + ' next evaluator "."', "jobs": L + " relaunch jobs", "cancel": L + " relaunch 'cancel J'",
                     "schedule": L + " relaunch 'worker \".\" haiku in 600 min'"}.get(a)
            elif sid == "s08":
                J = "python3 ~/.claude/skills/run-agent/scripts/jobs.py"
                c = {"jobs": J + " list", "cancel": J + " cancel J"}.get(a)
            elif sid == "s09": c = "cd ~/files/planner-building && " + call(S, a, j, at)
            elif sid == "s10": c = call(S, a, j, at) + "; git status --short | head -5"
            elif sid == "s11": c = call(S, a, j, at) + " 2>&1 | head -20"
            elif sid == "s12": c = "cat > plans/matrix-note.txt <<'EOF'\nmatrix cell: a note written before the call\nEOF\n" + call(S, a, j, at)
            else:
                t = {"next": ("next", {"agent": "evaluator", "prompt": "."}),
                     "handoff": ("handoff", {"prompt": ".", "done": "matrix cell", "in_progress": "none", "next": "none", "model": "haiku"}),
                     "jobs": ("jobs", {}), "cancel": ("cancel", {"id": "J"}),
                     "schedule": ("schedule", {"agent": "worker", "prompt": ".", "model": "haiku", "at": "in 600 min"})}[a]
                c = t
            if c is None:
                continue
            if a == "cancel":
                n = jid()
                c = (c[0], {"id": int(n)}) if sid == "s13" else c.replace("J", n)
            cells[(sid, a)] = c
    for (sid, a), c in cells.items():
        if sid == "s13":
            open(os.path.join(d, f"mcp-{sid}_{a}.txt"), "w").write("BASH:\n\nTOOLS:\n" + f"mcp__run-agent__{c[0]} {json.dumps(c[1])}\n")
        else:
            open(os.path.join(d, f"cmd-{sid}_{a}.txt"), "w").write(c)
    print(len(cells), "cells;", sum(1 for k in cells if k[1] == "cancel"), "cancel cells")


def tocsv(d, results, out):
    rows = {r["n"]: r for r in csv.DictReader(open(results))}
    names = dict(SHAPES); bad = 0
    with open(out, "w", newline="") as f:
        w = csv.writer(f); w.writerow(["shape", "action", "command", "session", "blocked", "prompted", "result", "output_tail"])
        for sid, name in SHAPES:
            for a in ACTIONS:
                key = f"{sid}_{a}"
                p = [x for x in (os.path.join(d, f"cmd-{key}.txt"), os.path.join(d, f"mcp-{key}.txt")) if os.path.exists(x)]
                if not p:
                    continue
                cmd = open(p[0]).read().replace("BASH:\n\nTOOLS:\n", "").strip()
                r = rows.get(key)
                if r is None:
                    res, r = "not run", {"session": "", "blocked": "", "prompted": "", "result": ""}
                else:
                    m = MARK[a]; m = m if isinstance(m, tuple) else (m,)
                    ok = r["exact"] == "yes" and r["blocked"] == "no" and r["prompted"] == "no" and any(x in r["result"] for x in m)
                    res = "pass" if ok else ("blocked" if r["blocked"] == "yes" else "prompted" if r["prompted"] == "yes" else "fail")
                bad += res != "pass"
                w.writerow([name, a, cmd, r["session"], r["blocked"], r["prompted"], res, r["result"][-120:]])
    print("cells not pass:", bad)


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2], sys.argv[3:])
    else:
        tocsv(*sys.argv[2:5])
