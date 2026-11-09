#!/usr/bin/env python3
"""drive.py <scene>: runs one replay scene (tests/agent-replay/scenes/<scene>.py) against `claude -p --agent assistant`
on the fake tmux that tests/fake-env.sh exported. A scene module defines TURNS (list of {"user": str, "offset": minutes})
and check(ctx) -> list of failure strings, plus an optional setup(ctx). Prints one PASS/FAIL line.
ctx: replies[i] (reply text), calls[i] (list of {"tool","input","result"}), asked[i] (AskUserQuestion used), tm(),
capture(pid), panes(), two_by_two(), sends() (every `GOT:`/answered line in every fake claude pane), env, out dir.
Every scene also gets _lib.every_fact_once on each reply (plan R4)."""
import importlib.util, json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SOCK = os.environ["ASSISTANT_TEST_SOCKET"]
OUT = os.environ["REPLAY_OUT"]
CLAUDE = os.environ["REAL_CLAUDE"]
TMX = ["tmux", "-L", SOCK]
FILES = os.environ["ASSISTANT_FILES"]


def tm(*a):
    return subprocess.run(TMX + list(a), capture_output=True, text=True).stdout


def capture(pid, n=80):
    return tm("capture-pane", "-p", "-J", "-t", pid, "-S", f"-{n}")


def panes():
    rows = []
    for ln in tm("list-panes", "-a", "-F", "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}\t#{@name}\t#{pane_current_command}\t#{pane_current_path}").split("\n"):
        if ln:
            s, w, i, pid, name, cmd, cwd = ln.split("\t")
            rows.append({"session": s, "window": int(w), "index": int(i), "id": pid, "name": name, "cmd": cmd, "cwd": cwd,
                         "pet": "[f] feed" in capture(pid, 5)})
    return rows


def windows():
    out = {}
    for p in panes():
        out.setdefault((p["session"], p["window"]), []).append(p)
    return out


def two_by_two():
    """every window holding a pet has the pet and three more panes; no window holds only a pet; no 5th pane"""
    bad = []
    for (s, w), ps in windows().items():
        pets = [p for p in ps if p["pet"]]
        if pets and len(ps) != 4:
            bad.append(f"{s}:{w} has a pet and {len(ps)} panes")
        if len(ps) > 4:
            bad.append(f"{s}:{w} has {len(ps)} panes")
    return bad


def sends():
    """{pane_id: [lines]} of what reached fake claude panes: GOT: <text> echoes and `→ <answer>` menu results"""
    out = {}
    for p in panes():
        got = [l for l in capture(p["id"]).split("\n") if l.startswith("GOT: ") or "? → " in l]
        if got:
            out[p["id"]] = got
    return out


def by_name(name, session="t"):
    for p in panes():
        if p["name"] == name and p["session"] == session:
            return p
    return None


def run_turn(user, offset=0, resume=None, timeout=600):
    env = dict(os.environ)
    env["ASSISTANT_CLOCK_OFFSET_MIN"] = str(offset) if offset else ""
    cmd = [CLAUDE, "-p", "--agent", "assistant", "--output-format", "stream-json", "--verbose"]
    if resume:
        cmd += ["--resume", resume]
    cmd.append(user)
    t0 = time.time()
    r = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)
    texts, calls, asked, sid, pending, pre = [], [], False, None, {}, None   # pre: text written before the first action call
    for l in r.stdout.split("\n"):
        try:
            d = json.loads(l)
        except Exception:
            continue
        if d.get("type") == "assistant":
            for c in d["message"]["content"]:
                if c["type"] == "tool_use":
                    if pre is None and re.search(r"assistant_(send|layout|launch|schedule)$", c["name"]):
                        pre = "\n\n".join(texts)
                    pending[c["id"]] = {"tool": c["name"], "input": c["input"], "result": ""}
                    calls.append(pending[c["id"]])
                    if c["name"] == "AskUserQuestion":
                        asked = True
                elif c["type"] == "text":
                    texts.append(c["text"])
        elif d.get("type") == "user":
            for c in d["message"].get("content", []) if isinstance(d["message"].get("content"), list) else []:
                if isinstance(c, dict) and c.get("type") == "tool_result" and c.get("tool_use_id") in pending:
                    s = c["content"] if isinstance(c["content"], str) else json.dumps(c["content"])
                    pending[c["tool_use_id"]]["result"] = s
        elif d.get("type") == "result":
            sid = d.get("session_id")
    reply = "\n\n".join(texts)
    return {"reply": reply, "pre_action": pre or "", "calls": calls, "asked": asked, "session_id": sid, "rc": r.returncode, "stderr": r.stderr[-2000:],
            "seconds": round(time.time() - t0)}


class Ctx:
    pass


def main():
    name = sys.argv[1]
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, "scenes", name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.join(HERE, "scenes"))
    spec.loader.exec_module(mod)
    ctx = Ctx()
    ctx.tm, ctx.capture, ctx.panes, ctx.windows, ctx.two_by_two, ctx.sends, ctx.by_name = tm, capture, panes, windows, two_by_two, sends, by_name
    ctx.env, ctx.out, ctx.files, ctx.replies, ctx.calls, ctx.asked, ctx.turns = dict(os.environ), OUT, FILES, [], [], [], []
    ctx.self_pane = os.environ["TMUX_PANE"]
    if hasattr(mod, "setup"):
        mod.setup(ctx)
        time.sleep(1.0)
    with open(os.path.join(OUT, "before.txt"), "w") as f:
        f.write(tm("list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{@name} #{pane_current_command}"))
    sid = None
    for i, t in enumerate(mod.TURNS):
        res = run_turn(t["user"], t.get("offset", 0), resume=sid)
        sid = res["session_id"] or sid
        ctx.replies.append(res["reply"]); ctx.calls.append(res["calls"]); ctx.asked.append(res["asked"]); ctx.turns.append(res)
        with open(os.path.join(OUT, f"turn{i + 1}.md"), "w") as f:
            f.write(f"# user\n{t['user']}\n\n# reply ({res['seconds']} s, rc {res['rc']})\n{res['reply']}\n\n# tool calls\n")
            for c in res["calls"]:
                f.write(f"- {c['tool']} {json.dumps(c['input'])[:400]}\n  → {c['result'][:400]}\n")
            if res["stderr"]:
                f.write("\n# stderr\n" + res["stderr"])
        time.sleep(1.5)
    with open(os.path.join(OUT, "after.txt"), "w") as f:
        f.write(tm("list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{@name} #{pane_current_command}"))
        for p in panes():
            f.write(f"\n--- {p['id']} {p['name']}\n{capture(p['id'], 20)}")
    try:
        fails = mod.check(ctx)
    except Exception as e:   # a check that crashes is a failure with the traceback's last line
        fails = [f"check raised {type(e).__name__}: {e}"]
    from _lib import every_fact_once     # plan R4, over every scene: each fact once outside the table, no bold
    for i, res in enumerate(ctx.turns):
        fails += every_fact_once(res["reply"], f"turn {i + 1}")
    for i, res in enumerate(ctx.turns):
        if res["rc"] != 0 and not res["reply"]:
            fails.insert(0, f"turn {i + 1}: claude exited {res['rc']} with no reply: {res['stderr'][-200:]}")
    with open(os.path.join(OUT, "result.txt"), "w") as f:
        f.write("PASS\n" if not fails else "FAIL\n" + "\n".join(fails) + "\n")
    print(f"PASS {name}" if not fails else f"FAIL {name}: " + " | ".join(fails)[:600])


main()
