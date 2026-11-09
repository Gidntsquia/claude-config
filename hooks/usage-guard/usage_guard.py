#!/usr/bin/env python3
"""usage-guard: a hard stop on the worker agent's expensive launches. Standard library only, no network, no model.

Hook mode (stdin = Claude Code hook JSON), registered in settings.json:
  PreToolUse Bash|Monitor   blocks > 2 parallel headless `claude` runs, a headless launch without --max-budget-usd /
                            --max-turns, the 31st launch of the day in a project, and any command touching guard state
  PreToolUse Agent          blocks a 4th running subagent, a task already dispatched today, the 31st launch of the
                            day; rewrites subagent_type to `helper` and drops an expensive `model`
  PreToolUse Edit|Write|NotebookEdit   blocks edits of guard state, the hook, settings.json and worker.md
  SubagentStart / SubagentStop         keep <project>/live/<agent_id>
It acts only in a session started as `claude --agent worker` (hook input agent_type == "worker") and in that
session's subagents; every other session exits 0 with no output. A block is exit 2 with one line on stderr.

CLI mode: `usage_guard.py cli ...` (installed as `guard`): allow / revoke / status / log / usage.
Test-only arguments (the settings.json command passes none): --now <epoch>, --live <n>.
State: ~/.cache/claude-guard/{log, sessions/, <project>/{<date>.count, <date>.dispatched, allow, live/}}.
"""
import json
import os
import re
import sys
import time

HOME = os.path.expanduser("~")
G = os.path.join(HOME, ".cache", "claude-guard")
HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MAX_HEADLESS, MAX_SUBAGENTS, DAILY = 2, 3, 30
SUGGEST = "--max-budget-usd 0.50 --max-turns 15"
CHEAP_MODELS = ("sonnet", "haiku")
STALE_LIVE, STALE_PENDING = 2 * 3600, 90
TAMPER = re.compile(r"\.cache/claude-guard|claude-guard/|\bguard\s+(allow|revoke)\b|usage_guard\.py|usage-guard/guard\b")
R6 = "blocked by usage-guard: guard state is edited by the user only"
NOW = None
LIVE = None


def now():
    return NOW if NOW is not None else time.time()


def et(ts=None):
    from datetime import datetime
    from zoneinfo import ZoneInfo
    return datetime.fromtimestamp(now() if ts is None else ts, ZoneInfo("America/New_York"))


def today():
    return et().strftime("%Y-%m-%d")


def clock(ts=None):
    return et(ts).strftime("%-I:%M %p")


def project_root(cwd):
    """the git root above cwd (so `cd tests` does not open a second pool), else cwd"""
    d = os.path.abspath(cwd or os.getcwd())
    p = d
    while p not in ("/", HOME) and os.path.dirname(p) != p:
        if os.path.exists(os.path.join(p, ".git")):
            return p
        p = os.path.dirname(p)
    return d


def slug_of(cwd):
    return os.path.basename(project_root(cwd)) or "root"


def pdir(slug):
    d = os.path.join(G, slug)
    os.makedirs(os.path.join(d, "live"), exist_ok=True)
    return d


class Lock:
    def __init__(self, slug):
        self.path = os.path.join(pdir(slug), ".lock")

    def __enter__(self):
        import fcntl
        self.f = open(self.path, "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)

    def __exit__(self, *a):
        self.f.close()


def read_count(slug, day=None):
    try:
        return int(open(os.path.join(pdir(slug), f"{day or today()}.count")).read().strip() or 0)
    except (OSError, ValueError):
        return 0


def add_count(slug, n):
    c = read_count(slug) + n
    with open(os.path.join(pdir(slug), f"{today()}.count"), "w") as f:
        f.write(f"{c}\n")
    return c


def allow_until(slug):
    """epoch the unlock runs to, or None"""
    try:
        exp = float(open(os.path.join(pdir(slug), "allow")).read().split()[0])
    except (OSError, ValueError, IndexError):
        return None
    return exp if exp > now() else None


def log(slug, verdict, count, what, reason):
    os.makedirs(G, exist_ok=True)
    what = " ".join((what or "").split())[:120]
    line = f"{et().strftime('%Y-%m-%d %I:%M:%S %p ET')} | {slug} | {verdict} | {count}/{DAILY} | {what} | {reason}\n"
    with open(os.path.join(G, "log"), "a") as f:
        f.write(line)


def block(slug, what, reason, count=None):
    log(slug, "BLOCK", read_count(slug) if count is None else count, what, reason)
    sys.stderr.write(reason + "\n")
    sys.exit(2)


# ---- processes ----------------------------------------------------------------------------------------------------
def live_headless():
    """running `claude -p/--print` processes, not counting this hook's own ancestors"""
    if LIVE is not None:
        return LIVE
    mine, n = set(), 0
    if os.path.isdir("/proc/self"):
        p = os.getpid()
        while p > 1:
            mine.add(p)
            try:
                p = int(open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split()[1])
            except (OSError, ValueError, IndexError):
                break
        rows = []
        for d in os.listdir("/proc"):
            if d.isdigit():
                try:
                    rows.append((int(d), open(f"/proc/{d}/cmdline", "rb").read().decode("utf-8", "replace").split("\0")))
                except OSError:
                    pass
    else:
        import subprocess
        out = subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True).stdout
        table = {}
        rows = []
        for line in out.splitlines():
            parts = line.split(None, 2)
            if len(parts) == 3 and parts[0].isdigit():
                table[int(parts[0])] = int(parts[1])
                rows.append((int(parts[0]), parts[2].split()))
        p = os.getpid()
        while p > 1 and p in table:
            mine.add(p)
            p = table[p]
    for pid, argv in rows:
        if pid in mine or not argv:
            continue
        k = 0 if os.path.basename(argv[0]) == "claude" else (1 if len(argv) > 1 and os.path.basename(argv[1]) == "claude" and os.path.basename(argv[0]) in ("node", "bun") else None)
        if k is not None and any(a in ("-p", "--print") for a in argv[k + 1:]):
            n += 1
    return n


