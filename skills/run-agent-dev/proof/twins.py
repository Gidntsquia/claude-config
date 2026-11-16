#!/usr/bin/env python3
"""twins.py <replay dir>: write mcp-N.txt next to each cmd-N.txt: the same step with every run-agent.sh call replaced
by the MCP tool call that does it. Format: `BASH:` + the command with the run-agent parts removed (may be empty), then
`TOOLS:` + one `mcp__run-agent__<tool> <json arguments>` line per call, in order. cmd-N.txt is only read."""
import json, os, re, sys

d = sys.argv[1]
S = "~/.claude/skills/run-agent/scripts/run-agent.sh"


def fields(text):
    """Done / In progress / Next out of a handoff printf"""
    m = re.search(r"Done: (.*?)\nIn progress: (.*?)\nNext: (.*)$", text, re.S)
    return [x.strip() for x in m.groups()]


def handoff(cmd):
    pr = cmd[:cmd.index("| " + S)]
    if pr.lstrip().startswith("cd "):
        pr = pr.split("&&", 1)[1]
    args = re.findall(r"""'((?:[^'])*)'|"((?:[^"])*)\"""", pr)
    parts = [a or b for a, b in args]
    if parts[0] == "%s\\n":
        text = "\n".join(parts[1:])
    else:
        text = parts[0].replace("\\n", "\n").strip()
    done, prog, nxt = fields(text)
    fl = cmd[cmd.index("--handoff"):]
    a = {"prompt": ".", "done": done, "in_progress": prog, "next": nxt}
    for k in ("model", "effort"):
        m = re.search(rf"--{k} (\w+)", fl)
        if m:
            a[k] = m.group(1)
    return a


TW = {}
c = {n: open(os.path.join(d, f"cmd-{n}.txt")).read() for n in range(1, 8)}
cut = lambda s, at: s[:s.index(at)].rstrip().rstrip(";").rstrip()
TW[1] = (cut(c[1], S), [("next", {"agent": "planner", "prompt": "Replan based on plans/EVAL.md"})])
TW[2] = ("", [("handoff", handoff(c[2])), ("jobs", {})])
TW[3] = ("cd ~/files/planner-building", [("handoff", handoff(c[3]))])
TW[4] = ("", [("handoff", handoff(c[4]))])
TW[5] = (cut(c[5], S), [("jobs", {}), ("next", {"agent": "evaluator", "prompt": "."})])
TW[6] = (cut(c[6], S), [("next", {"agent": "worker", "prompt": "."})])
TW[7] = (cut(c[7], S), [("next", {"agent": "evaluator", "prompt": "."})])
for n, (bash, tools) in TW.items():
    assert S not in bash, n
    with open(os.path.join(d, f"mcp-{n}.txt"), "w") as f:
        f.write("BASH:\n" + bash + "\nTOOLS:\n" + "".join(f"mcp__run-agent__{t} {json.dumps(a, ensure_ascii=False)}\n" for t, a in tools))
    print(f"mcp-{n}.txt: bash {len(bash)} chars, tools {[t for t, _ in tools]}")
