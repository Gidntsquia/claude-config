#!/usr/bin/env python3
"""jobs.py: the scheduled-run store under ~/.claude/run-agent/ (RUN_AGENT_HOME overrides).

  write --run-at E --at-text T --cwd D [--target split|window] --pane P --session S --socket SOCK --shown CMD --agent A --folder F
        [--until E] [--server-pid N] -- <claude argv...>      -> writes jobs/<id>.json, prints "<id>\t<path>"
  setpid <id> <pid>                          -> records the runner's pid
  argv <id>                                  -> prints the claude argv NUL-separated
  get <id> <key>                             -> prints one field
  list                                       -> the --jobs listing (id, command, time, runner state)
  pending                                    -> ids of pending jobs, one per line
  state <id>                                 -> runner state: sleeping (pid N) | dead | errored: <last logs/<id>.log line>
                                                | waiting: no pane (an agent's job whose pane was gone at fire time)
  health                                     -> one line per pending job; exit 1 when any runner is dead or errored
  waiting [<socket>]                         -> ids of waiting jobs (on that tmux server)
  stale                                      -> "<id>\tfuture|overdue" for pending jobs whose runner is gone (not waiting)
  set <id> <key> <value>                     -> sets one string field ("" clears it)
  cancel [<id>]                              -> kills the runner, logs cancelled, moves the job to done/
  done <id> <outcome> [note]                 -> logs the outcome, moves the job to done/
  log <id> <outcome> [note]                  -> appends to jobs.log only
  failures [--mark]                          -> one line per job that failed or was skipped since the last --mark
  clean                                      -> deletes done/*.json and logs/* older than 30 days
  size                                       -> "state dir N MB, trim with run-agent clean" when the dir is over 50 MB

write also records how to start claude at fire time: --claude-bin (absolute path), --path, --home, --shell (the env
keys, stored under "env"), and --model-default <model> when the argv carries no --model (the list then shows
"(<model>, default)"). Jobs written without these fields (older versions) are run as before: `claude` from the
runner's own PATH, no default-model note.
"""
import json
import os
import signal
import sys
import time
from datetime import datetime

HOME = os.environ.get("RUN_AGENT_HOME") or os.path.join(os.path.expanduser("~"), ".claude", "run-agent")
# test mode (RUN_AGENT_TEST=1, exported by test.sh): only a scratch store, RUN_AGENT_HOME set and outside ~/.claude
if os.environ.get("RUN_AGENT_TEST") == "1" and (not os.environ.get("RUN_AGENT_HOME") or (
        os.path.realpath(HOME) + os.sep).startswith(os.path.realpath(os.path.expanduser("~/.claude")) + os.sep)):
    print("test mode: refusing the real job store", file=sys.stderr)
    sys.exit(2)
JOBS = os.path.join(HOME, "jobs")
DONE = os.path.join(HOME, "done")
LOG = os.path.join(HOME, "jobs.log")
LOGS = os.path.join(HOME, "logs")  # logs/<id>.log: that job's runner output (empty unless it errored)
SEEN = os.path.join(HOME, "failures-seen")  # epoch: failures finished before it were already shown to a human
KEEP_DAYS = 30
BIG_MB = 50

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse import fmt_et, fmt_in, now_ts  # noqa: E402


def ensure():
    os.makedirs(JOBS, exist_ok=True)
    os.makedirs(DONE, exist_ok=True)
    os.makedirs(LOGS, exist_ok=True)


def state(job):
    """the runner's state as the listing shows it"""
    if str(job.get("waiting", "")) == "1":
        return "waiting: no pane"
    pid = job.get("pid")
    if alive(pid):
        return f"sleeping (pid {pid})"
    try:
        with open(os.path.join(LOGS, f"{job['id']}.log"), encoding="utf-8", errors="replace") as f:
            lines = [x.rstrip("\n") for x in f if x.strip()]
    except OSError:
        lines = []
    return f"errored: {lines[-1]}" if lines else "dead"


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
    """True when pid is a live runner.sh. After a reboot or WSL restart the pid can belong to something else,
    so on Linux the command line must name runner.sh."""
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return b"runner.sh" in f.read()
    except FileNotFoundError:
        return not os.path.isdir("/proc")
    except OSError:
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
        job["note"] = note
        job["finished"] = int(now_ts())
        with open(os.path.join(DONE, f"{jid}.json"), "w", encoding="utf-8") as f:
            json.dump(job, f, indent=1, ensure_ascii=False)
        os.remove(path(jid))
    except FileNotFoundError:
        pass
    for ext in (".log", ".exit"):
        try:
            os.remove(os.path.join(LOGS, f"{jid}{ext}"))
        except OSError:
            pass
    return line


def model_note(job):
    """' (sonnet, default)' for a job whose claude command carries no --model, else ''"""
    d = job.get("model_default", "")
    return f"  ({d}, default)" if d else ""


