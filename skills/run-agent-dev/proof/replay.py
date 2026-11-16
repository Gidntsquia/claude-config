#!/usr/bin/env python3
"""replay.py <replay dir> <out dir> <label> <agent> <item>...   (item = cmd-N | mcp-N | a file path with one command)
One headless haiku session (`claude -p --agent <agent> --permission-mode auto`) is told to make each item's calls
exactly as recorded; its stream-json goes to <out dir>/<label>.jsonl and the item list to <label>.items. Afterwards
every job the session left in the (scratch) store is cancelled. Run only inside `tmux -L run-agent-dev-test` (asserted below):
a replayed call may replace the pane it runs in. results.py turns the streams into results.csv."""
import json, os, re, subprocess, sys

rdir, out, label, agent, items = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
HERE = os.path.dirname(os.path.realpath(__file__))
S = os.path.join(os.path.dirname(HERE), "scripts", "run-agent.sh")
assert (os.environ.get("TMUX") or "").split(",")[0].endswith("/run-agent-dev-test"), "run replay.py inside tmux -L run-agent-dev-test"
os.makedirs(out, exist_ok=True)
steps = []
for k, it in enumerate(items, 1):
    path = it if os.path.exists(it) else os.path.join(rdir, it + ".txt")
    text = open(path).read()
    if os.path.basename(path).startswith("mcp-"):
        bash, tools = text.split("\nTOOLS:\n")
        bash = bash[len("BASH:\n"):]
        s = f"Step {k}:"
        if bash.strip():
            s += f" first make ONE Bash tool call whose command is exactly the text between the markers (do not include the marker lines):\n<<<COMMAND\n{bash}\nCOMMAND>>>\nThen"
        for line in tools.strip().split("\n"):
            name, args = line.split(" ", 1)
            s += f" call the tool `{name}` with exactly these arguments: {args}\n"
        steps.append(s)
    else:
        steps.append(f"Step {k}: make ONE Bash tool call whose command is exactly the text between the markers, character for "
                     f"character, all of it in the one call (do not include the marker lines):\n<<<COMMAND\n{text}\nCOMMAND>>>\n")
prompt = ("This is a replay of recorded steps for a permission test in a scratch copy of this project. Do not read the "
          "plan or any other file first. Do the steps below in order, each exactly once. Never change a command or an "
          "argument, never add a description-driven rewrite, never split or merge calls, never retry. If a call is "
          "denied or fails, go straight on to the next step. "
          f"There are {len(steps)} steps. Later steps may look like earlier ones (the same handoff once as a Bash "
          "command and once as an MCP tool call): they are separate steps and every one must be made. After step "
          f"{len(steps)} reply with the single word done.\n\n" + "\n".join(steps))
open(os.path.join(out, label + ".items"), "w").write("\n".join(items) + "\n")
with open(os.path.join(out, label + ".jsonl"), "w") as f:
    r = subprocess.run(["claude", "-p", "--agent", agent, "--model", "haiku", "--permission-mode", "auto",
                        "--max-budget-usd", "2.00", "--max-turns", str(8 + 4 * len(items)),
                        "--output-format", "stream-json", "--verbose", prompt], stdout=f, stderr=subprocess.STDOUT,
                       stdin=subprocess.DEVNULL)
print(label, "claude exit", r.returncode)
jobs = subprocess.run([S, "--jobs"], capture_output=True, text=True).stdout
keep = set((os.environ.get("REPLAY_KEEP") or "").split())  # job ids a later session still needs (matrix cancel cells)
for n in re.findall(r"^#(\d+)", jobs, re.M):
    if n in keep:
        continue
    print(subprocess.run([S, "--cancel", n], capture_output=True, text=True).stdout.strip())