# ---- protected files ----------------------------------------------------------------------------------------------
def _real(p):
    return os.path.realpath(os.path.expanduser(p))


def protected(path):
    """a file the worker may not change: guard state, the hook, settings, its own agent file"""
    rp = _real(path)
    for root in (_real(G), HERE, _real("~/.claude/hooks")):
        if rp == root or rp.startswith(root + os.sep):
            return True
    exact = {_real("~/.claude/settings.json"), _real("~/.claude/settings.local.json"), os.path.join(REPO, "settings.json"),
             _real("~/.claude/agents/worker.md"), os.path.join(REPO, "agents", "worker.md"), _real("~/.local/bin/guard"),
             os.path.join(HOME, ".local", "bin", "guard")}
    if rp in exact:
        return True
    b, parent = os.path.basename(rp), os.path.basename(os.path.dirname(rp))
    return b in ("settings.json", "settings.local.json") and parent == ".claude"


def holds_protected(path):
    """a directory that contains protected files (rm -rf ~/.claude)"""
    rp = _real(path)
    return any(r.startswith(rp + os.sep) for r in (_real(G), HERE, _real("~/.claude/settings.json")))


WRITERS = {"rm", "tee", "dd", "truncate", "chmod", "chown", "touch", "patch", "unlink", "shred", "sponge", "ed", "ex",
           "vi", "vim", "nano", "rmdir", "perl", "ruby", "tar", "unzip"}
DEST_WRITERS = {"cp", "ln", "install", "rsync", "mv"}
INTERP = re.compile(r"^(python[\d.]*|node|bun|deno|bash|sh|zsh)$")
GIT_WRITE = {"checkout", "restore", "reset", "apply", "stash", "rm", "mv", "clean", "update-index", "revert", "am"}
SKIP = {"do", "then", "else", "elif", "if", "!", "while", "until", "nohup", "time", "nice", "setsid", "command", "exec",
        "sudo", "env", "builtin"}


def tamper(result, cwd):
    """True when a simple command of the analyzed text writes to a protected file"""
    for c in result.cmds:
        words = [w.text for w in c.words]
        i = 0
        while i < len(words) and (re.fullmatch(r"\w+=.*", words[i], re.S) or words[i] in SKIP):
            i += 1
        base = os.path.basename(words[i]) if i < len(words) else ""
        args = words[i + 1:]

        def path_of(a):
            a = a.replace("$HOME", HOME).replace("${HOME}", HOME)
            if "=" in a and not a.startswith(("/", "~", ".")):
                a = a.split("=", 1)[1]
            if not a or "$" in a or "\n" in a or len(a) > 400:
                return None
            a = os.path.expanduser(a)
            return a if os.path.isabs(a) else os.path.join(result.cwd if result.cwd else cwd, a)

        for op, t in c.redirs:
            p = path_of(t.text)
            if p and op in (">", ">>", ">|", "&>", "<>") and protected(p):
                return True
        paths = [(k, path_of(a)) for k, a in enumerate(args)]
        hits = [(k, p) for k, p in paths if p and protected(p)]
        if base in ("rm", "mv", "rmdir") and any(p and holds_protected(p) for _, p in paths):
            return True
        if not hits:
            continue
        if base in WRITERS:
            return True
        if base in DEST_WRITERS and (base == "mv" or any(k == len(args) - 1 for k, _ in hits)):
            return True
        if base == "sed" and any(a == "--in-place" or re.fullmatch(r"-[a-zA-Z]*i.*", a) for a in args):
            return True
        if base == "git" and any(a in GIT_WRITE for a in args[:3]):
            return True
        if INTERP.match(base):
            files = [k for k, a in enumerate(args) if not a.startswith("-")]
            if any(k != (files[0] if files else -1) for k, _ in hits):
                return True
    return False