def failures(mark=False):
    """done jobs that failed or were skipped after the last mark, oldest first"""
    try:
        with open(SEEN, encoding="utf-8") as f:
            seen = int(f.read().strip() or 0)
    except (OSError, ValueError):
        seen = 0
    out = []
    for n in os.listdir(DONE):
        if not n.endswith(".json"):
            continue
        try:
            with open(os.path.join(DONE, n), encoding="utf-8") as f:
                j = json.load(f)
        except (OSError, ValueError):
            continue
        oc = str(j.get("outcome", ""))
        fin = int(j.get("finished") or 0)
        if fin > seen and oc.startswith(("failed", "skipped")):
            stamp = datetime.fromtimestamp(fin).astimezone().strftime("%Y-%m-%d %I:%M %p ET")
            line = f"{stamp}  #{j.get('id', n[:-5])}  {oc}"
            if j.get("note"):
                line += f" ({j['note']})"
            out.append((fin, line + f"  {j.get('shown', '')}"))
    if mark and out:
        with open(SEEN, "w", encoding="utf-8") as f:
            f.write(f"{max(fin for fin, _ in out)}\n")
    return [line for _, line in sorted(out)]


def dir_mb():
    total = 0
    for root, _dirs, files in os.walk(HOME):
        for n in files:
            try:
                total += os.path.getsize(os.path.join(root, n))
            except OSError:
                pass
    return total / (1024 * 1024)


def size_line():
    mb = dir_mb()
    return f"state dir {mb:.0f} MB, trim with run-agent clean" if mb > BIG_MB else ""


def clean():
    cutoff = now_ts() - KEEP_DAYS * 86400
    gone = 0
    for d in (DONE, LOGS):
        for n in os.listdir(d):
            p = os.path.join(d, n)
            try:
                if os.path.isfile(p) and os.path.getmtime(p) < cutoff:
                    os.remove(p); gone += 1
            except OSError:
                pass
    return gone


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
               "socket": o.get("socket", ""), "server_pid": o.get("server_pid", ""),
               "agent": o.get("agent", ""), "folder": o.get("folder", ""), "target": o.get("target", ""),
               "from_agent": 1 if o.get("from_agent") == "1" else 0,
               "argv": argv, "shown": o.get("shown", ""), "pid": 0,
               "claude_bin": o.get("claude_bin", ""),
               "env": {"PATH": o.get("path", ""), "HOME": o.get("home", ""), "SHELL": o.get("shell", "")},
               "model_default": o.get("model_default", "")}
        save(job)
        print(f"{job['id']}\t{path(job['id'])}")
    elif cmd == "setpid":
        job = load(int(args[0])); job["pid"] = int(args[1]); save(job)
    elif cmd == "argv":
        sys.stdout.write("\0".join(load(int(args[0]))["argv"]) + "\0")
    elif cmd == "get":
        v = load(int(args[0]))
        for k in args[1].split("."):  # env.PATH
            v = v.get(k, "") if isinstance(v, dict) else ""
        print("" if v is None or isinstance(v, (dict, list)) else v)
    elif cmd == "pending":
        for j in pending():
            print(j)
    elif cmd == "stale":
        for jid in pending():
            j = load(jid)
            if str(j.get("waiting", "")) != "1" and not alive(j.get("pid")):
                print(f"{jid}\t{'future' if j['run_at'] > now_ts() else 'overdue'}")
    elif cmd == "state":
        print(state(load(int(args[0]))))
    elif cmd == "waiting":
        for jid in pending():
            j = load(jid)
            if str(j.get("waiting", "")) == "1" and (not args or j.get("socket", "") == args[0]):
                print(jid)
    elif cmd == "health":
        bad = 0
        for jid in pending():
            j = load(jid)
            s = state(j)
            ok = s.startswith(("sleeping", "waiting"))
            bad += not ok
            print(f"{'ok' if ok else 'FAIL'}  #{jid}  {s}  {j['shown']}  at {fmt_et(j['run_at'])}")
        sys.exit(1 if bad else 0)
    elif cmd == "set":
        job = load(int(args[0])); job[args[1]] = args[2]; save(job)
    elif cmd == "list":
        # failures since the last human look come first; a human call (RUN_AGENT_HUMAN or a tty) marks them seen
        human = bool(os.environ.get("RUN_AGENT_HUMAN")) or sys.stdout.isatty()
        for line in failures(mark=human):
            print(line)
        ids = pending()
        if not ids:
            print("no scheduled runs")
        for jid in ids:
            j = load(jid)
            line = f"#{jid}  {j['shown']}{model_note(j)}  at {fmt_et(j['run_at'])} ({j['at_text']}, {fmt_in(j['run_at'])})"
            if j.get("until"):
                line += f"  until {fmt_et(j['until'])}"
            print(line + f"  [{state(j)}]")
        big = size_line()
        if big:
            print(big)
    elif cmd == "failures":
        for line in failures(mark="--mark" in args):
            print(line)
    elif cmd == "clean":
        print(f"removed {clean()} file(s) older than {KEEP_DAYS} days from {DONE} and {LOGS}")
    elif cmd == "size":
        big = size_line()
        if big:
            print(big)
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
        try:
            os.remove(os.path.join(LOGS, f"{jid}.log"))
        except OSError:
            pass
    elif cmd == "done":
        print(finish(int(args[0]), args[1], args[2] if len(args) > 2 else ""))
    elif cmd == "log":
        print(log(int(args[0]), args[1], args[2] if len(args) > 2 else ""))
    else:
        print(__doc__); sys.exit(2)


if __name__ == "__main__":
    main()
