"""Write one transcript: mksession.py <projects-dir> <session-id> <cwd> "<local time>" [key=value ...]
keys: agent mode model name entry (sdk-cli = headless) first (slash command) replies (0 or 1)
      end (text | tool_use | tool_result | thinking | api_error | exit | resumed)"""
import json, os, sys, time
root, sid, cwd, when = sys.argv[1:5]
o = dict(agent="worker", mode="auto", model="claude-sonnet-5-5", name="", entry="cli", first="", replies="1", end="text")
o.update(a.split("=", 1) for a in sys.argv[5:])
def msg(kind, content, **extra):
    return dict(type=kind, cwd=cwd, entrypoint=o["entry"], message=dict(content=content, **extra))
def reply(part):
    return msg("assistant", [{"type": part}], model=o["model"])
def command(c):
    return msg("user", "<command-name>%s</command-name>" % c)
rows = [{"type": "agent-setting", "agentSetting": o["agent"]},
        {"type": "permission-mode", "permissionMode": o["mode"]}]
if o["name"]:
    rows.append({"type": "agent-name", "agentName": o["name"]})
rows.append(command(o["first"]) if o["first"] else msg("user", "please do the thing"))
if o["replies"] != "0":
    rows.append(reply("text"))
    end = o["end"]
    if end in ("tool_use", "thinking"):
        rows.append(reply(end))
    elif end == "tool_result":
        rows += [reply("tool_use"), msg("user", [{"type": "tool_result"}])]
    elif end == "api_error":
        rows.append({"type": "system", "subtype": "api_error", "cwd": cwd})
    elif end in ("exit", "resumed"):
        rows.append(command("/exit"))
        if end == "resumed":
            rows.append(reply("text"))
folder = os.path.join(root, cwd.replace("/", "-"))
os.makedirs(folder, exist_ok=True)
path = os.path.join(folder, sid + ".jsonl")
with open(path, "w") as f:
    for r in rows:
        f.write(json.dumps(r, separators=(",", ":")) + "\n")
t = time.mktime(time.strptime(when, "%Y-%m-%d %H:%M:%S"))
os.utime(path, (t, t))