# ---- hooks --------------------------------------------------------------------------------------------------------
def bash_hook(data):
    ti = data.get("tool_input") or {}
    cmd = ti.get("command") or ""
    cwd = data.get("cwd") or os.getcwd()
    slug = slug_of(cwd)
    if TAMPER.search(cmd):
        block(slug, cmd, R6)
    sys.path.insert(0, HERE)
    import shellscan
    r = shellscan.analyze(cmd, cwd)
    if tamper(r, cwd) or any(TAMPER.search(t) for p, t in r.script_texts if not _real(p).startswith(HERE + os.sep)):
        block(slug, cmd, R6)
    if not r.launches:
        return 0
    with Lock(slug):
        unlocked = allow_until(slug)
        count = read_count(slug)
        live = live_headless()
        total = r.conc + live
        if total > MAX_HEADLESS and not unlocked:
            extra = f" ({live} already running)" if live else ""
            block(slug, cmd, f"blocked by usage-guard: {total} parallel headless claude runs (max {MAX_HEADLESS}){extra}. "
                             "Run -j 2 or one scene; ask the user to run `guard allow` for a full suite.", count)
        if count + r.total > DAILY and not unlocked:
            left = max(DAILY - count, 0)
            block(slug, cmd, f"blocked by usage-guard: {count}/{DAILY} headless launches used today for {slug}; this adds "
                             f"{r.total}. Run at most {left} more today (single scenes), or ask the user to run "
                             "`guard allow`.", count)
        if r.missing:
            miss = " and ".join(r.missing)
            if r.in_script:
                where = os.path.relpath(r.in_script, project_root(cwd)) if r.in_script.startswith(project_root(cwd)) else r.in_script
                block(slug, cmd, f"blocked by usage-guard: the headless claude launch in {where} lacks {miss}. Run it with "
                                 f"CLAUDE_GUARD_FLAGS=\"{SUGGEST}\" if the script passes that variable to claude, or edit "
                                 f"the script to pass {SUGGEST}.", count)
            block(slug, cmd, f"blocked by usage-guard: headless claude launch lacks {miss}. Add {SUGGEST}.", count)
        count = add_count(slug, r.total)
        why = f"{r.total} launch{'es' if r.total != 1 else ''}, {r.conc} at once" + (f", unlocked until {clock(unlocked)}" if unlocked else "")
        log(slug, "ALLOW", count, cmd, why)
    return 0


def norm(s):
    return " ".join((s or "").lower().split())


def digest(s):
    import hashlib
    return hashlib.sha1(norm(s).encode()).hexdigest()[:16]


def live_agents(slug, session):
    """live subagents of this session: files written by SubagentStart plus launches allowed a moment ago"""
    d, n, t = os.path.join(pdir(slug), "live"), 0, now()
    for name in os.listdir(d):
        p = os.path.join(d, name)
        try:
            age = t - os.path.getmtime(p)
            owner = open(p).read().strip()
        except OSError:
            continue
        if age > (STALE_PENDING if name.startswith("pending-") else STALE_LIVE) or age < -STALE_LIVE:
            if NOW is None:
                try:
                    os.unlink(p)
                except OSError:
                    pass
            continue
        if owner == session:
            n += 1
    return n


