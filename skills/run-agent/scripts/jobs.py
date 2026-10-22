#!/usr/bin/env python3
"""jobs.py: the scheduled-run store under ~/.claude/run-agent/ (RUN_AGENT_HOME overrides).

  write --run-at E --at-text T --cwd D --pane P --session S --socket SOCK --shown CMD --agent A --folder F
        [--until E] -- <claude argv...>      -> writes jobs/<id>.json, prints "<id>\t<path>"
  setpid <id> <pid>                          -> records the runner's pid
  argv <id>                                  -> prints the claude argv NUL-separated
  get <id> <key>                             -> prints one field
  list                                       -> the --jobs listing
  pending                                    -> ids of pending jobs, one per line
  cancel [<id>]                              -> kills the runner, logs cancelled, moves the job to done/
  done <id> <outcome> [note]                 -> logs the outcome, moves the job to done/
  log <id> <outcome> [note]                  -> appends to jobs.log only
"""
import json
import os
import signal
import sys
import time
from datetime import datetime

HOME = os.environ.get("RUN_AGENT_HOME") or os.path.join(os.path.expanduser("~"), ".claude", "run-agent")
JOBS = os.path.join(HOME, "jobs")
DONE = os.path.join(HOME, "done")
LOG = os.path.join(HOME, "jobs.log")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse import fmt_et, fmt_in, now_ts  # noqa: E402


def ensure():
    os.makedirs(JOBS, exist_ok=True)
    os.makedirs(DONE, exist_ok=True)


def path(jid):
    return os.path.join(JOBS, f"{jid}.json")


def load(jid):
    with open(path(jid), encoding="utf-8") as f:
        return json.load(f)


def save(job):
    tmp = path(job["id"]) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(job, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path(job["id"]))


def next_id():
    ids = []
    for d in (JOBS, DONE):
        for n in os.listdir(d):
            if n.endswith(".json") and n[:-5].isdigit():
                ids.append(int(n[:-5]))
    return (max(ids) + 1) if ids else 1


def pending():
    ensure()
    out = []
    for n in sorted(os.listdir(JOBS), key=lambda s: int(s[:-5]) if s[:-5].isdigit() else 0):
        if n.endswith(".json"):
            out.append(int(n[:-5]))
    return out


def alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def log(jid, outcome, note=""):
    ensure()
    stamp = datetime.fromtimestamp(now_ts()).astimezone().strftime("%Y-%m-%d %I:%M %p ET")
    try:
        shown = load(jid).get("shown", "")
    except FileNotFoundError:
        try:
            with open(os.path.join(DONE, f"{jid}.json"), encoding="utf-8") as f:
                shown = json.load(f).get("shown", "")
        except FileNotFoundError:
            shown = ""
    line = f"{stamp}  #{jid}  {outcome}  {shown}"
    if note:
        line += f"  ({note})"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    return line


def finish(jid, outcome, note=""):
    line = log(jid, outcome, note)
    try:
        job = load(jid)
        job["outcome"] = outcome
        job["finished"] = int(now_ts())
        with open(os.path.join(DONE, f"{jid}.json"), "w", encoding="utf-8") as f:
            json.dump(job, f, indent=1, ensure_ascii=False)
        os.remove(path(jid))
    except FileNotFoundError:
        pass
    return line


def kv_args(args):
    opts, rest = {}, []
    i = 0
    while i < len(args):
        if args[i] == "--":
            rest = args[i + 1:]
            break
        if args[i].startswith("--"):
            opts[args[i][2:].replace("-", "_")] = args[i + 1]
            i += 2
        else:
            rest.append(args[i]); i += 1
    return opts, rest


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    args = sys.argv[2:]
    ensure()
    if cmd == "write":
        o, argv = kv_args(args)
        job = {"id": next_id(), "created": int(now_ts()), "run_at": int(o["run_at"]),
               "until": int(o["until"]) if o.get("until") else None, "at_text": o.get("at_text", ""),
               "window": 1 if o.get("window") == "1" else 0,
               "cwd": o.get("cwd", ""), "pane": o.get("pane", ""), "session": o.get("session", ""),
               "socket": o.get("socket", ""), "agent": o.get("agent", ""), "folder": o.get("folder", ""),
               "argv": argv, "shown": o.get("shown", ""), "pid": 0}
        save(job)
        print(f"{job['id']}\t{path(job['id'])}")
    elif cmd == "setpid":
        job = load(int(args[0])); job["pid"] = int(args[1]); save(job)
    elif cmd == "argv":
        sys.stdout.write("\0".join(load(int(args[0]))["argv"]) + "\0")
    elif cmd == "get":
        v = load(int(args[0])).get(args[1], "")
        print("" if v is None else v)
    elif cmd == "pending":
        for j in pending():
            print(j)
    elif cmd == "list":
        ids = pending()
        if not ids:
            print("no scheduled runs"); return
        for jid in ids:
            j = load(jid)
            line = f"#{jid}  {j['shown']}  at {fmt_et(j['run_at'])} ({j['at_text']}, {fmt_in(j['run_at'])})"
            if j.get("until"):
                line += f"  until {fmt_et(j['until'])}"
            if not alive(j.get("pid")):
                line += "  [runner not running]"
            print(line)
    elif cmd == "cancel":
        ids = pending()
        if args:
            jid = int(args[0].lstrip("#"))
            if jid not in ids:
                print(f"no scheduled run #{jid}"); sys.exit(2)
        elif len(ids) == 1:
            jid = ids[0]
        elif not ids:
            print("no scheduled runs"); sys.exit(2)
        else:
            print("several scheduled runs; give an id:")
            for j in ids:
                print(f"  #{j}")
            sys.exit(2)
        job = load(jid)
        pid = job.get("pid") or 0
        if alive(pid):
            try:
                os.killpg(pid, signal.SIGTERM)
            except Exception:  # noqa: BLE001
                try:
                    os.kill(pid, signal.SIGTERM)
                except Exception:  # noqa: BLE001
                    pass
        print(finish(jid, "cancelled"))
    elif cmd == "done":
        print(finish(int(args[0]), args[1], args[2] if len(args) > 2 else ""))
    elif cmd == "log":
        print(log(int(args[0]), args[1], args[2] if len(args) > 2 else ""))
    else:
        print(__doc__); sys.exit(2)


if __name__ == "__main__":
    main()
