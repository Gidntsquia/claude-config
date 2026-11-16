#!/usr/bin/env python3
"""usage-guard: a hard stop on the worker agent's expensive launches. Standard library only, no network, no model.

Hook mode (stdin = Claude Code hook JSON), registered in settings.json:
  PreToolUse Bash|Monitor   blocks > 2 parallel headless `claude` runs, a headless launch without --max-budget-usd /
                            --max-turns, the 31st launch of the day in a project, and any command touching guard state
  PreToolUse Agent          blocks a 4th running subagent, a task already dispatched today, the 31st launch of the
                            day; rewrites subagent_type to `helper` and drops an expensive `model`
                            (report-writer is the exception: kept, on opus)
  PreToolUse Edit|Write|NotebookEdit   blocks edits of guard state, the hook, settings.json and worker.md
  PostToolUse Bash|Monitor  raises the count when a command started more headless sessions than were counted
  SessionStart              tells a worker how many of today's launches are already used
  SubagentStart / SubagentStop         keep <project>/live/<agent_id>
An allowed launch answers with the count (`usage-guard: 12/30 used today, 18 left`) as additionalContext; a block
ends with a smaller command that fits. A command that would take over half of what is left is turned back once.
It acts only in a session started as `claude --agent worker` (hook input agent_type == "worker") and in that
session's subagents; every other session exits 0 with no output. A block is exit 2 with one line on stderr.

CLI mode: `usage_guard.py cli ...` (installed as `guard`): allow / revoke / status / log / usage.
Test-only arguments (the settings.json command passes none): --now <epoch>, --live <n>.
State: ~/.cache/claude-guard/{log, sessions/, <project>/{<date>.count, <date>.dispatched, allow, live/, runs/,
confirm/, <date>.usage.json}}.
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
KEEP = {"report-writer": "opus"}   # subagent types a worker may start as they are, with the model each runs on
STALE_LIVE, STALE_PENDING = 2 * 3600, 90
MARKS = (25, 20)          # counts at which the worker is told to plan what is left
BIG, CONFIRM = 3, 600     # a command of BIG+ launches taking over half the slots left runs only when sent twice in CONFIRM s
NO_CLAUDE = "use checks that start no claude"
TAMPER = re.compile(r"\.cache/claude-guard|claude-guard/|\bguard\s+(allow|revoke|recount)\b|usage_guard\.py|usage-guard/guard\b")
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


def log(slug, verdict, count, what, reason, part=None):
    """part: the piece of a long command that launches; shown after the cut so the line says what was counted"""
    os.makedirs(G, exist_ok=True)
    what = " ".join((what or "").split())
    part = " ".join((part or "").split())
    if len(what) > 120:
        what = what[:120] if not part or part[:60] in what[:120] else what[:50] + " … " + part[:120]
    line = f"{et().strftime('%Y-%m-%d %I:%M:%S %p ET')} | {slug} | {verdict} | {count}/{DAILY} | {what} | {reason}\n"
    with open(os.path.join(G, "log"), "a") as f:
        f.write(line)


def block(slug, what, reason, count=None, part=None):
    log(slug, "BLOCK", read_count(slug) if count is None else count, what, reason, part)
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


# ---- what the worker is told --------------------------------------------------------------------------------------
def count_note(before, after):
    left = max(DAILY - after, 0)
    if any(before < m <= after for m in MARKS):
        return f"usage-guard: {after}/{DAILY} used, {left} left today: plan the remaining checks to fit"
    return f"usage-guard: {after}/{DAILY} used today, {left} left"


def _q(w):
    import shlex
    m = re.fullmatch(r"(\w+)=(.*)", w, re.S)
    if m and not re.fullmatch(r"[\w@%+=:,./-]*", m.group(2)):
        return m.group(1) + '="' + m.group(2).replace('"', '\\"') + '"'
    return w if w.startswith("<") else shlex.quote(w)


def top_text(L):
    return " ".join(_q(w.text) for w in L.top.words) if L is not None and L.top is not None else ""


def biggest(r):
    return max(r.launches, key=lambda L: (L.top is not None, L.total()), default=None)


def smaller(r, jobs, first=None):
    """the command that launches, rewritten to fit: `-j <jobs>`, and with `first` only that many of its scenes.
    None when the launch is not a script call that takes -j."""
    import shellscan
    L = biggest(r)
    if L is None or L.top is None or not L.script:
        return None
    words = [w.text for w in L.top.words]
    k = next((i for i, w in enumerate(words) if not re.fullmatch(r"\w+=.*", w, re.S) and not w.startswith("-")
              and ("/" in w or w.endswith((".sh", ".py")))), None)
    if k is None:
        return None
    jn, rest = shellscan._jobs(words[k + 1:], {})
    if jn is None and not L.takes_j:
        return None
    flags = [a for a in rest if a.startswith("-")]
    names = [a for a in rest if not a.startswith("-")]
    if first is not None:
        names = (names or L.items or [f"<{first} scene name{'s' if first != 1 else ''}>"])[:first]
    return " ".join(_q(w) for w in words[:k + 1] + ["-j", str(jobs)] + flags + names)


def say(note, extra=None):
    out = {"hookEventName": "PreToolUse", "additionalContext": note}
    out.update(extra or {})
    print(json.dumps({"hookSpecificOutput": out}))


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
    part = top_text(biggest(r))
    with Lock(slug):
        unlocked = allow_until(slug)
        count = read_count(slug)
        live = live_headless()
        total = r.conc + live
        left = max(DAILY - count, 0)
        if total > MAX_HEADLESS and not unlocked:
            extra = f" ({live} already running)" if live else ""
            room = MAX_HEADLESS - live
            fit = smaller(r, max(room, 1))
            if room <= 0:
                tip = f"Wait for {'it' if live == 1 else 'one'} to finish, then run: {fit}" if fit else "Wait for one to finish, then start one launch at a time."
            else:
                tip = f"Run: {fit}" if fit else f"Start at most {room} at a time: one launch per command, or -P {room} / -j {room}."
            block(slug, cmd, f"blocked by usage-guard: {total} parallel headless claude runs (max {MAX_HEADLESS}){extra}. {tip}", count, part)
        if count + r.total > DAILY and not unlocked:
            fit = smaller(r, 1, left) if left else None
            tip = NO_CLAUDE if not left else (f"Run: {fit}" if fit else f"start at most {left} more, one at a time")
            block(slug, cmd, f"blocked by usage-guard: {count}/{DAILY} headless launches used today for {slug}; this adds "
                             f"{r.total}. {left} left today: {tip}", count, part)
        if r.missing:
            miss = " and ".join(r.missing)
            if r.in_script:
                where = os.path.relpath(r.in_script, project_root(cwd)) if r.in_script.startswith(project_root(cwd)) else r.in_script
                block(slug, cmd, f"blocked by usage-guard: the headless claude launch in {where} lacks {miss}. Run it with "
                                 f"CLAUDE_GUARD_FLAGS=\"{SUGGEST}\" if the script passes that variable to claude, or edit "
                                 f"the script to pass {SUGGEST}.", count, part)
            block(slug, cmd, f"blocked by usage-guard: headless claude launch lacks {miss}. Add {SUGGEST}.", count, part)
        if r.total >= BIG and 2 * r.total > left and not unlocked:
            # a big bite of what is left: turned back once, nothing counted; the same command again within 10 minutes runs
            cdir = os.path.join(pdir(slug), "confirm")
            os.makedirs(cdir, exist_ok=True)
            mark = os.path.join(cdir, digest(cmd))
            try:
                asked = float(open(mark).read().strip())
            except (OSError, ValueError):
                asked = None
            if asked is None or not 0 <= now() - asked <= CONFIRM:
                with open(mark, "w") as f:
                    f.write(f"{now()}\n")
                block(slug, cmd, f"blocked by usage-guard: this takes {r.total} of your {left} left today. Pick fewer "
                                 "scenes, or send the same command again to confirm.", count, part)
            os.unlink(mark)
        before, count = count, add_count(slug, r.total)
        why = f"{r.total} launch{'es' if r.total != 1 else ''}, {r.conc} at once" + (f", unlocked until {clock(unlocked)}" if unlocked else "")
        log(slug, "ALLOW", count, cmd, why, part)
        tid = _safe(data.get("tool_use_id") or "")
        if tid and not ti.get("run_in_background"):
            rdir = os.path.join(pdir(slug), "runs")
            os.makedirs(rdir, exist_ok=True)
            with open(os.path.join(rdir, tid), "w") as f:
                json.dump({"t": now(), "n": r.total, "cmd": part or cmd[:200]}, f)
    say(count_note(before, count))
    return 0


def headless_started(root, since, own):
    """headless (`claude -p`) session files of this project whose first record is at or after `since`"""
    from datetime import datetime
    base = os.path.join(HOME, ".claude", "projects")
    want = re.sub(r"[^A-Za-z0-9]", "-", root)
    n = 0
    try:
        dirs = [d for d in os.listdir(base) if d == want or d.startswith(want + "-")]
    except OSError:
        return 0
    for d in dirs:
        try:
            entries = list(os.scandir(os.path.join(base, d)))
        except OSError:
            continue
        for e in entries:
            if not e.name.endswith(".jsonl") or e.name[:-6] == own:
                continue
            try:
                if e.stat().st_mtime < since:
                    continue
                with open(e.path, errors="ignore") as f:
                    head = f.read(16384)
            except OSError:
                continue
            if '"entrypoint":"sdk-cli"' not in head:
                continue
            m = re.search(r'"timestamp":"([^"]+)"', head)
            try:
                first = datetime.fromisoformat(m.group(1).replace("Z", "+00:00")).timestamp() if m else 0
            except ValueError:
                first = 0
            if first >= since - 1:
                n += 1
    return n


def post_hook(data):
    """after an allowed launch command: if it started more headless sessions than were counted, count the rest"""
    cwd = data.get("cwd") or os.getcwd()
    slug, tid = slug_of(cwd), _safe(data.get("tool_use_id") or "")
    path = os.path.join(G, slug, "runs", tid)
    if not tid or not os.path.exists(path):
        return 0
    try:
        rec = json.load(open(path))
        os.unlink(path)
    except (OSError, ValueError):
        return 0
    seen = headless_started(project_root(cwd), rec.get("t", now()), data.get("session_id") or "")
    more = seen - int(rec.get("n", 0))
    if more <= 0:
        return 0
    with Lock(slug):
        before, count = read_count(slug), add_count(slug, more)
        log(slug, "RECOUNT", count, rec.get("cmd") or "", f"counted {rec.get('n')}, started {seen} headless sessions: +{more}")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext":
          f"usage-guard: that command started {seen} headless sessions, {more} more than counted. " + count_note(before, count)[13:]}}))
    return 0


def session_start(data):
    slug = slug_of(data.get("cwd") or os.getcwd())
    count = read_count(slug)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext":
          f"usage-guard: {count}/{DAILY} launches already used today for {slug}, {max(DAILY - count, 0)} left"}}))
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
                                  f"0 left today: do the work in this session and {NO_CLAUDE}.", count)
        before, count = count, add_count(slug, 1)
        with open(os.path.join(pdir(slug), f"{today()}.dispatched"), "a") as f:
            f.write(json.dumps({"t": now(), "desc": norm(desc), "prompt": norm(prompt[:200]), "full": digest(prompt), "shown": desc or prompt[:60]}) + "\n")
        pend = os.path.join(pdir(slug), "live", f"pending-{data.get('tool_use_id') or int(now() * 1000)}")
        with open(pend, "w") as f:
            f.write(session)
        if NOW is not None:
            os.utime(pend, (NOW, NOW))
        notes, changed = [], False
        st = ti.get("subagent_type") or ""
        model = ti.get("model")
        if st in KEEP:
            # the one type that is not sent to helper: it keeps its own model, passed per call because that is the
            # only thing that outranks the worker's forced subagent model
            notes.append(f"{st} kept on {KEEP[st]}")
            if model != KEEP[st]:
                ti["model"] = KEEP[st]
                changed = True
        elif st != "helper":
            notes.append(f"subagent_type {st or '(default)'} rewritten to helper")
            ti["subagent_type"] = "helper"
            changed = True
        if st not in KEEP:
            # every other subagent gets its model from here, on each call: a per-call model outranks the agent file,
            # so a `helper.md` a project supplies with a bigger model changes nothing
            forced = (os.environ.get("CLAUDE_CODE_SUBAGENT_MODEL") or "").lower()
            forced = forced if forced in CHEAP_MODELS else "sonnet"
            if str(model or "").lower() not in CHEAP_MODELS:
                notes.append(f"model={model} requested, forced {forced}" if model else f"model set to {forced}")
                ti["model"] = forced
                changed = True
        if unlocked:
            notes.append(f"unlocked until {clock(unlocked)}")
        log(slug, "ALLOW", count, what, "; ".join(notes) or "subagent launch")
    say(count_note(before, count), {"permissionDecision": "allow", "permissionDecisionReason": "usage-guard: " + "; ".join(notes),
                                    "updatedInput": ti} if changed else None)
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
    if event not in ("PreToolUse", "PostToolUse", "SessionStart") or not is_worker(data):
        return 0
    if event == "SessionStart":
        return session_start(data)
    tool = data.get("tool_name")
    if event == "PostToolUse":
        return post_hook(data) if tool in ("Bash", "Monitor") else 0
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