def agent_hook(data):
    ti = dict(data.get("tool_input") or {})
    cwd = data.get("cwd") or os.getcwd()
    slug, session = slug_of(cwd), data.get("session_id") or ""
    desc, prompt = ti.get("description") or "", ti.get("prompt") or ""
    what = f"Agent[{ti.get('subagent_type') or 'default'}] {desc or prompt}"
    with Lock(slug):
        unlocked = allow_until(slug)
        count = read_count(slug)
        if not unlocked:
            n = live_agents(slug, session)
            if n >= MAX_SUBAGENTS:
                block(slug, what, f"blocked by usage-guard: {n} subagents running (max {MAX_SUBAGENTS}); wait for one to finish", count)
            dpath = os.path.join(pdir(slug), f"{today()}.dispatched")
            nd, np_, nf = norm(desc), norm(prompt[:200]), digest(prompt)
            try:
                rows = [json.loads(l) for l in open(dpath) if l.strip()]
            except (OSError, ValueError):
                rows = []
            for row in rows:
                # the same description, or the same prompt: its first 200 characters match and so does the rest (prompts
                # built from one template share their opening and differ further down, e.g. in a video id)
                if (nd and row.get("desc") == nd) or (np_ and row.get("prompt") == np_ and row.get("full") == nf):
                    block(slug, what, f"blocked by usage-guard: \"{row.get('shown') or desc}\" was already dispatched today at "
                                      f"{clock(row.get('t'))}; reuse its output", count)
            if count + 1 > DAILY:
                block(slug, what, f"blocked by usage-guard: {count}/{DAILY} launches used today for {slug}; this adds 1. "
                                  "Do the work in this session, or ask the user to run `guard allow`.", count)
        count = add_count(slug, 1)
        with open(os.path.join(pdir(slug), f"{today()}.dispatched"), "a") as f:
            f.write(json.dumps({"t": now(), "desc": norm(desc), "prompt": norm(prompt[:200]), "full": digest(prompt), "shown": desc or prompt[:60]}) + "\n")
        pend = os.path.join(pdir(slug), "live", f"pending-{data.get('tool_use_id') or int(now() * 1000)}")
        with open(pend, "w") as f:
            f.write(session)
        if NOW is not None:
            os.utime(pend, (NOW, NOW))
        notes, changed = [], False
        st = ti.get("subagent_type") or ""
        if st != "helper":
            notes.append(f"subagent_type {st or '(default)'} rewritten to helper")
            ti["subagent_type"] = "helper"
            changed = True
        model = ti.get("model")
        if model and not any(c in str(model).lower() for c in CHEAP_MODELS):
            forced = os.environ.get("CLAUDE_CODE_SUBAGENT_MODEL") or "sonnet"
            notes.append(f"model={model} requested, forced {forced}")
            del ti["model"]
            changed = True
        if unlocked:
            notes.append(f"unlocked until {clock(unlocked)}")
        log(slug, "ALLOW", count, what, "; ".join(notes) or "subagent launch")
    if changed:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
                                                 "permissionDecisionReason": "usage-guard: " + "; ".join(notes),
                                                 "updatedInput": ti}}))
    return 0


def file_hook(data):
    ti = data.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    cwd = data.get("cwd") or os.getcwd()
    if path and protected(path if os.path.isabs(os.path.expanduser(path)) else os.path.join(cwd, path)):
        block(slug_of(cwd), f"{data.get('tool_name')} {path}", R6)
    return 0


def _safe(s):
    return re.sub(r"[^\w.-]", "_", str(s))[:80]


def subagent_start(data):
    session, aid = data.get("session_id") or "", _safe(data.get("agent_id") or "")
    if not aid or not os.path.isdir(G):
        return 0
    import glob
    pend = []
    for p in glob.glob(os.path.join(G, "*", "live", "pending-*")):
        try:
            if open(p).read().strip() == session:
                pend.append((os.path.getmtime(p), p))
        except OSError:
            pass
    if not pend:
        return 0          # not a subagent the guard allowed for a worker
    _, p = min(pend)
    live = os.path.join(os.path.dirname(p), aid)
    os.replace(p, live)
    os.utime(live, (now(), now()))
    return 0


def subagent_stop(data):
    aid = _safe(data.get("agent_id") or "")
    if aid and os.path.isdir(G):
        import glob
        for p in glob.glob(os.path.join(G, "*", "live", aid)):
            try:
                os.unlink(p)
            except OSError:
                pass
    return 0


def is_worker(data):
    session = _safe(data.get("session_id") or "")
    marker = os.path.join(G, "sessions", session)
    if data.get("agent_type") == "worker":
        if session and not os.path.exists(marker):
            os.makedirs(os.path.dirname(marker), exist_ok=True)
            open(marker, "w").close()
        return True
    # a subagent inside a worker session is the worker's work too
    return bool(session and data.get("agent_id") and os.path.exists(marker))


def hook():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    event = data.get("hook_event_name")
    if event == "SubagentStart":
        return subagent_start(data)
    if event == "SubagentStop":
        return subagent_stop(data)
    if event != "PreToolUse" or not is_worker(data):
        return 0
    tool = data.get("tool_name")
    if tool in ("Bash", "Monitor"):
        return bash_hook(data)
    if tool == "Agent":
        return agent_hook(data)
    if tool in ("Edit", "Write", "NotebookEdit", "MultiEdit"):
        return file_hook(data)
    return 0


def main():
    global NOW, LIVE
    argv = sys.argv[1:]
    if argv and argv[0] == "cli":
        sys.path.insert(0, HERE)
        import guard_cli
        return guard_cli.main(argv[1:])
    while argv:
        a = argv.pop(0)
        if a == "--now":
            NOW = float(argv.pop(0))
        elif a == "--live":
            LIVE = int(argv.pop(0))
    return hook()


if __name__ == "__main__":
    sys.exit(main())
