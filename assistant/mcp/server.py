#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.12"
# dependencies = ["mcp>=1.2,<2"]
# ///
"""assistant: FastMCP stdio server that drives planner/worker/evaluator tmux panes.

Seven tools, all prefixed `assistant_`: panes, projects, launch, send, layout, schedule, jobs. tmux through stdlib subprocess;
scheduling through the production run-agent scripts (imported, never copied). Never writes to stdout (that is the
JSON-RPC channel); logs go to stderr. Env overrides used by tests/fake-env.sh: ASSISTANT_CLAUDE_JSON (~/.claude.json),
ASSISTANT_FILES (~/files), ASSISTANT_LOG (launches.tsv), ASSISTANT_HOME (the pet's `cd ~`), ASSISTANT_PRETRUST=0.
"""
import datetime
import json
import logging
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Literal

from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations
from pydantic import BaseModel, Field

logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="assistant: %(message)s")
log = logging.getLogger("assistant")

RA_SCRIPTS = os.path.expanduser("~/.claude/skills/run-agent/scripts")
sys.path.insert(0, RA_SCRIPTS)
import launch as ra_launch  # noqa: E402  (production run-agent: parse/run_args/S_REAL)
import parse as ra_parse  # noqa: E402  (fmt_et, now_ts)
import jobs as ra_jobs  # noqa: E402  (list/cancel on RUN_AGENT_HOME)

HOME = os.path.expanduser("~")
PET_HOME = os.environ.get("ASSISTANT_HOME") or HOME
FILES = os.environ.get("ASSISTANT_FILES") or os.path.join(HOME, "files")
CLAUDE_JSON = (os.environ.get("ASSISTANT_CLAUDE_JSON")
               or os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or HOME, ".claude.json"))
LOG_TSV = os.environ.get("ASSISTANT_LOG") or os.path.join(HOME, ".cache", "assistant-agent", "launches.tsv")
TOOLS = os.path.join(HOME, ".claude", "local-tools")
# the WSL window tools (R5): a new tmux session is shown in its own Windows Terminal window placed below the user's;
# tests point these at stubs (tests/bin) so the harness runs anywhere
WIN_SH = os.environ.get("ASSISTANT_WIN_SH") or os.path.join(TOOLS, "win.sh")
GAME_GUARD = os.environ.get("ASSISTANT_GAME_GUARD") or os.path.join(TOOLS, "game-guard.sh")
WT_EXE = os.environ.get("ASSISTANT_WT") or ""          # '' = wt.exe on PATH (WSL)
WT_PROFILE = os.environ.get("ASSISTANT_WT_PROFILE") or os.environ.get("TERM_OPEN_PROFILE") or "Ubuntu"
WT_WAIT = float(os.environ.get("ASSISTANT_WT_WAIT") or 15)   # seconds to wait for the new terminal to attach / show up
PROJECTS = os.environ.get("ASSISTANT_PROJECTS") or os.path.join(HOME, ".claude", "projects")   # Claude Code transcripts
PETS = ["squid", "cat", "dog", "capybara"]     # one of each across every tmux session
STATES = ("running", "done", "idle", "waiting", "trust", "error", "idle-bash", "pet", "other")

mcp = FastMCP("assistant", instructions=(
    "Operates the user's planner/worker/evaluator Claude Code sessions in tmux. Start every order with assistant_panes "
    "and assistant_projects; each pane row's `allowed` lists the steps that may be taken on it. Act with "
    "assistant_launch (a new session, into an empty shell), assistant_send (type into a done/idle pane), "
    "assistant_layout (close, move, swap, retile), assistant_schedule (later), assistant_jobs (pending runs). "
    "A refusal names the step to take instead."))


# ============================================================================ time / tmux
def now_et() -> str:
    try:
        from zoneinfo import ZoneInfo
        d = datetime.datetime.now(ZoneInfo("America/New_York"))
    except Exception:  # noqa: BLE001
        d = datetime.datetime.now()
    off = os.environ.get("ASSISTANT_CLOCK_OFFSET_MIN", "")   # the replay harness ages the clock between two turns
    if off.strip():
        d += datetime.timedelta(minutes=int(off))
    return d.strftime("%Y-%m-%d %-I:%M %p %Z")


def _env() -> dict:
    """our environment, with the parent claude's TMUX/TMUX_PANE when ours lack them (agent-scoped MCP inherits them)"""
    env = dict(os.environ)
    if not env.get("TMUX"):
        try:
            ce = ra_launch.claude_environ()
            for k in ("TMUX", "TMUX_PANE"):
                if ce.get(k):
                    env[k] = ce[k]
        except Exception:  # noqa: BLE001
            pass
    return env


def _tm_base() -> list[str]:
    sock = (_env().get("TMUX") or "").split(",")[0]
    return ["tmux", "-S", sock] if sock else ["tmux"]


def tm(*args: str) -> str:
    r = subprocess.run([*_tm_base(), *args], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"tmux {' '.join(args[:2])} failed: {r.stderr.strip() or 'no tmux server'}")
    return r.stdout.rstrip("\n")


def in_tmux() -> bool:
    if not _env().get("TMUX"):
        return False
    return subprocess.run([*_tm_base(), "display", "-p", "ok"], capture_output=True).returncode == 0


SESSION_ALIAS: dict[str, str] = {}   # grouped session name -> the session its panes are listed under (see _pane_rows)


def _canon(session: str) -> str:
    """the session a name stands for: a grouped session (`new-session -t 1` makes "1-2") shows the same windows as
    its first session, and every pane is listed under that first one"""
    return SESSION_ALIAS.get(session, session)


def my_session() -> str:
    p = _env().get("TMUX_PANE", "")
    try:
        s = tm("display", "-p", *(["-t", p] if p else []), "#{session_name}")
    except RuntimeError:
        s = tm("list-sessions", "-F", "#{session_name}").split("\n")[0]
    if not SESSION_ALIAS:
        try:
            _pane_rows()
        except RuntimeError:
            pass
    return _canon(s)


# ============================================================================ processes under a pane
def _proc_tree(root: str) -> list[tuple[str, str, list[str]]]:
    """[(pid, comm, argv)] for root and every descendant (Linux /proc; macOS ps)"""
    kids: dict[str, list[str]] = {}
    if not os.path.isdir("/proc/self"):
        return _proc_tree_ps(root)
    for n in os.listdir("/proc"):
        if n.isdigit():
            try:
                st = open(f"/proc/{n}/stat").read().rsplit(")", 1)[1].split()
                kids.setdefault(st[1], []).append(n)
            except OSError:
                pass
    out, todo = [], [root]
    while todo:
        p = todo.pop()
        try:
            comm = open(f"/proc/{p}/comm").read().strip()
            argv = [a.decode(errors="replace") for a in open(f"/proc/{p}/cmdline", "rb").read().split(b"\0") if a]
        except OSError:
            comm, argv = "", []
        out.append((p, comm, argv))
        todo.extend(kids.get(p, []))
    return out


def _proc_tree_ps(root: str) -> list[tuple[str, str, list[str]]]:
    """_proc_tree without /proc: ps lists the processes, run-agent's proc.py reads each argv"""
    import proc as ra_proc
    r = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,comm="], capture_output=True, text=True)
    kids: dict[str, list[str]] = {}
    comms: dict[str, str] = {}
    for ln in r.stdout.splitlines():
        f = ln.split(None, 2)
        if len(f) == 3:
            kids.setdefault(f[1], []).append(f[0])
            comms[f[0]] = os.path.basename(f[2].strip())
    out, todo = [], [root]
    while todo:
        p = todo.pop()
        out.append((p, comms.get(p, ""), ra_proc.argv(p) if p in comms else []))
        todo.extend(kids.get(p, []))
    return out


def _pet_kind(argv: list[str]) -> str:
    k = _flag(argv, "--pet") or "squid"
    return "capybara" if k == "capy" else k


def _flag(argv: list[str], *names: str) -> str:
    for i, a in enumerate(argv):
        if a in names and i + 1 < len(argv):
            return argv[i + 1]
        for n in names:
            if a.startswith(n + "="):
                return a.split("=", 1)[1]
    return ""


# ============================================================================ state classification
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][A-Z0-9]")   # CSI, OSC (BEL or ST ended), charset
RULE = re.compile(r"^\s*─{8,}")
PROMPT = re.compile(r"^\s*❯\s?(.*)$")
RUNNING = re.compile(r"esc to interrupt|⎿\s+Running…|^\s*[✻✶✳✢·✽⠂⠐⠒⠈⠁⠄⠠⠐]\s\S.*…", re.M)
SPINNER_LINE = re.compile(r"^\s*[✻✶✳✢·✽*]\s.*…", re.M)
TRUST = re.compile(r"Do you trust the files|Yes, I trust this folder|Yes, proceed|\.mcp\.json|hooks? (found|approval)|"
                   r"Use these hooks|MCP servers? (found|in this project)", re.I)
WAITING = re.compile(r"Enter to (confirm|select)|Esc to cancel|❯\s*1\.\s|Do you want to|Press Enter to continue|"
                     r"\(y/n\)|\[y/N\]|\[Y/n\]|Allow (once|always)|Yes, allow", re.I)
ERROR = re.compile(r"\b429\b|overloaded|rate.?limit|usage limit|API Error|api error", re.I)
USAGE = re.compile(r"usage limit[^\n]*?resets? (?:at|in)\s+([^\n(]+?)(?:\s*\(|\s*$)", re.I)
CLOSING = re.compile(r"^\s*(Without run-agent:\s*)?claude --agent \S+|^\s*/run-agent \S+")
NEXT_LINE = re.compile(r"^\s*(/run-agent\s+(\S+).*)$")
VERDICT = re.compile(r"\bverdict\b", re.I)
DONE_LINE = re.compile(r"^\s*[✻✶✳✢·✽]\s.*·\s*done\b")
# background work after the turn ended: (a) the done line's suffix, (b) the status bar count, (c) transcript lines
BG_DONE = re.compile(r"^\s*[✻✶✳✢·✽]\s.*·\s*done\b.*?·\s*(\d+\s+(?:shell|monitor|agent|task)s?(?:,\s*\d+\s+(?:shell|monitor|agent|task)s?)*\s+still running)")
BG_BAR = re.compile(r"⏵⏵.*?·\s*(\d+\s+(?:shell|monitor|agent|task)s?(?:,\s*\d+\s+(?:shell|monitor|agent|task)s?)*)\s*$")
BAR_LINE = re.compile(r"⏵⏵")
BG_START = re.compile(r"Monitor started\s*·\s*task\s+(\S+)|running in background|\bstill running\b", re.I)
BG_END = re.compile(r"Monitor event|finished|killed|stopped|completed", re.I)
PET_LINE = re.compile(r"\[f\] feed\s+\[p\] pet")
CLAUDE_UI = re.compile(r"auto mode|shift\+tab to cycle|^\s*❯|esc to interrupt|Claude Code v\d|⏵⏵|─{20,}", re.M)
HEADER_MODEL = re.compile(r"^\s*▝▜██████▀\s+(\S.*?) with (\w+) effort", re.M)
HEADER_AGENT = re.compile(r"^\s*▝▝\s+▝▝\s+@(\S+)", re.M)
STATUS_MODEL = re.compile(r"(Opus|Sonnet|Haiku|Fable)(?: [\d.]+)?", re.I)


def strip_ansi(s: str) -> str:
    return ANSI.sub("", s)


SGR = re.compile(r"\x1b\[([0-9;]*)m")


def _grey(params: list[str], i: int) -> bool | None:
    """True/False when params[i] sets the foreground to a grey / non-grey colour, None when it is not a colour"""
    p = params[i]
    if p in ("90",) or p == "38" and i + 2 < len(params) and params[i + 1] == "5" and (params[i + 2] == "8" or 240 <= int(params[i + 2] or 0) <= 250):
        return True
    if p == "38" and i + 4 < len(params) and params[i + 1] == "2":
        r, g, b = (int(x or 0) for x in params[i + 2:i + 5])
        return r == g == b and r < 170
    if p in ("39",) or p.startswith("3") and len(p) == 2 or p == "38" or p.startswith("9") and len(p) == 2:
        return False
    return None


def drop_ghost(raw: str) -> tuple[str, str]:
    """(line with ANSI stripped and the autocomplete ghost removed, the ghost text). Claude Code draws its autocomplete /
    suggestion in the ❯ box as dim (SGR 2) or grey text; anything after the ❯ in that style was never typed by the user."""
    kept, ghost = [], []
    dim = grey = after = False
    pos = 0
    for m in re.finditer(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[()][A-Z0-9]", raw):
        chunk = raw[pos:m.start()]
        pos = m.end()
        if chunk:
            if not after and "❯" in chunk:
                a, b = chunk.split("❯", 1)
                kept.append(a + "❯")
                after = True
                chunk = b
            (ghost if after and (dim or grey) else kept).append(chunk)
        sg = SGR.match(m.group(0))
        if not sg:
            continue
        params = sg.group(1).split(";") if sg.group(1) else ["0"]
        i = 0
        while i < len(params):
            p = params[i]
            if p in ("0", ""):
                dim = grey = False
            elif p == "2":
                dim = True
            elif p == "22":
                dim = False
            else:
                g = _grey(params, i)
                if g is not None:
                    grey = g
                    if p == "38":
                        i += 4 if i + 1 < len(params) and params[i + 1] == "2" else 2
            i += 1
    chunk = raw[pos:]
    if chunk:
        if not after and "❯" in chunk:
            a, b = chunk.split("❯", 1)
            kept.append(a + "❯")
            after = True
            chunk = b
        (ghost if after and (dim or grey) else kept).append(chunk)
    g = "".join(ghost).strip()
    k = "".join(kept)
    if g and not k.rstrip().endswith("❯"):
        k = k.rstrip() + " "   # typed text plus a trailing ghost: keep the typed part
    return k, g


OPTION = re.compile(r"^\s*(❯)?\s{0,3}(\d{1,2})\.\s+(\S.*)$")
MENU_FOOT = re.compile(r"Enter to (select|confirm)|Esc to cancel|Tab to amend|↑/↓ to navigate", re.I)
FREE_OPTION = re.compile(r"type something|^other\b|tell claude what to do|chat about this", re.I)
PERMISSION_Q = re.compile(r"Do you want to proceed|Allow (once|always)|Yes, allow|don't ask again|Yes, and|permission", re.I)
PROCEED_Q = re.compile(r"\b(ready|proceed|continue|go ahead|start|ok to)\b", re.I)
YN_LINE = re.compile(r"\((y/n|Y/n|y/N)\)|\[(y/N|Y/n|y/n)\]", re.I)
CHIP = re.compile(r"^\s*☐|^\s*☑")


def unbox(plain: list[str]) -> list[str]:
    """the same lines with a surrounding `│ … │` box frame removed (the folder-trust dialog draws its options inside one)"""
    out = []
    for l in plain:
        t = l.rstrip()
        if t.startswith("│") and t.endswith("│") and len(t) > 1:
            t = t[1:-1].rstrip()
            if t.startswith(" "):
                t = t[1:]
        out.append(t)
    return out


def read_menu(plain: list[str]) -> dict | None:
    """an AskUserQuestion menu, permission prompt or y/n question on screen (ANSI-stripped lines, ghost text kept).
    Claude Code draws options as `❯ 1. Text` (highlighted) / `  2. Text`, description lines indented below each, then
    `Enter to select · Esc to cancel`; the ❯ input box is not on screen while a dialog is. Returns
    {question, options (['❯ 1. Squid', '2. Cat', …]), highlighted, free_option, kind, start} or None."""
    n = len(plain)
    lo = max(0, n - 45)
    blocks: list[list[tuple[int, str, int, str]]] = []   # (line index, mark, number, text)
    cur: list[tuple[int, str, int, str]] = []
    for i in range(lo, n):
        m = OPTION.match(plain[i])
        if m and int(m.group(2)) == len(cur) + 1:
            cur.append((i, m.group(1) or "", int(m.group(2)), m.group(3).strip()))
            continue
        if cur and (not plain[i].strip() or plain[i].startswith("    ") or RULE.match(plain[i]) or plain[i].lstrip().startswith("╌")):
            continue          # description line, blank, or the rule before "Chat about this"
        if cur:
            blocks.append(cur)
            cur = []
        if m and int(m.group(2)) == 1:
            cur = [(i, m.group(1) or "", 1, m.group(3).strip())]
    if cur:
        blocks.append(cur)
    yn = None
    for i in range(n - 1, lo - 1, -1):
        if YN_LINE.search(plain[i]):
            yn = i
            break
    block = None
    for b in reversed(blocks):
        if len(b) >= 2 and any(mark for _, mark, _, _ in b):
            tail = plain[b[-1][0] + 1:b[-1][0] + 6]
            if any(MENU_FOOT.search(x) for x in tail) or any(mark for _, mark, _, _ in b):
                block = b
                break
    if block is None:
        arrow = _arrow_list(plain, lo)
        if arrow:
            return arrow
        if yn is not None and not any(PROMPT.match(x) and not OPTION.match(x) for x in plain[yn + 1:]):
            return {"question": plain[yn].strip()[:300], "options": ["y", "n"], "highlighted": 0, "free_option": 0,
                    "kind": "yn", "start": yn, "unnumbered": False}
        return None
    # no live ❯ input box below the menu (a menu in the transcript is finished)
    for x in plain[block[-1][0] + 1:]:
        if PROMPT.match(x) and not OPTION.match(x):
            return None
    start = block[0][0]
    q: list[str] = []
    for i in range(start - 1, max(lo - 1, start - 14), -1):
        ln = plain[i].strip()
        if RULE.match(plain[i]) or CHIP.match(plain[i]) or ln.startswith(("╭", "╰")):
            break
        if not ln or ln.startswith("╌") or ln.startswith("Tip:") or set(ln) <= set("│ "):
            continue
        q.append(ln.strip("│ ").strip())
    q.reverse()
    question = " | ".join(q)[:400]
    options = [f"{'❯ ' if mark else ''}{num}. {txt}" for _, mark, num, txt in block]
    highlighted = next((num for _, mark, num, _ in block if mark), 0)
    free = next((num for _, _, num, txt in block if FREE_OPTION.search(txt)), 0)
    if PERMISSION_Q.search(question) or any(PERMISSION_Q.search(txt) for _, _, _, txt in block):
        kind = "permission"
    elif PROCEED_Q.search(question) and all(re.match(r"^(yes|no|y|n)\b", txt, re.I) or FREE_OPTION.search(txt) for _, _, _, txt in block):
        kind = "proceed"
    else:
        kind = "menu"
    return {"question": question, "options": options, "highlighted": highlighted, "free_option": free, "kind": kind, "start": start,
            "unnumbered": False}


VERDICT_OPT = re.compile(r"\b(works|doesn't work|does not work|not what I meant|ship|rerun|replan)\b", re.I)
JUDGEMENT_Q = re.compile(r"\b(which|prefer|choose|pick|style|design|layout|theme|colou?r|name|idea|option|approach|direction|look)\b", re.I)


def is_judgement(kind: str, question: str, options: list[str], agent: str) -> bool:
    """a menu the user wants to answer: an evaluator's verdict (Works / Doesn't work / Not what I meant), or a planner's
    or evaluator's choice between ideas (which / prefer / style / design…). Permission and trust dialogs are mechanics and not a
    judgement; a proceed or y/n question is the user's (an evaluator's "Ready for me to move windows and start?"). The PreToolUse hook blocks assistant_send(answer=) on a judgement row."""
    if kind in ("proceed", "yn"):
        return True       # "Ready for me to move windows and start?": the user is at the desk or is not, only they know
    if kind != "menu":
        return False
    opts = " ".join(options)
    if sum(1 for o in options if VERDICT_OPT.search(o)) >= 2:
        return True
    return agent in ("planner", "evaluator") and bool(JUDGEMENT_Q.search(question) or JUDGEMENT_Q.search(opts))


ARROW_OPT = re.compile(r"^\s{0,3}(❯)?\s{1,4}(\S.*)$")


def _arrow_list(plain: list[str], lo: int) -> dict | None:
    """an unnumbered dialog: `❯ No, exit` / `  Yes, I trust this folder` straight above `Enter to confirm · Esc to cancel`
    (the folder-trust dialog since Claude Code 2.1). Options get numbers in screen order ('❯ 1. No, exit', '2. Yes, …');
    answer_dialog moves the cursor with Up/Down. The highlighted one may be No: nobody presses a blind Enter here."""
    n = len(plain)
    foot = next((i for i in range(n - 1, lo - 1, -1) if MENU_FOOT.search(plain[i])), None)
    if foot is None:
        return None
    if any(PROMPT.match(x) and not OPTION.match(x) for x in plain[foot + 1:]):
        return None
    rows: list[tuple[int, str, str]] = []
    i = foot - 1
    while i >= lo and len(rows) < 6:
        ln = plain[i]
        if not ln.strip():
            if rows:
                break
            i -= 1
            continue
        m = ARROW_OPT.match(ln)
        if not m or RULE.match(ln) or len(m.group(2)) > 80:
            break
        rows.append((i, m.group(1) or "", m.group(2).strip()))
        i -= 1
    rows.reverse()
    if len(rows) < 2 or not any(mark for _, mark, _ in rows):
        return None
    start = rows[0][0]
    q: list[str] = []
    for j in range(start - 1, max(lo - 1, start - 14), -1):
        ln = plain[j].strip()
        if RULE.match(plain[j]) or CHIP.match(plain[j]) or ln.startswith(("╭", "╰")):
            break
        if not ln or ln.startswith("╌") or set(ln) <= set("│ "):
            continue
        q.append(ln.strip("│ ").strip())
    q.reverse()
    options = [f"{'❯ ' if mark else ''}{k + 1}. {txt}" for k, (_, mark, txt) in enumerate(rows)]
    highlighted = next((k + 1 for k, (_, mark, _) in enumerate(rows) if mark), 0)
    return {"question": " | ".join(q)[:400], "options": options, "highlighted": highlighted, "free_option": 0,
            "kind": "menu", "start": start, "unnumbered": True}


def classify(text: str, procs: list[tuple[str, str, list[str]]]) -> dict:
    """state and message facts for one pane from its captured text (ANSI kept, so the ❯ box's dim autocomplete ghost
    can be told from typed text) and process tree. Text decides the state (fake panes in tests print captured
    screens); processes name agent/model when the screen does not."""
    ghosts: dict[int, str] = {}
    clean = []
    for i, rl in enumerate(text.split("\n")):
        if "❯" in rl and "\x1b" in rl:
            c, g = drop_ghost(rl)
            if g:
                ghosts[i] = g
            clean.append(c)
        else:
            clean.append(strip_ansi(rl))
    plain = [strip_ansi(rl).rstrip() for rl in text.split("\n")]   # ANSI stripped, ghost kept: menus read from this
    text = "\n".join(clean)
    comms = [c for _, c, _ in procs]
    claude = next((a for _, c, a in procs if c == "claude" or (a and os.path.basename(a[0]) == "claude")), None)
    lines = [ln.rstrip() for ln in text.split("\n")]
    nb = [ln for ln in lines if ln.strip()]
    out = {"agent": "", "model": "", "process": "", "tail": nb, "last_message": "", "next_line": "",
           "next_agent": "", "prompt_text": "", "ends_with": "", "error": "", "reset_text": "", "pet": "", "has_prompt": False,
           "why": "", "suggestion": "", "question": "", "options": [], "highlighted": 0, "free_option": 0, "question_kind": "",
           "judgement": False,
           "unnumbered": False}
    pet = next((a for _, c, a in procs if c == "terminal-pet" or any(os.path.basename(x) == "terminal-pet" for x in (a or [])[:2])), None)
    if pet is not None or (nb and PET_LINE.search(nb[-1])):
        out.update(state="pet", process="terminal-pet", pet=_pet_kind(pet or []))
        return out
    looks_claude = bool(CLAUDE_UI.search(text)) or claude is not None
    if not looks_claude:
        shells = {"bash", "zsh", "sh", "fish", "dash"}
        leaf = procs[-1][1] if procs else ""
        others = [c for c in comms if c not in shells]
        out["process"] = leaf or "?"
        # a shell with nothing running is idle-bash; a foreground program (vim, ssh, a build, sleep) counts as running
        out["state"] = "idle-bash" if procs and not others else ("running" if others else "other")
        return out
    out["process"] = "claude"
    if claude:
        out["agent"] = _flag(claude, "--agent")
        out["model"] = _flag(claude, "--model", "-m")
        name = _flag(claude, "--name", "-n")
        if not out["agent"]:
            m = re.match(r"^(\w[\w-]*):", name)
            out["agent"] = m.group(1) if m else ""
        if not out["model"]:
            m = re.search(r"\((\w+)\)\s*$", name)
            out["model"] = m.group(1) if m else ""
    if not out["agent"]:
        m = HEADER_AGENT.search(text)
        out["agent"] = m.group(1) if m else ""
    if not out["model"]:
        m = HEADER_MODEL.search(text)
        if m:
            out["model"] = m.group(1)
        else:
            m = STATUS_MODEL.search(nb[-2] if len(nb) >= 2 else (nb[-1] if nb else ""))
            out["model"] = m.group(0) if m else ""
    last12 = "\n".join(nb[-12:])
    # trust and other dialogs come before everything: they block the pane
    if TRUST.search(last12) and (WAITING.search(last12) or "❯ 1." in last12):
        out["state"] = "trust"
        menu = read_menu(plain) or read_menu(unbox(plain))   # the folder-trust dialog is drawn inside a │ box
        if menu:
            out.update(question=menu["question"], options=menu["options"], highlighted=menu["highlighted"],
                       free_option=menu["free_option"], question_kind="trust", unnumbered=menu.get("unnumbered", False))
        return out
    # an AskUserQuestion menu / permission prompt / y-n question replaces the ❯ box: waiting, never idle (boxed or not)
    menu = read_menu(plain) or read_menu(unbox(plain))
    if menu:
        out["state"] = "waiting"
        out.update(question=menu["question"], options=menu["options"], highlighted=menu["highlighted"],
                   free_option=menu["free_option"], question_kind=menu["kind"], unnumbered=menu.get("unnumbered", False))
        out["tail"] = [ln for ln in plain[:menu["start"]] if ln.strip()]
        return out
    # the input box: the last `❯` line sitting between two rules; the transcript is everything above the upper rule
    rules = [i for i, ln in enumerate(lines) if RULE.match(ln)]
    box_i = None
    for i in range(len(lines) - 1, -1, -1):
        if PROMPT.match(lines[i]) and any(r < i for r in rules) and any(r > i for r in rules):
            box_i = i
            break
    if box_i is None:
        if WAITING.search(last12):
            out["state"] = "waiting"
        elif RUNNING.search(last12):
            out["state"] = "running"
        elif ERROR.search(last12):
            out["state"] = "error"
            out["error"] = _error_text(nb[-12:])
        else:
            out["state"] = "other"
        return out
    upper = max([r for r in rules if r < box_i], default=box_i)
    transcript = [ln for ln in lines[:upper] if ln.strip()]
    below = "\n".join(lines[box_i + 1:])
    out["prompt_text"] = PROMPT.match(lines[box_i]).group(1).strip()
    out["suggestion"] = ghosts.get(box_i, "")
    out["has_prompt"] = True
    out["tail"] = transcript
    recent = "\n".join(transcript[-12:])
    # a spinner anywhere recent means running, even with a ❯ prompt on screen
    if SPINNER_LINE.search(recent) and not any(DONE_LINE.match(x) for x in transcript[-2:]) or RUNNING.search(recent):
        if not any(DONE_LINE.match(x) for x in transcript[-1:]):
            out["state"] = "running"
            return out
    if WAITING.search(recent) and not any(CLOSING.match(x) for x in transcript[-4:]) and not any(
            DONE_LINE.match(x) for x in transcript[-2:]):
        out["state"] = "waiting"
        return out
    body = transcript
    for i in range(len(transcript) - 1, -1, -1):
        if DONE_LINE.match(transcript[i]):
            body = transcript[:i]
            break
    last = body[-6:]
    out["last_message"] = "\n".join(last[-3:])
    # the turn ended but background work (shell, monitor, agent, task) will nudge the agent later: running + why
    why = _background(transcript, below)
    if why:
        out["state"], out["why"] = "running", why
        return out
    if ERROR.search(recent) and not any(CLOSING.match(x) for x in last[-3:]):
        out["state"] = "error"
        out["error"] = _error_text(transcript[-12:])
        m = USAGE.search(recent)
        if m:
            out["reset_text"] = m.group(1).strip()
        return out
    closing = any(CLOSING.match(x) for x in last[-3:])
    for x in reversed(last):
        m = NEXT_LINE.match(x)
        if m:
            out["next_line"], out["next_agent"] = m.group(1).strip(), m.group(2)
            break
    verdict = any(VERDICT.search(x) for x in last[-4:])
    if out["prompt_text"] == "" and (closing or verdict):
        out["state"] = "done"
        out["ends_with"] = "closing-lines" if closing else "eval-verdict"
    else:
        out["state"] = "idle"
    return out


def _background(transcript: list[str], below: str) -> str:
    """why-text when the pane's turn has ended but background work is still running, else ''. Signals, any one
    suffices: (a) the latest `✻ … · done H:MM · N shell, N monitor still running` line, verbatim suffix; (b) the
    status bar `⏵⏵ … · N shell, N monitor` (verbatim count); (c) a transcript line that started a background item
    (`Monitor started · task X`, `running in background`, `… still running`) with no later line ending it
    (`Monitor event`/`finished`/`killed`/`stopped` naming the same task) — only when no status bar is visible, since
    a visible bar without a count means everything ended."""
    for ln in reversed(transcript):
        if DONE_LINE.match(ln):
            m = BG_DONE.match(ln)
            if m:
                return m.group(1).strip()
            break
    bar = next((ln for ln in below.split("\n") if BAR_LINE.search(ln)), None)
    if bar is not None:
        m = BG_BAR.search(bar.rstrip())
        return m.group(1).strip() if m else ""
    for i in range(len(transcript) - 1, -1, -1):
        m = BG_START.search(transcript[i])
        if not m:
            continue
        task = m.group(1)
        later = transcript[i + 1:]
        if task and any(BG_END.search(x) and task in x for x in later):
            return ""
        if not task and any(BG_END.search(x) for x in later):
            return ""
        return re.sub(r"\s+", " ", transcript[i].strip().lstrip("●○◐◑ ").strip())[:120]
    return ""


def _error_text(lines: list[str]) -> str:
    for ln in reversed(lines):
        if ERROR.search(ln):
            return re.sub(r"\s+", " ", ln.strip())[:200]
    return ""


def _pane_rows(session: str = "") -> list[dict]:
    fmt = ("#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}\t#{pane_current_path}\t#{pane_pid}\t"
           "#{pane_title}\t#{window_panes}\t#{pane_dead}\t#{pane_current_command}\t#{pane_top}\t#{pane_left}\t"
           "#{@name}\t#{window_width}\t#{window_height}\t#{pane_width}\t#{pane_height}\t#{window_id}\t#{window_active}\t"
           "#{session_attached}")
    # always `list-panes -a`, filtered here: `-t =1` on a session named "1" resolved to another session (the dog-window bug)
    # a grouped session (`new-session -t 1` makes "1-2") lists the same panes again under its own name: each pane id
    # is kept once, under its first session, so retile and launch never read the copy as a second agent
    rows, seen = [], {}
    SESSION_ALIAS.clear()
    try:
        out = tm("list-panes", "-a", "-F", fmt)
    except RuntimeError:
        if not tm("list-sessions", "-F", "#{session_name}").strip():
            return []
        raise
    for ln in out.split("\n"):
        if not ln.strip():
            continue
        s, w, p, pid, cwd, ppid, title, n, dead, cmd, top, left, name, ww, wh, pw, ph, wid, wact, satt = ln.split("\t")
        if pid in seen:
            first = seen[pid]
            if s != first["session"]:
                SESSION_ALIAS[s] = first["session"]
                first["attached"] = first["attached"] or satt not in ("", "0")   # shown through either name
            continue
        row = {}
        seen[pid] = row
        row.update({"pane": f"{s}:{w}.{p}", "id": pid, "session": s, "window": int(w), "index": int(p),
                     "cwd": cwd, "pane_pid": ppid, "title": title, "window_panes": int(n), "dead": dead == "1",
                     "command": cmd, "top": int(top), "left": int(left), "name": name, "win_w": int(ww), "win_h": int(wh),
                     "width": int(pw), "height": int(ph), "win_id": int(wid.lstrip("@") or 0), "win_active": wact == "1",
                     "attached": satt not in ("", "0")})
        rows.append(row)
    for r in rows:                      # every pane of a window shares the window's attached flag
        r["attached"] = r["attached"] or any(x["attached"] for x in rows if x["win_id"] == r["win_id"])
    session = _canon(session) if session else ""
    return [r for r in rows if not session or r["session"] == session]


def _inspect(row: dict, lines: int = 120) -> dict:
    text = tm("capture-pane", "-e", "-p", "-J", "-t", row["id"], "-S", f"-{lines}")
    procs = _proc_tree(row["pane_pid"]) if row["pane_pid"] else []
    info = classify(text, procs)
    if row["dead"]:
        info["state"], info["process"] = "other", "dead"
    if info["state"] == "idle-bash" or info["state"] == "other":
        info["process"] = info["process"] or row["command"]
    # agent/model from the pane title "worker: proj (sonnet)" when the screen and argv did not say
    m = re.match(r"^\s*\S*\s*(\w[\w-]*):\s.*\((\w[\w.-]*)\)\s*$", row["title"])
    if info["process"] == "claude" and m:
        info["agent"] = info["agent"] or m.group(1)
        info["model"] = info["model"] or m.group(2)
    if info.get("state") == "waiting":
        info["judgement"] = is_judgement(info.get("question_kind", ""), info.get("question", ""), info.get("options", []), info.get("agent", ""))
    d = {k: row[k] for k in ("pane", "id", "cwd", "session", "window", "index", "top", "left", "name", "win_w", "win_h",
                             "win_id", "win_active", "attached", "pane_pid")}
    d.update({k: info.get(k, "") for k in ("process", "agent", "model", "state", "tail", "last_message", "next_agent",
                                            "next_line", "prompt_text", "suggestion", "ends_with", "error", "reset_text",
                                            "pet", "has_prompt", "why", "question", "options", "highlighted", "free_option",
                                            "question_kind", "unnumbered", "judgement")})
    d["window_panes"] = row["window_panes"]
    d["_pids"] = {str(row["pane_pid"])} | {str(p) for p, _, _ in procs}
    d.update(state_source="screen", waiting_for="")
    return d


# ============================================================================ session state from Claude Code itself
def claude_sessions() -> list[dict] | None:
    """`claude agents --json`: the live sessions as Claude Code lists them (pid, cwd, status busy | waiting | idle,
    waitingFor). None when the command is missing, fails or prints something else: the screen is read instead."""
    if time.monotonic() - _CS_CACHE["t"] < 2:          # one tool call reads the panes many times
        return _CS_CACHE["v"]
    _CS_CACHE.update(t=time.monotonic(), v=_claude_sessions())
    return _CS_CACHE["v"]


_CS_CACHE: dict = {"t": -10.0, "v": None}


def _claude_sessions() -> list[dict] | None:
    exe = os.environ.get("ASSISTANT_CLAUDE_BIN") or shutil.which("claude", path=_env().get("PATH")) or os.path.join(HOME, ".local", "bin", "claude")
    try:
        r = subprocess.run([exe, "agents", "--json"], capture_output=True, text=True, timeout=8, env=_env(),
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if r.returncode:
        return None
    try:
        v = json.loads(r.stdout)
    except ValueError:
        return None
    return [x for x in v if isinstance(x, dict)] if isinstance(v, list) else None


def _apply_claude(d: dict, sessions: list[dict] | None) -> None:
    """state from Claude Code when it lists a session whose pid runs under this pane and whose cwd is the pane's:
    busy = running, waiting = waiting (trust when the screen shows the folder-trust dialog), idle = what the screen
    says of an ended turn (done, error, idle, or running with background work named in `why`). Otherwise the state
    read from the screen stays and state_source is "screen"."""
    if not sessions or d["state"] == "pet":
        return
    cwd = os.path.realpath(d["cwd"])
    hit = next((x for x in sessions if str(x.get("pid", "")) in d["_pids"]
                and os.path.realpath(str(x.get("cwd") or "")) == cwd), None)
    if hit is None:
        return
    st, screen = str(hit.get("status") or ""), d["state"]
    if st == "busy":
        new = "running"
        if screen != "running":
            d["why"] = ""
    elif st == "waiting":
        new = "trust" if screen == "trust" else "waiting"
    elif st == "idle":
        new = screen if screen in ("done", "idle", "error") or (screen == "running" and d.get("why")) else "idle"
    else:
        return
    d.update(state=new, state_source="claude", waiting_for=str(hit.get("waitingFor") or ""), process="claude")
    if new == "waiting" and not d.get("question_kind"):
        d["question_kind"] = "permission" if "permission" in d["waiting_for"].lower() else "menu"
    m = re.match(r"^(\w[\w-]*):\s.*?(?:\((\w[\w.-]*)\))?\s*$", str(hit.get("name") or ""))
    if m:
        d["agent"] = d.get("agent") or m.group(1)
        d["model"] = d.get("model") or (m.group(2) or "")
    if new == "waiting":
        d["judgement"] = is_judgement(d.get("question_kind", ""), d.get("question", ""), d.get("options", []), d.get("agent", ""))


def _means(d: dict) -> tuple[str, list[str]]:
    """(what the pane's state means in Claude Code terms, the steps the operator may take on it)"""
    st, kind = d["state"], d.get("question_kind", "")
    if d["id"] == _self_pane():
        return "This is the operator's own session.", ["nothing: it is left out of every close, move and retile"]
    if st == "pet":
        return "The window's terminal pet, not a Claude Code session.", ["close its whole window on an order that names the window"]
    if st == "idle-bash":
        return "An empty shell with nothing running: a free quarter.", ["assistant_launch goes here"]
    if st == "running" and d.get("why"):
        return (f"The turn ended but background work ({d['why']}) will wake the session; a close loses that work, since "
                "background tasks do not come back on resume."), [
            "read", "assistant_send (it takes text like an idle session)",
            "close or move on an order that names it (force=True, confirmed=True)"]
    if st == "running":
        return "Claude Code is in the middle of a turn. Text sent now is queued until the turn ends and a close cuts the turn off.", [
            "read", "close or move on an order that names it (force=True, confirmed=True)"]
    if st == "trust":
        return "The folder-trust dialog shown before a session starts; nothing runs until it is answered.", [
            "assistant_send(answer='yes')"]
    if st == "waiting" and kind == "permission" and not d.get("judgement"):
        return "A tool permission prompt: the session is stopped until it is answered.", [
            "assistant_send(answer='yes')", "close on an order that names it (force=True, confirmed=True)"]
    if st == "waiting":
        whose = ("an evaluator's question about the user's desk or its verdict" if d.get("agent") == "evaluator"
                 else "a planner's question about the design" if d.get("agent") == "planner" else "a question")
        return f"The session is stopped on {whose}: the answer is the user's, and a close loses the question.", [
            "quote the question and its options to the user", "close on an order that names this pane (force=True, confirmed=True)"]
    if st == "error" and d.get("reset_text"):
        return "The session stopped at the usage limit; nothing runs in it until the reset.", [
            "assistant_schedule(at=<the reset time>, pane_id=<this pane>)", "close", "move"]
    if st == "error":
        return "The turn stopped on an API error (429, overload); the session and its history are intact.", [
            "assistant_send of the retry line, three times a pane at most", "close", "move"]
    if st == "done":
        nxt = d.get("next_agent") or ""
        return ("The agent ended its turn with its closing lines" + (f" naming the {nxt} as next" if nxt else "")
                + "; the session stays open until something replaces it."), [
            "assistant_send of its `/run-agent` line", "assistant_launch of this project's next agent with force=True, confirmed=True (replaces this session)",
            "close", "move"]
    if st == "idle":
        return "Claude Code sits at an empty prompt with no closing lines: a session just opened, or a turn that ended without a handoff.", [
            "assistant_send", "assistant_launch for this project with force=True, confirmed=True (replaces this session)", "close", "move"]
    return "Not a shell at rest and not a readable Claude Code screen.", ["read again with response_format='detailed'"]


# ============================================================================ pane names (by position, per window pet)
THEMES = {"squid": ["squid", "kelp", "coral", "oyster"], "cat": ["cat", "yarn", "lazer", "catnip"],
          "dog": ["dog", "bone", "fetch", "kennel"], "capybara": ["capybara", "melon", "mud", "yuzu"]}


def assign_names(ds: list[dict], write: bool = True) -> None:
    """name every pane from its position: the window's top-left pet picks the theme (squid/cat/dog), the four quarters
    top-left, top-right, bottom-left, bottom-right take the theme's four words; a 5th+ pane, or every pane of a window
    without a pet top-left, is spare-1, spare-2… in index order. Written to the tmux pane option @name (never the title)."""
    by_win: dict[tuple[str, int], list[dict]] = {}
    for d in ds:
        by_win.setdefault((d["session"], d["window"]), []).append(d)
    for prs in by_win.values():
        pos = sorted(prs, key=lambda x: (x["top"], x["left"]))
        tl = pos[0]
        if tl.get("state") == "pet":
            theme = THEMES.get(tl.get("pet") or "squid", THEMES["squid"])
            for i, d in enumerate(pos[:4]):
                d["name"] = theme[i]
            rest = sorted(pos[4:], key=lambda x: x["index"])
        else:
            rest = sorted(prs, key=lambda x: x["index"])
        for i, d in enumerate(rest, 1):
            d["name"] = f"spare-{i}"
    if write:
        for d in ds:
            cur = d.get("_tmux_name")
            if cur != d["name"]:
                try:
                    tm("set-option", "-p", "-t", d["id"], "@name", d["name"])
                except RuntimeError as e:
                    log.warning("@name %s: %s", d["id"], e)


def list_panes(session: str = "") -> list[dict]:
    ds = []
    sessions = claude_sessions()
    for r in _pane_rows(session):
        d = _inspect(r)
        _apply_claude(d, sessions)
        d["_tmux_name"] = r["name"]
        ds.append(d)
    assign_names(ds)
    for d in ds:
        d["means"], d["allowed"] = _means(d)
    return ds


# ============================================================================ tool: assistant_panes
class ProjectStep(BaseModel):
    name: str = Field(description="the project's folder name: how replies name it")
    path: str
    agent: str = Field(default="", description="the agent in the project's pane ('' = none open, or a plain claude)")
    state: str = Field(default="", description="that pane's state ('' = no agent pane)")
    pane_id: str = Field(default="", description="the project's agent pane, newest when it has two")
    older_panes: list[str] = Field(default_factory=list, description="ids of the project's other agent panes. They stay open: closing one takes a close order from the user that names it")
    stage: str = Field(default="", description="`<agent> running` | `<agent> waiting` | `<agent> stopped` | `<agent> idle` | `<agent> next` | `worker paused` (its notes end in `## Stopped at usage limit` or `## Waiting`: it booked its own relaunch) | `stuck` | `finished` (verdict ship)")
    next_agent: str = Field(default="", description="planner | worker | evaluator: the agent to start now; '' while one runs, while the user owes an answer, when stuck and when finished. Read from plans/: no PLAN.md = planner; PLAN.md newest = worker; WORKER_NOTES.md newest = evaluator; EVAL.md newest = worker (rerun worker), planner (replan) or finished (ship); a done pane's own closing line wins")
    waits_on: str = Field(default="", description="its agent | the operator (start next_agent, answer the prompt, retry) | the scheduled job a paused worker comes back with | the user | nothing")
    sent_back: int = Field(default=0, description="worker starts that followed an evaluator start since the project's last planner start (launches.tsv)")
    stuck: bool = Field(default=False, description="the evaluator sent the worker back and it was already restarted twice: no third restart without a new order")
    verdict: str = Field(default="", description="the verdict line of plans/EVAL.md when EVAL.md is the newest plan file")
    line: str = Field(default="", description="the project said in words, project and agent first: `badminton's evaluator is waiting on your verdict`")


class Pane(BaseModel):
    name: str = Field(description="positional name themed on the window's pet: squid/kelp/coral/oyster, cat/yarn/lazer/catnip, dog/bone/fetch/kennel, capybara/melon/mud/yuzu (one of each pet across all sessions, so a name is one pane) for top-left, top-right, bottom-left, bottom-right; spare-N for a 5th+ pane or a window without a pet. The user's orders name panes this way ('send /compact to kelp in window 1')")
    session: str = Field(description="tmux session name; the status table groups rows by session with a `session` column before `name`")
    window: int = Field(description="tmux window index")
    pane: str = Field(description="tmux address session:window.pane, e.g. 1:1.3")
    id: str = Field(description="tmux pane id (%N), stable while the pane lives; pass this as pane_ids / pane_id")
    cwd: str
    process: str = Field(description="claude | terminal-pet | bash | other leaf process")
    agent: str = Field(description="worker | planner | evaluator | helper | '' (plain claude or no claude)")
    model: str
    state: Literal[STATES]
    state_source: str = Field(default="screen", description="claude: `claude agents --json` lists a session whose pid runs under this pane with this cwd, and the state is its status (busy, waiting, idle) and waitingFor; screen: no such session was listed, so the state was read from the pane's text and can lag a redraw")
    waiting_for: str = Field(default="", description="Claude Code's own word for what a waiting session waits on (permission prompt, input needed, dialog open); '' from the screen")
    means: str = Field(default="", description="one sentence: what this state means in Claude Code terms")
    allowed: list[str] = Field(default_factory=list, description="the steps the operator may take on this pane as it is now; a step not listed here is refused or needs the user's order naming the pane")
    why: str = Field(default="", description="when state is running: the background work still running after the turn ended, verbatim from the screen (e.g. '1 shell, 1 monitor still running'); '' for a live spinner. Show it in the state column: 'running — 1 shell, 1 monitor still running'. A running pane with a why takes text like idle; one without takes text only when the user named it (allow_running)")
    tail: list[str] = Field(description="last non-blank transcript lines, ANSI stripped (3 concise, 12 detailed)")
    next_line: str = Field(default="", description="the `/run-agent <agent> …` closing line when the pane is done")
    next_agent: str = Field(default="", description="the agent named by next_line (what the pane expects next)")
    ends_with: str = Field(default="", description="closing-lines | eval-verdict | '' (why state is done)")
    prompt_text: str = Field(default="", description="text the user typed into the ❯ box and has not sent (never Claude's dim autocomplete suggestion); assistant_send clears it (Ctrl-U) before typing and reports `cleared: <text>`")
    suggestion: str = Field(default="", description="Claude Code's dim autocomplete / suggestion text that sat in the ❯ box; not the user's, ignored for the state (the box counts as empty); typing dismisses it")
    error: str = Field(default="", description="the error line when state is error")
    reset_text: str = Field(default="", description="the 'resets at …' words when the error is a usage limit")
    pet: str = Field(default="", description="squid | cat | dog | capybara when state is pet")
    question: str = Field(default="", description="when state is waiting/trust: the dialog's prompt text (an AskUserQuestion question, a permission prompt's header + command + 'Do you want to proceed?', a y/n line), lines joined with ' | '")
    options: list[str] = Field(default_factory=list, description="when state is waiting/trust: the numbered choices as shown ('1. Squid', '2. Cat', '4. Type something.'); the highlighted one carries a leading '❯ '. Quote them to the user when you leave the question to them")
    highlighted: int = Field(default=0, description="number of the highlighted option (0 = none)")
    free_option: int = Field(default=0, description="number of the free-text option ('Type something.' / 'Other' / 'Chat about this'), 0 when none: assistant_send(answer='free', text=…) delivers text through it")
    question_kind: str = Field(default="", description="permission (a tool permission prompt: the operator answers Yes), trust (the folder-trust dialog: the operator answers Yes), proceed (a yes/no about going on, such as an evaluator's 'Ready for me to move windows and start?': the user's), yn (a shell (y/n) question: the user's), menu (anything else: the user's). `allowed` on the row says which it is")
    held_at_launch: str = Field(default="", description="what this pane held just before the last launch into it, from launches.tsv (`<time>: worker for x went into an empty shell: process=bash cwd=~ …`); '' when no launch recorded it. When the user says a pane holds something else, answer from this and the pane's row")
    judgement: bool = Field(default=False, description="true when the menu is a judgement call for the user: an evaluator's Works / Doesn't work / Not what I meant verdict, or a planner's / evaluator's choice between ideas (which, prefer, style, design…). Quote question and options to the user; the PreToolUse hook blocks assistant_send(answer=) on such a pane")


class PanesResult(BaseModel):
    reply_rule: str = Field(default="Write no text yet: make every tool call the order needs first, without a sentence before or between them. "
                                    "A line that plans or names the next call (`Close the planner pane, done.`) is shown to the user too, so it stays in your thinking. "
                                    "Then reply once. After acting that is two sentences and 30 words at most, longer only to name something lost: the outcome, project and agent first, and what that project "
                                    "needs from the user. Reasons, routes, models and panes wait for `details`; other projects wait for `status`; nothing about later.",
                            description="how the reply to the user is written; the same on every read")
    session: str = Field(description="the tmux session the assistant itself runs in ('' outside tmux)")
    in_tmux: bool
    time_et: str
    panes: list[Pane]
    status_line: str = Field(default="", description="the brief that opens a status reply, one line per part, parts with nothing in them left out: `One thing needs you: badminton's evaluator is waiting on your verdict.` / `Running: archery and golf, both on their workers.` / `Stopped: rowing's worker stopped: API Error 429.` / `Finished: skiing's worker and curling's planner.` Built from `projects`; used word for word, and only when the user asks for status")
    duplicates: list[str] = Field(default_factory=list, description="one line per project holding two or more agent panes, project first: `worker-building has two agents open: a running worker and an idle planner; the older is the worker.` The older panes' ids are in that project's `older_panes`; all of them stay open until a close order names one")
    projects: list[ProjectStep] = Field(default_factory=list, description="one row per project that has an agent pane: its stage in the planner, worker, evaluator pipeline, what it waits on and the agent to start next")
    note: str = Field(default="", description="truncation or environment notes for the agent")


@mcp.tool(name="assistant_panes", annotations=ToolAnnotations(readOnlyHint=True, destructiveHint=False,
                                                              openWorldHint=False, idempotentHint=True))
def assistant_panes(session: str = Field(default="", description="tmux session name to limit to; '' = every session on this server"),
                    response_format: Literal["concise", "detailed"] = Field(default="concise", description="concise: last 3 transcript lines per pane; detailed: last 12")) -> PanesResult:
    """Inventory of every pane of every tmux session (list-panes -a) with its state. Call this first in every
    conversation and after every action. Each row carries `session`; the status table groups by session (a `session`
    column before `name`) and the status line counts across sessions.

    States: `running` (spinner or 'esc to interrupt' visible, even with a ❯ prompt; never type here), `done` (empty
    ❯ and the last message ends in run-agent's closing lines `/run-agent …` / `Without run-agent: claude --agent …`,
    or an evaluator verdict; eligible for `send`), `idle` (empty ❯, no closing lines; eligible for `send`),
    `waiting` (AskUserQuestion menu, permission dialog or y/n question; `question_kind` and `judgement` say whose it
    is), `trust` (folder trust / .mcp.json / hooks approval; `launch` answers these itself), `error` (429, overloaded, rate limit, usage
    limit, API error in the last 12 lines; see assistant_send retry text and assistant_schedule for usage limits),
    `idle-bash` (a shell with nothing running; `launch` may use it), `pet` (terminal-pet; never touch), `other`.
    `next_agent` on a done pane says what the pane expects next (worker after planner, evaluator after worker).
    `projects` has one row per project with an agent pane: `stage` (`worker running`, `evaluator waiting`,
    `worker stopped`, `evaluator next`, `stuck`, `finished`), `waits_on` (its agent, the operator, the user, a paused worker's scheduled job,
    nothing), `next_agent` (the agent to start now, '' when none) and `line`, the project said in words.
    `duplicates`: one plain line per project with two or more agent panes, project first; the older panes' ids are
    in that project's `older_panes`, and none is closed without a close order that names it. `suggestion` is Claude's own dim hint in a box (prompt_text stays '').
    `held_at_launch` says what a pane was just before the last launch into it.
    Example: assistant_panes() → every pane; assistant_panes(session="1", response_format="detailed") → 12 lines each.
    Outside tmux: in_tmux=false and an empty list; there is nothing to drive, which is what the user is told."""
    if not in_tmux():
        return PanesResult(session="", in_tmux=False, time_et=now_et(), panes=[],
                           note="not inside tmux: no panes to drive")
    n = 12 if response_format == "detailed" else 3
    rows = []
    held = _held_at_launch()
    ds = list_panes(session)
    steps = _project_steps(ds)
    for d in ds:
        d["held_at_launch"] = held.get(d["id"], "") if d["state"] not in ("pet", "idle-bash") else ""
        d["tail"] = [ln.strip()[:240] for ln in d["tail"][-n:]]
        rows.append(Pane(**{k: v for k, v in d.items() if k in Pane.model_fields}))
    note = "" if response_format == "detailed" else "tail shows the last 3 lines; response_format='detailed' gives 12"
    return PanesResult(session=my_session(), in_tmux=True, time_et=now_et(), panes=rows, note=note,
                       status_line=_status_line(steps), duplicates=_dups_safe(ds),
                       projects=[ProjectStep(**st) for st in steps])


def _and(items: list[str]) -> str:
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def _status_line(steps: list[dict]) -> str:
    """the status brief: what needs the user, then what runs, what stopped, what finished; empty parts left out"""
    count = {2: "Two", 3: "Three", 4: "Four", 5: "Five", 6: "Six"}
    out = []
    needs = [st["line"] for st in steps if st["waits_on"] == "the user"]
    if len(needs) == 1:
        out.append(f"One thing needs you: {needs[0]}.")
    elif needs:
        out.append(f"{count.get(len(needs), str(len(needs)))} things need you: " + "; ".join(needs) + ".")
    run = [st for st in steps if st["state"] == "running"]
    if run:
        agents = {st["agent"] for st in run}
        if len(run) > 1 and len(agents) == 1 and run[0]["agent"]:
            out.append(f"Running: {_and([st['name'] for st in run])}, {'both' if len(run) == 2 else 'all'} on their {run[0]['agent']}s.")
        else:
            out.append("Running: " + _and([f"{st['name']}'s {st['agent']}" if st["agent"] else st["name"] for st in run]) + ".")
    stopped = [st["line"] for st in steps if st["waits_on"] != "the user" and st["state"] in ("error", "waiting", "trust")]
    if stopped:
        out.append("Stopped: " + "; ".join(stopped) + ".")
    fin = [st for st in steps if st["waits_on"] != "the user" and st["state"] == "done"]
    if fin:
        out.append("Finished: " + _and([f"{st['name']}'s {st['agent']}" if st["agent"] else st["name"] for st in fin]) + ".")
    return "\n".join(out) or "No agent is open."


# ============================================================================ tool: assistant_projects
def _title(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for ln in f:
                if ln.startswith("#"):
                    return ln.lstrip("#").strip()[:160]
    except OSError:
        pass
    return ""


def _criteria(path: str) -> tuple[int, int]:
    """(met, unmet) from WORKER_NOTES.md checkbox lines / 'met' words"""
    met = unmet = 0
    try:
        for ln in open(path, encoding="utf-8", errors="replace"):
            t = ln.strip()
            if re.match(r"^[-*] \[[xX]\]", t) or re.match(r"^[-*] .*\b(met|verified|done)\b", t, re.I) and not re.search(r"\bnot (met|done|verified)\b", t, re.I):
                met += 1
            elif re.match(r"^[-*] \[ \]", t) or re.search(r"\bnot (met|done|verified)\b", t, re.I):
                unmet += 1
    except OSError:
        pass
    return met, unmet


def _verdict(path: str) -> str:
    try:
        for ln in open(path, encoding="utf-8", errors="replace"):
            m = re.search(r"\bverdict\b\s*[:\-—]?\s*(.+)", ln, re.I)
            if m:
                return m.group(1).strip()[:120]
    except OSError:
        pass
    return ""


def _mtime(p: str) -> float:
    try:
        return os.stat(p).st_mtime
    except OSError:
        return 0.0


def _fmt_ts(ts: float) -> str:
    if not ts:
        return ""
    try:
        from zoneinfo import ZoneInfo
        return datetime.datetime.fromtimestamp(ts, ZoneInfo("America/New_York")).strftime("%m-%d %-I:%M %p %Z")
    except Exception:  # noqa: BLE001
        return datetime.datetime.fromtimestamp(ts).strftime("%m-%d %H:%M")


def _repos() -> list[str]:
    out = []
    try:
        names = sorted(os.listdir(FILES))
    except OSError:
        return out
    for n in names:
        d = os.path.join(FILES, n)
        if os.path.isdir(os.path.join(d, ".git")):
            out.append(d)
    return out


AGENTS3 = ("planner", "worker", "evaluator")


def _root(cwd: str) -> str:
    """the project a folder belongs to: the nearest folder at or above it that holds `.git` (a worker started in
    `plans/` belongs to the repo, not to a project called plans); the folder itself when none does"""
    try:
        p = os.path.realpath(cwd)
    except OSError:
        return cwd
    q = p
    while q and q != os.path.dirname(q):
        if os.path.exists(os.path.join(q, ".git")):
            return q
        if q in (os.path.realpath(HOME), os.path.realpath(FILES)):
            break
        q = os.path.dirname(q)
    return p


def _pname(cwd: str) -> str:
    """how replies name a project: its repo root's folder name"""
    return os.path.basename(_root(cwd or "").rstrip("/")) or "a"


PAUSED_HEADS = ("Stopped at usage limit", "Waiting")


def _paused(path: str) -> tuple[str, str]:
    """(the paused heading, what the worker waits on) when the last `## ` heading of plans/WORKER_NOTES.md is
    `## Stopped at usage limit` or `## Waiting …`: the worker left on purpose and booked its own relaunch, so the
    project is not ready for its evaluator. ('', '') otherwise."""
    try:
        text = open(os.path.join(path, "plans", "WORKER_NOTES.md"), encoding="utf-8", errors="replace").read()
    except OSError:
        return "", ""
    heads = [(m.start(), m.group(1).strip()) for m in re.finditer(r"^## (.+)$", text, re.M)]
    if not heads or not heads[-1][1].startswith(PAUSED_HEADS):
        return "", ""
    pos, head = heads[-1]
    job = ""
    try:
        for jid in ra_jobs.pending():
            j = ra_jobs.load(jid)
            if j.get("cwd") and _root(j["cwd"]) == _root(path):
                job = f"scheduled job #{jid}, which starts its {j.get('agent') or 'worker'} at {ra_parse.fmt_et(j['run_at'])}"
                break
    except Exception:  # noqa: BLE001
        job = ""
    if not job:
        m = re.findall(r"scheduled #(\d+)", text[pos:])
        job = (f"scheduled job #{m[-1]} (named in its notes; not among the pending jobs now)" if m
               else "a relaunch its notes name no job for (assistant_jobs lists what is pending)")
    return head, job


def _verdict_next(v: str) -> str:
    """the agent an EVAL.md verdict calls for: worker, planner, '' (passed) or '?' (not readable)"""
    t = v.lower()
    if re.search(r"re-?run (the )?worker|doesn.?t work|does not work|\bfail|\bfix\b", t):
        return "worker"
    if re.search(r"re-?plan|not what i meant", t):
        return "planner"
    if re.search(r"\bpass|\bworks\b|\baccept|\bship", t):
        return ""
    return "?"


def _sent_back(path: str) -> int:
    """worker starts that followed an evaluator start, counted since the project's last planner start (launches.tsv)"""
    try:
        lines = open(LOG_TSV, encoding="utf-8").read().split("\n")
    except OSError:
        return 0
    n, after_eval = 0, False
    for ln in lines:
        c = ln.split("\t")
        if len(c) < 5 or not _same_dir(c[3], path):
            continue
        m = re.search(r"claude --agent (\S+)", c[4]) or re.match(r"\s*/run-agent\s+([\w.-]+)", c[4])
        a = m.group(1).strip("'\"") if m else ""
        if a == "planner":
            n, after_eval = 0, False
        elif a == "evaluator":
            after_eval = True
        elif a == "worker" and after_eval:
            n, after_eval = n + 1, False
    return n


def _file_next(path: str) -> tuple[str, str, bool]:
    """(next agent by the plan files, EVAL verdict when EVAL.md is newest, EVAL.md is newest)"""
    plans = os.path.join(path, "plans")
    tp, tn, te = (_mtime(os.path.join(plans, f)) for f in ("PLAN.md", "WORKER_NOTES.md", "EVAL.md"))
    if not tp:
        return "planner", "", False
    if te and te >= tn and te >= tp:
        v = _verdict(os.path.join(plans, "EVAL.md"))
        return _verdict_next(v), v, True
    if tn > tp:
        return "evaluator", "", False
    return "worker", "", False


def _project_step(path: str, panes: list[dict]) -> dict:
    """one project's place in the pipeline, from its plan files and its agent pane (`panes`: its agent panes)"""
    path = _root(path)
    name = _pname(path) or path
    nxt, verdict, evaluated = _file_next(path)
    head, job = _paused(path) if nxt == "evaluator" else ("", "")
    back = _sent_back(path)
    panes = _by_activity(panes) if panes else []
    d = panes[-1] if panes else None
    agent = (d or {}).get("agent") or ""
    st = (d or {}).get("state", "")
    if d and not agent and st == "done":            # no name on the pane: the closing line says who wrote it
        agent = ("evaluator" if d.get("ends_with") == "eval-verdict" or d.get("next_agent") == "planner"
                 else "worker" if d.get("next_agent") == "evaluator"
                 else ("evaluator" if evaluated else "planner") if d.get("next_agent") == "worker" else "")
    who = f"{name}'s {agent or 'agent'}"
    out = {"name": name, "path": path, "agent": agent, "state": st, "pane_id": (d or {}).get("id", ""),
           "older_panes": [x["id"] for x in panes[:-1]], "sent_back": back, "stuck": False, "verdict": verdict,
           "next_agent": "", "waits_on": "", "stage": "", "line": ""}

    def settle(from_evaluator: bool) -> None:
        if nxt == "?":
            out.update(stage="evaluator waiting", waits_on="the user",
                       line=f"{name}'s evaluator left a verdict that names no next step: {verdict or 'none written'}")
        elif nxt == "":
            out.update(stage="finished", waits_on="nothing", line=f"{name} is finished: the evaluator's verdict is {verdict or 'ship'}")
        elif nxt == "worker" and from_evaluator and back >= 2:
            out.update(stage="stuck", stuck=True, waits_on="the user",
                       line=f"{name} is stuck: its worker was sent back {back} times and the evaluator sent it back again"
                            + (f" ({verdict})" if verdict else ""))
        else:
            out.update(stage=f"{nxt} next", next_agent=nxt, waits_on="the operator",
                       line=(f"{who} finished; its {nxt} is next" if d else f"{name} has no agent open; its {nxt} is next"))

    if head and agent in ("worker", "") and st in ("", "done", "idle", "error"):
        how = "stopped at its usage limit" if head.startswith("Stopped") else "waiting on its own relaunch"
        out.update(agent=agent or "worker", stage="worker paused", next_agent="", waits_on=job,
                   line=f"{name}'s worker is paused ({how}) and comes back with {job}; its evaluator is not next yet")
    elif d is None:
        settle(evaluated)
    elif st == "running":
        out.update(stage=f"{agent or 'agent'} running", waits_on="its agent", line=f"{who} is running")
    elif st in ("waiting", "trust"):
        kind = d.get("question_kind", "")
        if d.get("judgement") or (st == "waiting" and kind not in ("permission", "trust")):
            what = "your verdict" if agent == "evaluator" else "your answer"
            out.update(stage=f"{agent or 'agent'} waiting", waits_on="the user", line=f"{who} is waiting on {what}")
        else:
            what = "a folder-trust prompt" if st == "trust" or kind == "trust" else "a permission prompt" if kind == "permission" else "a yes/no prompt"
            out.update(stage=f"{agent or 'agent'} waiting", waits_on="the operator", line=f"{who} is held at {what}")
    elif st == "error":
        err = re.sub(r"\s*Stopped\.?$", "", (d.get("error") or "an API error").strip(" ●•*")).strip(" .")[:80]
        if d.get("reset_text"):
            rt = d["reset_text"].strip(" .")
            line = f"{who} hit the usage limit, which resets at {re.sub(r'^resets?( at)? ', '', rt)}"
        else:
            line = f"{who} stopped on {err}"
        out.update(stage=f"{agent or 'agent'} stopped", waits_on="the operator", line=line)
    else:                                           # done or idle: the turn is over, the next stage can start
        if st == "done" and d.get("next_agent") in AGENTS3 and not (agent == "evaluator" and evaluated and nxt != "?"):
            nxt = d["next_agent"]
        if st == "idle" and agent == "planner" and nxt == "planner":
            out.update(stage="planner waiting", waits_on="the user", line=f"{who} is open and waiting for you to describe the project")
        elif st == "idle":
            out.update(stage=f"{agent or 'agent'} idle", next_agent=nxt if nxt in AGENTS3 else "", waits_on="the operator",
                       line=f"{who} is idle" + (f"; by its plan files the {nxt} is next" if nxt in AGENTS3 else ""))
        else:
            settle(evaluated or agent == "evaluator")
    return out


def _project_steps(ds: list[dict]) -> list[dict]:
    """a step row for every project that has an agent pane, in pane order"""
    groups: dict[str, list[dict]] = {}
    for d in ds:
        if _is_agent_pane(d):
            groups.setdefault(_root(d["cwd"]), []).append(d)
    return [_project_step(k, g) for k, g in groups.items()]


class Project(BaseModel):
    name: str
    path: str
    plan_title: str = Field(default="", description="first heading of plans/PLAN.md, '' when no plan")
    criteria_met: int = 0
    criteria_unmet: int = 0
    notes_newer_than_plan: bool = Field(default=False, description="WORKER_NOTES.md is newer than PLAN.md (a worker ran after this plan)")
    eval_verdict: str = Field(default="", description="the verdict line from plans/EVAL.md, '' when none")
    eval_newer_than_notes: bool = False
    panes: list[str] = Field(default_factory=list, description="pane ids (%N) whose cwd is inside this repo")
    pane_states: list[str] = Field(default_factory=list, description="state of each pane in `panes`, same order")
    stage: str = Field(default="", description="no-plan | planned | worked | evaluated — from which files exist and their order")
    step: str = Field(default="", description="where the project stands with its pane counted in: `<agent> running` | `<agent> waiting` | `<agent> stopped` | `<agent> idle` | `<agent> next` | `worker paused` (its notes end in `## Stopped at usage limit` or `## Waiting`: it booked its own relaunch) | `stuck` | `finished` (verdict ship)")
    next_agent: str = Field(default="", description="planner | worker | evaluator: the agent to start now; '' while one runs, while the user owes an answer, when stuck and when finished")
    waits_on: str = Field(default="", description="its agent | the operator | the user | the scheduled job of a paused worker | nothing")
    sent_back: int = Field(default=0, description="worker starts that followed an evaluator start since the last planner start")
    stuck: bool = Field(default=False, description="sent back by the evaluator after two restarts: no third restart without a new order")
    line: str = Field(default="", description="the project said in words, project and agent first")
    updated: str = Field(default="", description="newest of the three plan files, US Eastern")


class ProjectsResult(BaseModel):
    root: str
    time_et: str
    projects: list[Project]
    duplicates: list[str] = Field(default_factory=list, description="projects with two or more agent panes, the same lines as assistant_panes.duplicates")
    note: str = ""
    now: str = Field(default="The next thing you emit is the tool call the order needs, with no text in front of it; what you worked out from these "
                             "reads (which pane, what state) stays in your thinking. When the order needs no call, the reply.",
                     description="what follows the two reads; the same on every read, and the last field so it is read last")


@mcp.tool(name="assistant_projects", annotations=ToolAnnotations(readOnlyHint=True, destructiveHint=False,
                                                                 openWorldHint=False, idempotentHint=True))
def assistant_projects(response_format: Literal["concise", "detailed"] = Field(default="concise", description="concise: only repos with a plans/ folder or an open pane; detailed: every git repo under ~/files")) -> ProjectsResult:
    """Every git repo under ~/files with its plan title, worker criteria (met/unmet from plans/WORKER_NOTES.md),
    EVAL.md verdict, stage and the panes whose cwd is that repo. Call it with assistant_panes on every 'status'.
    `stage`: no-plan (nothing in plans/), planned (PLAN.md newest: ready for a worker), worked (WORKER_NOTES newer:
    ready for the evaluator), evaluated (EVAL.md newest: fix or replan). `step`, `next_agent`, `waits_on`, `sent_back`,
    `stuck` and `line` say where the project stands with its pane counted in. "start all the workers" = every done pane
    whose project is `planned`; "run the evaluator … that are done" = done panes whose project is `worked`.
    Example: assistant_projects() ; assistant_projects(response_format="detailed") lists repos with no plans too."""
    pane_map: dict[str, list[tuple[str, str]]] = {}
    agent_map: dict[str, list[dict]] = {}
    if in_tmux():
        for d in list_panes():
            for repo in _repos():
                if d["cwd"] == repo or d["cwd"].startswith(repo + "/"):
                    pane_map.setdefault(repo, []).append((d["id"], d["state"]))
                    if _is_agent_pane(d):
                        agent_map.setdefault(repo, []).append(d)
    rows = []
    for repo in _repos():
        plans = os.path.join(repo, "plans")
        pl, wn, ev = (os.path.join(plans, f) for f in ("PLAN.md", "WORKER_NOTES.md", "EVAL.md"))
        tp, tn, te = _mtime(pl), _mtime(wn), _mtime(ev)
        met, unmet = _criteria(wn)
        if not tp and not tn and not te:
            stage = "no-plan"
        elif te >= tn and te >= tp:
            stage = "evaluated"
        elif tn >= tp:
            stage = "worked"
        else:
            stage = "planned"
        st = _project_step(repo, agent_map.get(repo, []))
        pr = Project(name=os.path.basename(repo), path=repo, step=st["stage"], next_agent=st["next_agent"],
                     waits_on=st["waits_on"], sent_back=st["sent_back"], stuck=st["stuck"], line=st["line"], plan_title=_title(pl), criteria_met=met, criteria_unmet=unmet,
                     notes_newer_than_plan=tn > tp > 0, eval_verdict=_verdict(ev), eval_newer_than_notes=te > tn,
                     panes=[p for p, _ in pane_map.get(repo, [])], pane_states=[s for _, s in pane_map.get(repo, [])],
                     stage=stage, updated=_fmt_ts(max(tp, tn, te)))
        if response_format == "detailed" or stage != "no-plan" or pr.panes:
            rows.append(pr)
    note = "" if response_format == "detailed" else "repos without plans/ and without a pane are hidden; response_format='detailed' shows all"
    return ProjectsResult(root=FILES, time_et=now_et(), projects=rows, note=note, duplicates=_dups_safe() if in_tmux() else [])


# ============================================================================ shared: typing into a pane
def _pane_by_id(pane_id: str) -> dict | None:
    for r in _pane_rows():
        if r["id"] == pane_id or r["pane"] == pane_id:
            return r
    return None


def type_into(pane_id: str, text: str, enter: bool = True, clear: bool = False) -> dict:
    """[Ctrl-U to clear typed text,] send-keys -l (or load-buffer/paste-buffer for multiline), ~150 ms pause, Enter as
    its own send-keys, then re-capture and say whether the pane took it (screen changed and the text is not still
    sitting in the ❯ box)."""
    before = strip_ansi(tm("capture-pane", "-p", "-J", "-t", pane_id, "-S", "-60"))
    if clear:
        tm("send-keys", "-t", pane_id, "C-u")
        time.sleep(0.15)
    if "\n" in text:
        with tempfile.NamedTemporaryFile("w", delete=False, prefix="assistant-", suffix=".txt") as f:
            f.write(text)
        try:
            tm("load-buffer", "-b", "assistant", f.name)
            tm("paste-buffer", "-d", "-b", "assistant", "-p", "-t", pane_id)
        finally:
            os.unlink(f.name)
    else:
        tm("send-keys", "-t", pane_id, "-l", text)
    time.sleep(0.15)
    if enter:
        tm("send-keys", "-t", pane_id, "Enter")
        time.sleep(0.4)
    after = strip_ansi(tm("capture-pane", "-p", "-J", "-t", pane_id, "-S", "-60"))
    changed = after != before
    first = text.split("\n")[0].strip()
    still_in_box = any(PROMPT.match(ln) and PROMPT.match(ln).group(1).strip() == first and first
                       for ln in after.split("\n")[-8:]) if enter else False
    return {"accepted": bool(changed and not still_in_box) if enter else changed, "screen_changed": changed}


# ============================================================================ tool: assistant_send
class SendItem(BaseModel):
    pane_id: str
    pane: str = Field(default="", description="session:window.pane")
    state_before: str = Field(default="", description="state re-read right before typing")
    sent: bool
    accepted: bool = Field(default=False, description="after Enter the screen changed and the text left the ❯ box")
    reason: str = Field(default="", description="why nothing was typed (state, unknown pane)")
    cleared: str = Field(default="", description="text the user had typed into the ❯ box, removed with Ctrl-U before typing: a loss, said in the result's `say`")
    typed: str = Field(default="", description="the line this pane got when it differs from `text`: a bare `/run-agent <agent>` line gets the model and effort of the project's last launch of that agent appended (launches.tsv). Quoted when the user asks for details")
    note: str = Field(default="", description="'typed into a pane with <why>' (background work still running), 'queued behind the running turn' (spinner, allow_running), 'cleared: <text>' (typed text removed first)")
    answered: str = Field(default="", description="when a dialog was answered: `\"<question>\" → <option>`")
    question: str = Field(default="", description="when refused because the pane is on a dialog: its question")
    options: list[str] = Field(default_factory=list, description="when refused because the pane is on a dialog: its options (quote them to the user, or call again with answer=)")
    say: str = Field(default="", description="this pane's clause for the reply, project and agent first")


class SendResult(BaseModel):
    text: str
    sent: list[SendItem]
    refused: list[SendItem]
    replaced: list[str] = Field(default_factory=list, description="R1/R2: a `/run-agent` line starts an agent in the pane's project, so the project's other agent panes were ended first (one agent per project): each with state, menu, last line, transcript resumable: the detail behind `say`")
    say: str = Field(default="", description="the reply's clauses for this call, project and agent first, live work that was cut off and text of the user's that was cleared included: `badminton's worker is starting`. Pane names and ids stay in the items")
    time_et: str


@mcp.tool(name="assistant_send", annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=False,
                                                             openWorldHint=False, idempotentHint=False))
def assistant_send(pane_ids: list[str] | str = Field(description="pane ids (%N) or addresses (session:window.pane) from assistant_panes, e.g. [\"%5\", \"%7\"]"),
                   text: str = Field(description="exactly what to type, e.g. '/run-agent worker' or 'Retry: the API returned 429; continue the task from where it stopped, repeating nothing already done'. Multi-line text is pasted as one block."),
                   enter: bool = Field(default=True, description="press Enter after the text (a separate send-keys)"),
                   allow_running: bool = Field(default=False, description="also type into a pane whose turn is live (state running, why ''): Claude queues the text behind the running turn. Set only when the user named that pane or project in the directive; never for batch directives"),
                   self: bool = Field(default=False, description="the directive named the assistant's own pane as the target ('type X into your own pane'); without it the PreToolUse hook blocks a send into the pane this conversation runs in"),
                   answer: str = Field(default="", description="for a pane that is `waiting`/`trust` on a dialog: which option to take. '2' = option 2 (the key is pressed; Claude Code selects and submits on the digit), 'yes'/'no' = the first option starting with that word, 'y'/'n' for a shell (y/n) question, 'free' = the free-text option ('Type something.' / 'Other' / 'Chat about this') followed by `text` and Enter — how a directive reaches a pane sitting on a menu. Answer yourself: permission prompts (yes), trust, 'ready to proceed?'-style yes/no about the agent's own work, menus you can settle from facts (tmux, the screen). Never a judgement call (evaluator verdicts Works / Doesn't work / Not what I meant, design or preference questions): quote question + options to the user instead")) -> SendResult:
    """Type text into Claude panes that are `done` or `idle`, re-checking each pane's state immediately before typing.
    Text the user typed but did not send (`prompt_text`) is cleared first with Ctrl-U and named in `say` (it is lost); a dim autocomplete `suggestion` is not the user's and needs no clearing.
    An `error` pane with a ❯ box also takes text (the retry line below). A `running` pane whose `why` is set
    (turn ended, background shell/monitor/agent/task still running) takes text like `idle`, batch directives included;
    the item carries `note: typed into a pane with <why>`. A `running` pane with `why` '' (live spinner) is refused
    unless `allow_running=True`, which you pass only when the user named that pane or project; then the item says
    `queued behind the running turn`. A `/run-agent …` line starts an agent in the pane's project, so the project's
    other agent panes (running or waiting included) are ended first and listed in `replaced` (name, state, last line,
    `transcript resumable`): one agent per project, no question asked; when one of them will not close the line is
    refused naming that pane. Any other state (waiting, trust, idle-bash, pet, other) is refused with that
    state and nothing is typed there; a pane that changed state since your dry run is therefore refused, not retried. The text is sent
    literally (`#`, `!`, quotes unchanged), then ~150 ms later Enter as its own key. The result says per pane
    sent/refused and whether the pane accepted the line (screen changed, text left the input box).
    Directive mapping: "start all the workers" → text='/run-agent worker' to every done pane whose project is planned;
    "run the evaluator on phone for all workers that are done" → text='/run-agent evaluator "phone"' to done panes
    ending in worker closing lines; "replan X" → '/run-agent planner "Replan based on plans/EVAL.md"'. Append model /
    effort / time words verbatim ("/run-agent worker opus medium after window"); a bare `/run-agent <agent>` line gets the
    model and effort of that project's last launch of the agent appended (item `typed`, note `reused opus medium, …`).
    `say` holds the reply's clauses. Rate limits (state error with 429/overloaded/API error): send exactly
    'Retry: the API returned <error>; continue the task from where it stopped, repeating nothing already done', then
    wait 1, 5, 15 min between re-checks, at most 3 attempts, logging each; a usage limit ("resets at …") is not retried:
    assistant_schedule one job per pane at the reset time instead. Every send and answer is appended to
    ~/.cache/assistant-agent/launches.tsv (time ET, pane, agent, dir, text): a log, never read as truth.
    Example: assistant_send(pane_ids=["%5"], text='/run-agent evaluator "phone"')."""
    if isinstance(pane_ids, str):
        pane_ids = [x for x in re.split(r"[\s,]+", pane_ids) if x]
    if not pane_ids or not isinstance(pane_ids, list) or not all(isinstance(p, str) and p for p in pane_ids):
        raise ValueError("pane_ids must be a non-empty list of pane ids from assistant_panes, e.g. "
                         "assistant_send(pane_ids=[\"%5\"], text=\"/run-agent worker\")")
    if not in_tmux():
        raise ValueError("not inside tmux: there is no pane to type into")
    if not text and not answer:
        raise ValueError("text is empty; example: assistant_send(pane_ids=[\"%5\"], text=\"/run-agent worker\")")
    sent, refused, replaced = [], [], []
    LOSSES.clear()
    starts_agent = bool(re.match(r"^\s*/run-agent\b", text))

    def who(row: dict, d: dict | None = None) -> str:
        return f"{_pname(row['cwd'])}'s {(d or row).get('agent') or 'agent'}"
    for pid in pane_ids:
        row = _pane_by_id(pid)
        if row is None:
            refused.append(SendItem(pane_id=pid, sent=False, reason="no such pane; ids come from assistant_panes (e.g. %5 or 1:1.3)"))
            continue
        if starts_agent:
            # R1/R2: a /run-agent line starts an agent in this pane's project — its other panes end first
            _slot, rep, fail = takeover(row["cwd"], keep=row["id"])
            replaced += rep
            if fail:
                refused.append(SendItem(pane_id=row["id"], pane=row["pane"], sent=False,
                                        reason=f"not typed: {fail} runs the same project and did not close",
                                        say=f"{who(row)} got nothing: the project's other pane did not close"))
                continue
        d = _inspect(row)
        note = ""
        if d["state"] in ("waiting", "trust") and (d.get("options") or d.get("question")):
            if not answer:
                refused.append(SendItem(pane_id=row["id"], pane=row["pane"], state_before=d["state"], sent=False,
                                        question=d["question"], options=d["options"],
                                        reason=f"pane is {d['state']} on a dialog ({d['question_kind']}): {d['question']!r} — options "
                                               f"{d['options']}. Pass answer=N / 'yes' / 'free' (+text) to answer it, or quote it to the user",
                                        say=f"{who(row, d)} is on a question and took no text"))
                continue
            r = answer_dialog(row["id"], d, answer, text)
            if r["ok"]:
                sent.append(SendItem(pane_id=row["id"], pane=row["pane"], state_before=d["state"], sent=True, accepted=r["accepted"],
                                     answered=r["answered"], question=d["question"], options=d["options"], note=r.get("note", ""),
                                     say=f"{who(row, d)} had its {'folder-trust' if d['state'] == 'trust' else d.get('question_kind') or 'menu'} prompt answered"))
                _log_launch(row["id"], d.get("agent") or "answer", row["cwd"], f"answer {answer}: {text}")
            else:
                refused.append(SendItem(pane_id=row["id"], pane=row["pane"], state_before=d["state"], sent=False,
                                        question=d["question"], options=d["options"], reason=r["reason"],
                                        say=f"{who(row, d)} did not take the answer: {r['reason'][:80]}"))
            continue
        if d["state"] == "running" and d.get("why"):
            typable, note = True, f"typed into a pane with {d['why']}"
        elif d["state"] == "running" and allow_running:
            typable, note = True, "queued behind the running turn"
        else:
            typable = d["state"] in ("done", "idle") or (d["state"] == "error" and d.get("has_prompt"))
        if not typable:
            why = ("; its turn is live (spinner): pass allow_running=True only if the user named this pane"
                   if d["state"] == "running" else "; only done, idle, running-with-background-work or error panes with a ❯ box take text")
            refused.append(SendItem(pane_id=row["id"], pane=row["pane"], state_before=d["state"], sent=False,
                                    reason=f"pane is {d['state']}{why}",
                                    say=f"{who(row, d)} is {d['state']} and took no text"))
            continue
        cleared = d["prompt_text"]   # typed by the user, unsent: Ctrl-U first (a dim suggestion needs no clearing)
        if cleared:
            note = (note + "; " if note else "") + f"cleared: {cleared}"
        line = text
        m = re.match(r"^\s*/run-agent\s+([\w.-]+)\s*((?:\"[^\"]*\"|'[^']*')?)\s*$", text)
        if m:      # R16: no model or effort in the line, so the project's last launch of this agent supplies them
            lm, le, _src = _last_model(m.group(1), row["cwd"], transcript=False)
            if lm or le:
                line = " ".join(x for x in (text.strip(), lm, le) if x)
                note = (note + "; " if note else "") + f"reused {' '.join(x for x in (lm, le) if x)}, this project's last {m.group(1)} (launches.tsv)"
        r = type_into(row["id"], line, enter, clear=bool(cleared))
        proj = _pname(row["cwd"])
        if m:
            clause = f"{proj}'s {m.group(1)} is starting"
        elif text.startswith("Retry:"):
            clause = f"{who(row, d)} was told to retry"
        else:
            clause = f"{who(row, d)} got the line"
        if not r["accepted"] and enter:
            clause = f"{who(row, d)} did not take the line; it is still in its box"
        if cleared:
            clause += f", and your unsent text \"{cleared[:80]}\" was cleared from its box"
        sent.append(SendItem(pane_id=row["id"], pane=row["pane"], state_before=d["state"], sent=True, accepted=r["accepted"],
                             cleared=cleared, note=note, typed=line if line != text else "", say=clause))
        _log_launch(row["id"], d.get("agent") or "send", row["cwd"], line)
    log.info("send %r -> sent %d refused %d", text[:60], len(sent), len(refused))
    say = "; ".join([x.say for x in sent + refused if x.say] + LOSSES)
    return SendResult(text=text, sent=sent, refused=refused, replaced=replaced, time_et=now_et(), say=say)


def answer_dialog(pane_id: str, d: dict, answer: str, text: str) -> dict:
    """press the key(s) that answer the dialog on screen: option N as the digit (Claude Code selects and submits on
    it; Enter follows only if the menu is still up with N highlighted), 'free' = the free-text option's digit, then
    `text`, Enter; a (y/n) line gets y/n + Enter. Returns ok, answered ('\"question\" → option'), accepted."""
    opts = d.get("options") or []
    kind = d.get("question_kind") or ""
    a = (answer or "").strip().lower()
    q = d.get("question") or ""
    if kind == "yn":
        key = "y" if a in ("y", "yes", "1") else "n" if a in ("n", "no", "2") else ""
        if not key:
            return {"ok": False, "reason": f"answer {answer!r} is not y/n for {q!r}"}
        tm("send-keys", "-t", pane_id, "-l", key)
        time.sleep(0.15)
        tm("send-keys", "-t", pane_id, "Enter")
        time.sleep(0.5)
        return {"ok": True, "answered": f"\"{q}\" → {key}", "accepted": True}
    plain = [re.sub(r"^❯\s*", "", o) for o in opts]          # 'N. text'
    n = 0
    if a == "free":
        n = d.get("free_option") or 0
        if not n:
            return {"ok": False, "reason": f"no free-text option in {opts}; answer with a number"}
        if not text:
            return {"ok": False, "reason": "answer='free' needs text"}
    elif a.isdigit():
        n = int(a)
    elif a in ("yes", "no", "y", "n"):
        word = "yes" if a in ("yes", "y") else "no"
        n = next((int(o.split(".")[0]) for o in plain if re.match(rf"^\d+\.\s*{word}\b", o, re.I)), 0)
        if not n:
            return {"ok": False, "reason": f"no option starting with {word!r} in {opts}"}
    else:
        n = next((int(o.split(".")[0]) for o in plain if a in o.lower()), 0)
        if not n:
            return {"ok": False, "reason": f"answer {answer!r} matches no option in {opts}: pass its number"}
    if not any(int(o.split(".")[0]) == n for o in plain):
        return {"ok": False, "reason": f"no option {n} in {opts}"}
    chosen = next(o for o in plain if int(o.split(".")[0]) == n)
    chosen_text = chosen.split(".", 1)[1].strip()
    before = strip_ansi(tm("capture-pane", "-p", "-J", "-t", pane_id, "-S", "-60"))
    note = ""
    if d.get("unnumbered"):
        steps = n - (d.get("highlighted") or 1)
        for _ in range(abs(steps)):
            tm("send-keys", "-t", pane_id, "Down" if steps > 0 else "Up")
            time.sleep(0.15)
        time.sleep(0.3)
        row = _pane_by_id(pane_id)
        d2 = _inspect(row, 60) if row else {}
        if not (d2 and d2.get("question") == q and d2.get("highlighted") == n):
            return {"ok": False, "reason": f"cursor did not reach option {n} ({chosen_text}) in {opts}; nothing confirmed"}
        tm("send-keys", "-t", pane_id, "Enter")
        time.sleep(0.6)
        note = f"cursor moved {abs(steps)} to option {n}; Enter sent"
        after = strip_ansi(tm("capture-pane", "-p", "-J", "-t", pane_id, "-S", "-60"))
        row = _pane_by_id(pane_id)
        d3 = _inspect(row, 60) if row else {}
        gone = not (d3 and d3.get("state") in ("waiting", "trust") and d3.get("question") == q)
        return {"ok": True, "answered": f"\"{q}\" → {chosen_text}", "accepted": bool(after != before and gone), "note": note}
    tm("send-keys", "-t", pane_id, "-l", str(n))
    time.sleep(0.6)
    if a == "free" or (n == d.get("free_option") and text):
        tm("send-keys", "-t", pane_id, "-l", text)
        time.sleep(0.2)
        tm("send-keys", "-t", pane_id, "Enter")
        time.sleep(0.5)
        chosen_text = text
        note = f"typed through option {n} ({chosen.split('.', 1)[1].strip()})"
    else:
        row = _pane_by_id(pane_id)
        d2 = _inspect(row, 60) if row else {}
        if d2 and d2.get("state") in ("waiting", "trust") and d2.get("question") == q and d2.get("highlighted") == n:
            tm("send-keys", "-t", pane_id, "Enter")       # a dialog that only moves the cursor on the digit
            time.sleep(0.5)
            note = "digit moved the cursor; Enter sent"
    after = strip_ansi(tm("capture-pane", "-p", "-J", "-t", pane_id, "-S", "-60"))
    row = _pane_by_id(pane_id)
    d3 = _inspect(row, 60) if row else {}
    gone = not (d3 and d3.get("state") in ("waiting", "trust") and d3.get("question") == q)
    return {"ok": True, "answered": f"\"{q}\" → {chosen_text}", "accepted": bool(after != before and gone), "note": note}


def _log_launch(pane: str, agent: str, d: str, cmd: str, held: str = "") -> None:
    """append to launches.tsv (time ET, pane, agent, dir, command[, held: what the pane was just before a launch])"""
    try:
        os.makedirs(os.path.dirname(LOG_TSV), exist_ok=True)
        with open(LOG_TSV, "a", encoding="utf-8") as f:
            cols = [now_et(), pane, agent, d, cmd.replace("\t", " ").replace("\n", "⏎")]
            if held:
                cols.append(held.replace("\t", " ").replace("\n", "⏎"))
            f.write("\t".join(cols) + "\n")
    except OSError as e:
        log.warning("launches.tsv: %s", e)


# ============================================================================ tool: assistant_launch
STOP = {"a", "an", "the", "new", "for", "of", "project", "repo", "folder", "app", "in", "to", "on", "my", "called", "named"}


def _slug_words(phrase: str) -> tuple[list[str], list[str]]:
    """(idea words, sibling repo paths named in the phrase). Parentheticals name siblings ('same style as archery and
    curling'); a word that prefixes exactly one repo name is a sibling mention."""
    repos = {os.path.basename(r): r for r in _repos()}
    paren = " ".join(re.findall(r"\(([^)]*)\)", phrase))
    main = re.sub(r"\([^)]*\)", " ", phrase)
    sibs: list[str] = []
    for w in re.findall(r"[A-Za-z0-9]+", paren.lower()):
        hits = [r for n, r in repos.items() if n.lower().split("_")[0].split("-")[0] == w or n.lower() == w]
        if len(hits) == 1 and hits[0] not in sibs:
            sibs.append(hits[0])
    words = [w for w in re.findall(r"[A-Za-z0-9]+", main.lower()) if w not in STOP]
    return words, sibs


def _sep_for(sibs: list[str], words: list[str]) -> str:
    """underscore when the named siblings (or the repos sharing this idea's last word) use underscores, else hyphen"""
    names = [os.path.basename(x) for x in sibs]
    if not names and words:
        names = [os.path.basename(r) for r in _repos() if os.path.basename(r).lower().endswith(words[-1])]
    if names and all("_" in n or ("-" not in n) for n in names) and any("_" in n for n in names):
        return "_"
    return "-"


def resolve_project(project: str) -> dict:
    """{'path', 'slug', 'siblings', 'exists', 'is_repo', 'candidates', 'note'} for an absolute path or an idea phrase"""
    project = (project or "").strip()
    if not project:
        return {"path": "", "slug": "", "siblings": [], "exists": False, "is_repo": False, "candidates": [], "note": ""}
    if project.startswith(("/", "~")):
        path = os.path.abspath(os.path.expanduser(project))
        return {"path": path, "slug": os.path.basename(path), "siblings": [], "exists": os.path.isdir(path),
                "is_repo": os.path.isdir(os.path.join(path, ".git")), "candidates": [], "note": ""}
    words, sibs = _slug_words(project)
    sibnames = {os.path.basename(x) for x in sibs}
    words = [w for w in words if not any(n.lower().startswith(w) for n in sibnames)] or words
    # an existing repo whose name is the phrase itself (either separator) wins
    joined = "".join(words)
    exact = [r for r in _repos() if re.sub(r"[-_]", "", os.path.basename(r).lower()) == joined]
    if len(exact) == 1:
        return {"path": exact[0], "slug": os.path.basename(exact[0]), "siblings": sibs, "exists": True, "is_repo": True,
                "candidates": [], "note": "existing repo"}
    if len(exact) > 1:
        return {"path": "", "slug": "", "siblings": sibs, "exists": False, "is_repo": False, "candidates": exact,
                "note": "two repos spell this idea; ask which one"}
    sep = _sep_for(sibs, words)
    slug = sep.join(words) if words else ""
    path = os.path.join(FILES, slug) if slug else ""
    exists = bool(path) and os.path.isdir(path)
    is_repo = exists and os.path.isdir(os.path.join(path, ".git"))
    cands: list[str] = []
    note = ""
    if exists and not is_repo and os.listdir(path):
        cands = [path, os.path.join(FILES, slug + sep + "2"), os.path.join(FILES, ("-" if sep == "_" else "_").join(words))]
        note = f"{path} exists with unrelated content (not a git repo); ask which folder to use"
    return {"path": path, "slug": slug, "siblings": sibs, "exists": exists, "is_repo": is_repo, "candidates": cands, "note": note}


def _agent_model(agent: str, cwd: str, flags: list[str]) -> str:
    m = _flag(flags, "--model", "-m")
    if m:
        return m
    for d in (os.path.join(cwd, ".claude", "agents"), os.path.join(HOME, ".claude", "agents")):
        f = os.path.join(d, agent + ".md")
        try:
            for ln in open(f, encoding="utf-8"):
                if ln.startswith("model:"):
                    return ln.split(":", 1)[1].strip().strip("'\"")
        except OSError:
            continue
    return ""


def _pet_panes() -> list[tuple[dict, str]]:
    """(pane row, pet kind) for every pane showing a pet, on every tmux session"""
    out = []
    for r in _pane_rows():
        d = _inspect(r, 20)
        if d["state"] == "pet":
            out.append((r, d.get("pet") or "squid"))
    return out


def _free_pet() -> str:
    """the first of squid, cat, dog, capybara that no session runs; '' when all four are in use"""
    used = {p for _, p in _pet_panes()}
    return next((p for p in PETS if p not in used), "")


def _pet_cmd(pet: str) -> str:
    return "cd ~ && terminal-pet" if pet in ("squid", "") else f"cd ~ && terminal-pet --pet {pet}"


def fix_pets(dry: bool = False) -> list[str]:
    """one of each pet across all sessions: where two windows run the same pet, the later-created window's pet pane is
    restarted as an unused pet (its agent panes are not touched). Returns one clause per window."""
    out: list[str] = []
    try:
        pets = _pet_panes()
    except RuntimeError:
        return out
    used = {p for _, p in pets}
    seen: set[str] = set()
    for r, pet in sorted(pets, key=lambda x: (x[0]["win_id"], x[0]["index"])):
        if pet not in seen:
            seen.add(pet)
            continue
        where = f"{r['session']}:{r['window']}"
        new = next((p for p in PETS if p not in used), "")
        if not new:
            out.append(f"window {where} keeps a second {pet} (all four pets are in use)")
            continue
        used.add(new)
        if dry:
            out.append(f"window {where}'s second {pet} would restart as a {new}")
            continue
        tm("respawn-pane", "-k", "-c", PET_HOME, "-t", r["id"], _idle_shell_cmd())
        time.sleep(0.3)
        tm("send-keys", "-t", r["id"], "-l", _pet_cmd(new))
        tm("send-keys", "-t", r["id"], "Enter")
        out.append(f"window {where}'s second {pet} restarted as a {new}")
        log.info("fix_pets: %s %s -> %s", where, pet, new)
    if any("restarted" in x for x in out):
        time.sleep(0.8)
    return out


def _held(d: dict) -> dict:
    """what a pane holds, for the launch result and launches.tsv: process, cwd, agent, state, last screen line, and
    `words`, the reply's four-words-at-most form"""
    tail = d.get("tail") or []
    st = d.get("state", "")
    if st == "idle-bash":
        words = "an empty shell"
    elif d.get("process") == "claude":
        words = f"{_pname(d.get('cwd', ''))}'s {st} {d.get('agent') or 'claude'}"
    else:
        words = f"a running {d.get('process') or 'program'}"
    return {"process": d.get("process", ""), "cwd": tilde(d.get("cwd", "")), "agent": d.get("agent", ""), "state": st,
            "last_line": tail[-1].strip()[:120] if tail else "", "words": words}


def _held_text(h: dict) -> str:
    return (f"{h.get('words', '')}: process={h.get('process') or '-'} cwd={h.get('cwd') or '-'} agent={h.get('agent') or '-'} "
            f"state={h.get('state') or '-'} last={h.get('last_line', '')}")


def _free_for(d: dict, path: str) -> tuple[str, bool]:
    """('' when the inspected pane is free for a launch into `path`, else why not; whether a moment's wait could change
    it). Free: its state is idle-bash (nothing but the shell runs there: no claude, no other child) and the cwd is ~,
    ~/files or the launch's own project. The prompt character on screen plays no part: a shell whose prompt ends in a
    glyph this file has not heard of is as free as one ending in `$`. A shell sitting in another project's folder is
    that project's."""
    if d["id"] == _self_pane():
        return "it is my own pane", False
    if d["state"] != "idle-bash":
        what = d.get("agent") or d.get("process") or "something"
        return f"it holds a {d['state']} {what}", False
    cwd, proj = os.path.realpath(d["cwd"]), os.path.realpath(path)
    if cwd in {os.path.realpath(x) for x in (HOME, PET_HOME, FILES)} or cwd == proj or cwd.startswith(proj + os.sep):
        return "", False
    files = os.path.realpath(FILES)
    if cwd.startswith(files + os.sep):
        return f"its shell sits in {tilde(d['cwd'])}, which is {cwd[len(files) + 1:].split(os.sep)[0]}'s", False
    return f"its shell sits in {tilde(d['cwd'])}, not ~, ~/files or the project", False


def _check_free(pane_id: str, path: str) -> tuple[dict | None, str]:
    """re-read a pane right before typing into it: (inspected pane, why it is not free or ''). A shell that was just
    respawned gets up to 2 s to print its prompt."""
    d, why = None, "the pane is gone"
    for _ in range(8):
        row = _pane_by_id(pane_id)
        if row is None:
            return None, "the pane is gone"
        d = _inspect(row, 40)
        why, wait = _free_for(d, path)
        if not why or not wait:
            break
        time.sleep(0.25)
    return d, why


def _free_quarters(ds: list[dict], path: str = "") -> list[str]:
    """the places a launch or a move can go without touching anything in use: every idle shell of a pet window (free
    for `path` when given), every pet window with fewer than four panes, and a new window when a pet is unused"""
    out = []
    for s, w in sorted({(d["session"], d["window"]) for d in ds}):
        prs = _window_panes(ds, s, w)
        if not prs or prs[0]["state"] != "pet" or len(prs) > 4:
            continue
        for d in prs[1:]:
            if _is_shell(d) and (not path or not _free_for(d, path)[0]):
                out.append(_mention(d))
        if len(prs) < 4:
            out.append(f"a new quarter in window {s}:{w}")
    pet = _free_pet()
    if pet:
        out.append(f"a new window with the {pet} pet")
    return out


def _test_fail(name: str, pid: str) -> bool:
    """harness only: pane ids listed in the tmux global `name` stand for a step that does not land on that pane
    (there is no honest way to make tmux fail on demand), so the failure paths can be exercised"""
    if not os.environ.get("ASSISTANT_TEST_SOCKET"):
        return False
    try:
        v = tm("show-environment", "-g", name)
    except RuntimeError:
        return False
    return pid in v.split("=", 1)[-1].split(",")


def _test_hook(name: str, target: str = "") -> None:
    """harness only: a shell command in the tmux global `name` is run once at this point (e.g. something starts in the
    picked pane between pick and type), then the variable is removed"""
    if not os.environ.get("ASSISTANT_TEST_SOCKET"):
        return
    try:
        v = tm("show-environment", "-g", name)
    except RuntimeError:
        return
    if "=" not in v:
        return
    tm("set-environment", "-g", "-u", name)
    subprocess.run(["bash", "-c", v.split("=", 1)[1]], capture_output=True, env={**_env(), "TARGET": target})


SHOWN_SESSIONS: set[str] = set()     # sessions whose terminal window this server opened (the client attaches a moment later)


def _sessions_attached() -> dict[str, bool]:
    out = {}
    _pane_rows()                          # refreshes SESSION_ALIAS
    for ln in tm("list-sessions", "-F", "#{session_name}\t#{session_attached}").split("\n"):
        if ln.strip():
            n, a = ln.split("\t")
            c = _canon(n)                 # a grouped session counts as its first session, attached through either
            out[c] = out.get(c, False) or a not in ("", "0")
    return out


def _pick_slot(session: str, path: str, prefer: str = "", skip: tuple = ()) -> tuple[str, str, list[str]]:
    """placement for a launch into `path`: the first pet window with a free quarter. Order: `prefer` (the session an
    earlier launch of the same order opened), the assistant's own window, the rest of its session, other attached
    sessions, then detached ones (numeric names ascending). Returns ('bash', pane_id, skipped) for a free shell (see
    _free_for; never the pet's quarter or the assistant's own pane), ('split', window_target, skipped) for a window
    with fewer than 4 panes, ('new', '', skipped) when every pet window is full. `skipped` names each idle shell
    passed over and why."""
    att = _sessions_attached()
    others = sorted((x for x in att if x != session),
                    key=lambda x: (not att[x], not x.isdigit(), int(x) if x.isdigit() else 0, x))
    order = [session] + others
    if prefer and prefer in att:
        order = [prefer] + [x for x in order if x != prefer]
    rows = _pane_rows()
    me = _self_pane()
    mine = next((r for r in rows if r["id"] == me), None)
    skipped: list[str] = []
    for s in order:
        by_win: dict[int, list[dict]] = {}
        for r in rows:
            if r["session"] == s:
                by_win.setdefault(r["window"], []).append(r)
        own = mine["window"] if mine and mine["session"] == s else None
        for w in sorted(by_win, key=lambda w: (w != own, w)):
            prs = sorted(by_win[w], key=lambda x: (int(x["top"]), int(x["left"])))
            if len(prs) > 4 or _inspect(prs[0], 20)["state"] != "pet":
                continue
            if len(prs) < 4:
                return "split", f"={s}:{w}", skipped
            for r in prs[1:]:
                if r["id"] == me or r["id"] in skip:
                    continue
                d = _inspect(r, 40)
                if d["state"] != "idle-bash":
                    continue
                why, _wait = _free_for(d, path)
                if not why:
                    return "bash", r["id"], skipped
                skipped.append(f"{_mention(d)}: {why}")
    return "new", "", skipped


def _finished_pane(path: str) -> dict | None:
    """with all four pet windows full: the pane a launch may take. The oldest (by last activity) agent pane in a pet
    window whose state is done, else the oldest idle Claude pane with an empty box. Running, waiting, trust and error
    panes are not candidates."""
    ds = list_panes()
    cands = [d for d in ds if _is_agent_pane(d) and _is_pet_window(ds, d["session"], d["window"])
             and _root(d["cwd"]) != _root(path)]
    done = _by_activity([d for d in cands if d["state"] == "done"])
    idle = _by_activity([d for d in cands if d["state"] == "idle" and not d.get("prompt_text")])
    return (done or idle or [None])[0]


MODEL_WORD = r"(?:opus|sonnet|haiku|fable|claude-[\w.-]+)"
EFFORT_WORD = r"(?:low|medium|high|xhigh|max)"


def _last_model(agent: str, path: str, transcript: bool = True) -> tuple[str, str, str]:
    """(model, effort, source) of the project's last launch of `agent`: the newest launches.tsv row for that folder
    that starts the agent (a `claude --agent <agent>` command or a `/run-agent <agent>` line), else the model of the
    newest transcript when it is that agent's. ('', '', '') when the last launch named none."""
    try:
        lines = open(LOG_TSV, encoding="utf-8").read().split("\n")
    except OSError:
        lines = []
    for ln in reversed(lines):
        c = ln.split("\t")
        if len(c) < 5 or not _same_dir(c[3], path):
            continue
        text = c[4]
        m = re.search(r"claude --agent (\S+)(.*)", text)
        if m and m.group(1).strip("'\"") == agent:
            mm = re.search(r"--model[ =]['\"]?([\w.\[\]-]+)", m.group(2))
            me = re.search(r"--effort[ =]['\"]?(\w+)", m.group(2))
            return (mm.group(1) if mm else ""), (me.group(1) if me else ""), "launches.tsv"
        m = re.match(r"\s*/run-agent\s+([\w.-]+)(.*)", text)
        if m and m.group(1) == agent:
            rest = re.sub(r"\"[^\"]*\"|'[^']*'", " ", m.group(2))
            mm = re.search(rf"\b({MODEL_WORD})\b", rest)
            me = re.search(rf"\b({EFFORT_WORD})\b", rest)
            return (mm.group(1) if mm else ""), (me.group(1) if me else ""), "launches.tsv"
    if transcript:
        tr = latest_transcript(path)
        if tr and tr.get("agent") == agent and tr.get("model"):
            return tr["model"], "", "its newest transcript"
    return "", "", ""


def _held_at_launch() -> dict[str, str]:
    """pane id → `<time> <agent> for <project> went into <held>` from the newest launches.tsv row that recorded it"""
    out: dict[str, str] = {}
    try:
        lines = open(LOG_TSV, encoding="utf-8").read().split("\n")[-400:]
    except OSError:
        return out
    for ln in lines:
        c = ln.split("\t")
        if len(c) >= 6 and c[5].strip():
            out[c[1]] = f"{c[0]}: {c[2]} for {os.path.basename(c[3])} went into {c[5]}"[:300]
    return out


def _claude_json_load() -> tuple[str, dict]:
    try:
        raw = open(CLAUDE_JSON, encoding="utf-8").read()
    except OSError:
        return "", {}
    return raw, json.loads(raw)


def pretrust(path: str) -> dict:
    """set projects.<path>.hasTrustDialogAccepted (+ hooks key when the file uses it) with an atomic write after a
    JSON round-trip check; returns what changed"""
    if os.environ.get("ASSISTANT_PRETRUST", "1") == "0":
        return {"pretrusted": False, "keys": [], "note": "ASSISTANT_PRETRUST=0"}
    raw, data = _claude_json_load()
    if not raw:
        return {"pretrusted": False, "keys": [], "note": f"{CLAUDE_JSON} missing or unreadable"}
    if json.loads(json.dumps(data)) != data:
        return {"pretrusted": False, "keys": [], "note": "round-trip check failed; file left alone"}
    projects = data.setdefault("projects", {})
    uses_hooks = any(isinstance(v, dict) and "hasTrustDialogHooksAccepted" in v for v in projects.values())
    entry = projects.setdefault(path, {})
    keys = []
    if entry.get("hasTrustDialogAccepted") is not True:
        entry["hasTrustDialogAccepted"] = True
        keys.append("hasTrustDialogAccepted")
    if uses_hooks and entry.get("hasTrustDialogHooksAccepted") is not True:
        entry["hasTrustDialogHooksAccepted"] = True
        keys.append("hasTrustDialogHooksAccepted")
    if not keys:
        return {"pretrusted": True, "keys": [], "note": "already trusted"}
    indent = 2 if re.match(r"\{\n {2}\S", raw) else None
    out = json.dumps(data, indent=indent, ensure_ascii=False)
    if raw.endswith("\n"):
        out += "\n"
    d = os.path.dirname(CLAUDE_JSON) or "."
    fd, tmp = tempfile.mkstemp(prefix=".claude.json.", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(out)
    try:
        os.chmod(tmp, os.stat(CLAUDE_JSON).st_mode & 0o777)
    except OSError:
        pass
    os.replace(tmp, CLAUDE_JSON)
    return {"pretrusted": True, "keys": keys, "note": ""}


def answer_dialogs(pane_id: str, timeout: float = 20.0) -> dict:
    """poll the pane up to `timeout` s: answer trust / .mcp.json / hooks dialogs with their Yes option (cursor moved to
    it; the 2.1 folder-trust dialog highlights `No, exit` by default, so never a blind Enter); a
    permission prompt or AskUserQuestion is left for assistant_send(answer=); stop at a ❯ prompt. Returns trust_answered, final state, seconds."""
    t0 = time.time()
    answered = False
    state = "other"
    while time.time() - t0 < timeout:
        row = _pane_by_id(pane_id)
        if row is None:
            break
        d = _inspect(row, 40)
        state = d["state"]
        if state == "trust":
            if d.get("options"):
                r = answer_dialog(pane_id, d, "yes", "")
                if not r.get("ok"):
                    log.warning("trust dialog not answered: %s", r.get("reason"))
                    break
            else:
                tm("send-keys", "-t", pane_id, "Enter")       # legacy dialog: only `Yes, proceed` highlighted
            answered = True
            time.sleep(0.7)
            continue
        if state in ("idle", "done", "waiting", "error"):
            break
        time.sleep(0.5)
    return {"trust_answered": answered, "state": state, "seconds": round(time.time() - t0, 1)}


def _wrap(shown: str, cmd: list[str]) -> list[str]:
    """run cmd in a pane, then keep an interactive shell there so the pane survives claude's exit"""
    return ["bash", "-c", 'printf "running: %s\\n" "$1"; RUN_AGENT_FROM= "${@:3}"; exec "$2"', "assistant", shown,
            os.environ.get("SHELL") or "bash", *cmd]


class LaunchResult(BaseModel):
    launched: bool
    pane: str = Field(default="", description="session:window.pane of the new agent")
    pane_id: str = ""
    window_created: bool = False
    pet_pane: str = Field(default="", description="pane running the pet when a window was created")
    project: str = Field(default="", description="resolved absolute project path")
    project_created: bool = Field(default=False, description="folder was created and git-initialised now")
    siblings: list[str] = Field(default_factory=list, description="sibling repo paths named in the idea phrase; name them in the reply (they are not put in the prompt: the planner finds them when the user types the idea)")
    prompt: str = Field(default="", description="the prompt argument actually passed: '' = none (planner starts fresh), '.' = run-agent's default for worker/evaluator/helper, else the directive's words")
    command: str = Field(default="", description="the claude command line as typed/run")
    trust: dict = Field(default_factory=dict, description="pretrust keys written; trust_answered; final state; seconds")
    trust_answered: bool = False
    candidates: list[str] = Field(default_factory=list, description="when ambiguous: 2–3 folder names; nothing launched")
    resumed: dict = Field(default_factory=dict, description="resume=True: id (session id), agent, model, last_time_et, last_line, transcript path")
    done: bool = Field(default=True, description="false when the project's other pane could not be closed (named in note) or nothing launched")
    replaced: list[str] = Field(default_factory=list, description="R1/R2: the project's other agent panes ended first (one agent per project), each with its state, the menu it sat on, its last line and that its transcript is resumable; the new agent took the most recent one's quarter. The detail behind `say`")
    session_created: str = Field(default="", description="R5: the new tmux session made when every pet window was full ('' otherwise)")
    window: dict = Field(default_factory=dict, description="R5/R6: the terminal window step for session_created: opened, placed, below (rectangle), attach (command for the user when not shown), note (why not)")
    session: str = Field(default="", description="tmux session the agent landed in. One order, one window: pass it as `session` on the order's next assistant_launch so both land in the same window")
    held: dict = Field(default_factory=dict, description="what the pane held just before the launch: process, cwd, agent, state, last_line, and `words` (four words at most, project first: 'an empty shell', 'a new pane', \"skiing's done worker\"): given when the user asks for details")
    refused: list[str] = Field(default_factory=list, description="panes passed over or refused right before typing, each with why (a claude started there, its shell sits in another project's folder, no prompt on screen); nothing was typed into them")
    took: str = Field(default="", description="all four pet windows were full: the finished pane this launch closed and reused, with its project, state and last line (transcript resumable); `say` names the project")
    reused: str = Field(default="", description="the order named no model or effort, so the project's last launch of this agent supplied them, e.g. '--model opus --effort medium (from launches.tsv)'. Given when the user asks for details")
    off_screen: str = Field(default="", description="set when the agent landed in a session no terminal shows; `say` says so and the reply repeats it")
    free_quarters: list[str] = Field(default_factory=list, description="on a refusal: the empty shells and unfilled windows a launch could use instead")
    say: str = Field(default="", description="the reply's clauses for this launch, project and agent first: `badminton's worker is running`, then a new window, a pane taken from another project, live work cut off. Pane names and ids stay in their own fields")
    note: str = ""
    time_et: str = ""


def _slug(path: str) -> str:
    """Claude Code's project folder name under ~/.claude/projects: every non-alphanumeric character becomes '-'"""
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(path))


def latest_transcript(path: str) -> dict | None:
    """the newest interactive Claude Code transcript for a project folder: {id, agent, model, last_time_et, last_line,
    transcript}; headless runs (`claude -p`: user entries with entrypoint sdk-cli / promptSource sdk) are skipped"""
    folder = os.path.join(PROJECTS, _slug(path))
    try:
        files = sorted((os.path.join(folder, f) for f in os.listdir(folder) if f.endswith(".jsonl")), key=_mtime, reverse=True)
    except OSError:
        return None
    for f in files:
        agent = model = last_ts = last_line = ""
        headless = False
        users = 0
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                for ln in fh:
                    try:
                        d = json.loads(ln)
                    except ValueError:
                        continue
                    t = d.get("type")
                    if t == "agent-setting":
                        agent = d.get("agentSetting") or agent
                    elif t == "user":
                        users += 1
                        if d.get("entrypoint") == "sdk-cli" or d.get("promptSource") == "sdk":
                            headless = True
                            break
                        last_ts = d.get("timestamp") or last_ts
                    elif t == "assistant":
                        msg = d.get("message") or {}
                        model = msg.get("model") or model
                        last_ts = d.get("timestamp") or last_ts
                        for c in msg.get("content") or []:
                            if isinstance(c, dict) and c.get("type") == "text" and c.get("text", "").strip():
                                last_line = c["text"].strip().split("\n")[-1][:200]
        except OSError:
            continue
        if headless or not users:
            continue
        et = ""
        if last_ts:
            try:
                from zoneinfo import ZoneInfo
                et = datetime.datetime.fromisoformat(last_ts.replace("Z", "+00:00")).astimezone(
                    ZoneInfo("America/New_York")).strftime("%m-%d %-I:%M %p %Z")
            except ValueError:
                et = last_ts
        return {"id": os.path.basename(f)[:-6], "agent": agent, "model": model, "last_time_et": et, "last_line": last_line, "transcript": f}
    return None


@mcp.tool(name="assistant_launch", annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=False,
                                                               openWorldHint=False, idempotentHint=False))
def assistant_launch(agent: str = Field(description="agent name: planner | worker | evaluator | helper | …"),
                     prompt: str = Field(default="", description="'' (the default) = run-agent's rule: planner starts fresh with no prompt argument, worker/evaluator/helper get '.'. Pass text only when the directive dictates a prompt (quoted words, 'tell it …'); never the idea phrase itself"),
                     project: str = Field(default="", description="absolute path (~/files/x) or an idea phrase ('a new badminton simulator (same style as archery and curling)'); '' = the current folder"),
                     flags: str = Field(default="", description="extra claude flags verbatim, e.g. '--model opus --effort medium'"),
                     window: Literal["auto", "new", "new-wt"] = Field(default="auto", description="auto: first idle shell in a 2x2 window of this session, else a new 2x2 window with a pet; new: always a new window; new-wt: new window plus a Windows Terminal tab (term-open.sh), skipped while a game runs"),
                     session: str = Field(default="", description="one order, one window: the `session` an earlier assistant_launch of the same order returned; its window is tried first"),
                     resume: bool = Field(default=False, description="'reopen / bring back / resume <project>': run `claude --resume <id>` on the project's newest interactive transcript (headless `claude -p` runs skipped), with that transcript's agent and model; `agent` is only the fallback when the transcript names none. The result's `resumed` carries session id, agent, model, last message time (ET) and last line. launched=false + note when the project has no transcript"),
                     force: bool = Field(default=False, description="take an occupied pane: the project's own agent pane is replaced (ended with /exit, transcript resumable), and with every quarter in use the oldest finished pane is closed and reused. Only with confirmed=True. Without it a launch goes into an empty shell or is refused with the free quarters named"),
                     confirmed: bool = Field(default=False, description="set with force=True when the pane to be replaced is this project's own done or idle pane and the order is to start its next agent, or when the user's order names the pane or project to replace; the PreToolUse hook blocks force=True without it")) -> LaunchResult:
    """Start a Claude agent session in tmux: resolves the project (idea phrase → ~/files/<slug>, created with git init
    when missing; siblings named in the phrase are returned, not prompted), picks a pane, pre-trusts the folder in
    ~/.claude.json, runs `claude --agent <agent> [prompt] <flags> --name
    "<agent>: <folder> (<model>)"` — the prompt follows run-agent: none for the planner (fresh session, empty box),
    '.' for worker/evaluator/helper, the directive's own words only when it dictates them —
    then watches up to 20 s and answers any folder-trust / .mcp.json / hooks dialog with the highlighted Yes (never a
    permission prompt or AskUserQuestion). A launch goes only into a pane whose state is `idle-bash`, judged by that
    state and not by the prompt character on its screen: the first free shell of a pet window (the assistant's own
    window, other attached sessions, then detached ones, `off_screen` set), a new quarter in a window with fewer than
    four panes, or, with every pet window full and a pet unused, a new tmux session opened in a terminal window below
    the user's (`session_created`, `window`; when it cannot be opened or placed `say` says it is not on screen and
    why). Free means nothing but the shell runs there and its cwd is ~, ~/files or this project; a shell sitting in
    another project's folder is that project's and is passed over (`refused`). The pane is read again right before
    typing and refused if anything started there.
    An occupied pane is taken only with force=True, confirmed=True. Without them: a project that already has an agent
    pane (done, idle, running or waiting) gets launched=false, and so does a launch with every quarter in use and no
    pet left; `say` names what is open and the free quarters, `note` the step to take instead. With them: the
    project's own agent panes are ended (`/exit`, kill after 5 s), the most recent one's quarter is reused
    (`replaced`, and `say` carries any live work cut off), and with every quarter in use the oldest done pane (then an
    idle one with an empty box) of another project is closed and reused (`took`); running, waiting and trust panes of
    other projects are left alone. When a pane will not close: done=false, launched=false, `note` names it.
    With no model or effort in `flags` the project's last launch of the same agent supplies them (`reused`).
    `candidates` non-empty (nothing launched) means the folder is ambiguous or holds unrelated content: settle it
    from assistant_projects when one candidate is plainly meant, else ask once and call again with project=<absolute path>.
    Directive: "start a planner for a new badminton simulator (same style as archery and curling)" →
    assistant_launch(agent="planner", project="a new badminton simulator (same style as archery and curling)") — no
    prompt (`siblings` are the repos the user will mention to the planner). Launched agents keep their own model
    unless the directive names one ("opus medium" → flags="--model opus --effort medium")."""
    if not agent or not re.match(r"^[\w.-]+$", agent):
        raise ValueError("agent must be a name like planner, worker or evaluator; example: "
                         "assistant_launch(agent=\"planner\", project=\"a new badminton simulator\")")
    flag_list = shlex.split(flags) if flags else []
    res = resolve_project(project)
    if res["candidates"]:
        return LaunchResult(launched=False, done=False, candidates=res["candidates"], siblings=res["siblings"], note=res["note"], time_et=now_et())
    path = res["path"] or os.getcwd()
    created = False
    if not os.path.isdir(path):
        os.makedirs(path)
        created = True
    if not os.path.isdir(os.path.join(path, ".git")):
        subprocess.run(["git", "init", "-q", path], capture_output=True)
        created = True
    # run-agent's defaults: '.' for worker/evaluator/helper, no prompt argument for the planner (and any other agent)
    full_prompt = prompt if prompt else ("." if agent in ("worker", "evaluator", "helper") else "")
    resumed: dict = {}
    reused = ""
    if resume:
        tr = latest_transcript(path)
        if not tr:
            return LaunchResult(launched=False, project=path, project_created=created, siblings=res["siblings"], time_et=now_et(),
                                note=f"no interactive Claude transcript for {tilde(path)} under {tilde(PROJECTS)}/{_slug(path)}: "
                                     f"nothing to resume; start it fresh (assistant_launch without resume) and say so")
        agent = tr["agent"] or agent
        model = tr["model"]
        full_prompt = ""
        cmd = ["claude", "--resume", tr["id"]]
        if agent:
            cmd += ["--agent", agent]
        if model and not _flag(flag_list, "--model"):
            cmd += ["--model", model]
        cmd += flag_list
        resumed = {k: tr[k] for k in ("id", "agent", "model", "last_time_et", "last_line", "transcript")}
    else:
        if not _flag(flag_list, "--model") and not _flag(flag_list, "--effort"):
            lm, le, src = _last_model(agent, path)
            add = (["--model", lm] if lm else []) + (["--effort", le] if le else [])
            if add:
                flag_list += add
                reused = f"{' '.join(add)} (from {src}: this project's last {agent})"
        model = _agent_model(agent, path, flag_list)
        cmd = ["claude", "--agent", agent]
        if full_prompt:
            cmd.append(full_prompt)
        cmd += flag_list
        if not _flag(flag_list, "--name", "-n"):
            cmd += ["--name", f"{agent}: {os.path.basename(path)} ({model or 'default'})"]
    shown = " ".join(shlex.quote(x) for x in cmd)
    if not in_tmux():
        return LaunchResult(launched=False, project=path, project_created=created, siblings=res["siblings"], prompt=full_prompt,
                            command=f"cd {shlex.quote(path)} && {shown}", time_et=now_et(),
                            note="not inside tmux: nothing launched")
    trust = pretrust(path)
    prefer = session if isinstance(session, str) else ""
    session = my_session()
    NEW_SESSIONS.clear()
    pets_fixed = fix_pets()               # one of each pet before anything is placed
    # R1/R2: one agent per project — the project's other panes end first, the newest one's quarter is the slot
    LAST_TAKEN.clear()
    LAST_TOOK.clear()
    LOSSES.clear()
    take = bool(force is True and confirmed is True)
    proj = _pname(path)
    ds0 = list_panes()
    own = _project_panes(ds0, path)
    if own and not take:
        free = _free_quarters(ds0, path)
        has = _and([f"{_a(d['state'] + ' ' + (d.get('agent') or 'agent'))} in {d['name']}" for d in own])
        return LaunchResult(launched=False, done=False, project=path, project_created=created, siblings=res["siblings"],
                            prompt=full_prompt, command=shown, time_et=now_et(), free_quarters=free,
                            say=f"not launched: {proj} already has {has}, and a launch goes only into an empty shell; "
                                f"free quarters: {_and(free) if free else 'none'}",
                            note="Instead: when that pane is done or idle and the order is to start this project's next agent, call "
                                 "again with force=True, confirmed=True (the pane is replaced, its transcript stays resumable). "
                                 "A running or waiting pane is replaced only when the user's order names it. One project holds "
                                 "one agent, so the free quarters are for other projects.")
    slot, replaced, fail = takeover(path) if own else ("", [], "")
    if fail:
        return LaunchResult(launched=False, done=False, project=path, project_created=created, siblings=res["siblings"],
                            prompt=full_prompt, command=shown, replaced=replaced, time_et=now_et(),
                            note=f"not launched: {fail} did not close (still not an idle shell); tell the user which pane and its state")
    before = {r["id"]: (r["cwd"], r["pane"]) for r in _pane_rows()}
    refused: list[str] = []
    skip: list[str] = []
    held: dict = {}
    took = ""
    if slot:
        kind, target = "bash", slot
        if LAST_TAKEN:
            held = _held(LAST_TAKEN)
    elif window == "auto":
        kind, target, refused = _pick_slot(session, path, prefer)
    else:
        kind, target = "new", ""
    # a shell is read again right before typing: anything that started there since the pick means another pane
    while kind == "bash":
        _test_hook("ASSISTANT_TEST_BEFORE_TYPE", target)
        d, why = _check_free(target, path)
        if not why:
            held = held or _held(d)
            break
        refused.append(f"{_mention(d) if d else target}: {why}; nothing typed there")
        skip.append(target)
        held = {}
        kind, target, more = _pick_slot(session, path, prefer, tuple(skip))
        refused += [m for m in more if m not in refused]
    if kind == "new" and not _free_pet() and not take:
        fin = _finished_pane(path)
        return LaunchResult(launched=False, done=False, project=path, project_created=created, siblings=res["siblings"],
                            prompt=full_prompt, command=shown, refused=refused, time_et=now_et(), free_quarters=[],
                            say=f"not launched: every quarter is in use and all four pets have a window; free quarters: none",
                            note="Instead: close a finished pane on the user's order (assistant_layout close) and launch again"
                                 + (f", or, when the user's order says to make room, call again with force=True, confirmed=True: "
                                    f"{_mention(fin)}, {_pname(fin['cwd'])}'s {fin['state']} {fin.get('agent') or 'agent'}, would be closed and reused"
                                    if fin else "; no pane is finished, so nothing can be taken"))
    if kind == "new" and not _free_pet():
        # all four pets have a window and none has a free quarter: take a finished pane, never a live one
        ds = list_panes()
        fin = _finished_pane(path)
        ok = False
        if fin:
            took = _cut_off_line(fin)
            LAST_TOOK.update(fin)
            route, ok = _end_pane(fin, ds)
            took += f"; {route}"
        if not fin or not ok:
            why = (f"{_mention(fin)} did not close" if fin else
                   "all four pet windows are full and no pane is done or idle with an empty box (running, waiting and "
                   "trust panes are not taken)")
            return LaunchResult(launched=False, done=False, project=path, project_created=created, siblings=res["siblings"],
                                prompt=full_prompt, command=shown, replaced=replaced, refused=refused, time_et=now_et(),
                                note=f"not launched: {why}; say so and name what each window holds")
        kind, target = "bash", fin["id"]
        held = _held(fin)
    window_created = False
    pet_pane = ""
    wt_note = ""
    session_created = ""
    win_info: dict = {}
    if window == "new-wt":
        guard = subprocess.run([GAME_GUARD], capture_output=True, text=True)
        if guard.returncode == 0:
            wt_note = "Windows Terminal tab skipped: " + (guard.stdout.strip() or "a game is running") + "; "
        else:
            title = f"{agent}-{os.path.basename(path)}-{int(time.time()) % 10000}"
            r = subprocess.run([os.path.join(TOOLS, "term-open.sh"), title, PET_HOME], capture_output=True, text=True)
            if r.returncode == 0:
                session = title
                wt_note = f"Windows Terminal tab {title} opened; "
                first = tm("display", "-p", "-t", f"={session}:", "#{pane_id}")
                tm("send-keys", "-t", first, "-l", _pet_cmd(_free_pet()))
                tm("send-keys", "-t", first, "Enter")
                pet_pane = first
                kind, target = "split", f"={session}"
                window_created = True
            else:
                wt_note = "term-open.sh failed (" + (r.stdout + r.stderr).strip()[:120] + "); used a tmux window instead; "
    if kind == "bash":
        pane_id = target
        line = f"cd {shlex.quote(path)} && {shown}"
        tm("send-keys", "-t", pane_id, "-l", line)
        time.sleep(0.15)
        tm("send-keys", "-t", pane_id, "Enter")
    else:
        held = {"process": "", "cwd": "", "agent": "", "state": "", "last_line": "", "words": "a new pane"}
        if kind == "new":
            # R5: every pet window is full → a new tmux session with a pet window, shown below the user's terminal
            session, pet_pane = new_session_with_pet(f"{agent}: {os.path.basename(path)}")
            session_created = session
            win_info = open_terminal_below(session)
            target = f"={session}:"
            window_created = True
        # split the window's last pane so existing panes keep their index; pane 2 goes right of the pet, 3–4 tiled
        last = tm("list-panes", "-t", target, "-F", "#{pane_index} #{pane_id}").split("\n")
        last_id = sorted(last, key=lambda x: int(x.split()[0]))[-1].split()[1]
        n = len(last)
        pane_id = tm("split-window", "-d", "-h" if n == 1 else "-v", "-t", last_id, "-c", path, "-P", "-F", "#{pane_id}",
                     *_wrap(shown, cmd))
        if n >= 2:
            tm("select-layout", "-t", target, "tiled")
        win_idx = int(tm("display", "-p", "-t", pane_id, "#{window_index}"))
        ensure_quarters(session, win_idx)          # R1: a pet window always holds pet + 3 quarters (idle shells fill in)
    ans = answer_dialogs(pane_id)
    after = {r["id"]: (r["cwd"], r["pane"]) for r in _pane_rows()}
    moved = [k for k, v in before.items() if k in after and after[k][1] != v[1]]
    addr = tm("display", "-p", "-t", pane_id, "#{session_name}:#{window_index}.#{pane_index}")
    _log_launch(pane_id, agent, path, shown, _held_text(held))
    landed = addr.split(":")[0]
    off = ""
    if session_created and win_info.get("opened"):
        SHOWN_SESSIONS.add(session_created)       # its terminal window was opened by this server: on screen
    if not session_created and landed != my_session() and landed not in SHOWN_SESSIONS and not _sessions_attached().get(landed):
        off = f"off screen: session {landed} has no terminal attached"
    parts = [wt_note.strip("; ")] if wt_note.strip("; ") else []
    parts.append(_window_line(win_info) if session_created else ("created window" if window_created else f"used {kind} slot"))
    if replaced:
        parts.append(f"replaced {len(replaced)} pane(s) of this project (one agent per project)")
    if trust.get("keys"):
        parts.append(f"pre-trust wrote {trust['keys']}")
    if ans["trust_answered"]:
        parts.append(f"answered the trust dialog in {addr}")
    if moved:
        parts.append(f"WARNING pane addresses changed: {moved}")
    parts += pets_fixed
    note = "; ".join(parts)
    log.info("launch %s -> %s (%s)", agent, addr, note)
    say = f"{proj}'s {agent} is {'reopened' if resumed else 'running'}"
    if session_created:
        say += (" in a new window below yours" if win_info.get("placed")
                else f" in a new terminal window that was not placed below yours ({win_info.get('note') or 'not placed'})" if win_info.get("opened")
                else f" in a new session that is not on screen ({win_info.get('note') or 'no window opened'})")
    elif off:
        say += " in a session no terminal shows"
    if took and LAST_TOOK.get("cwd"):
        say += (f"; {_pname(LAST_TOOK['cwd'])}'s finished {LAST_TOOK.get('agent') or 'agent'} was closed to make room "
                f"and can be resumed")
    say = "; ".join([say] + LOSSES)
    return LaunchResult(launched=True, done=True, pane=addr, pane_id=pane_id, window_created=window_created, resumed=resumed,
                        pet_pane=tm("display", "-p", "-t", pet_pane, "#{session_name}:#{window_index}.#{pane_index}") if pet_pane else "",
                        project=path, project_created=created, siblings=res["siblings"], prompt=full_prompt, command=shown,
                        trust={**trust, **ans}, trust_answered=ans["trust_answered"], note=note.strip("; "), time_et=now_et(),
                        replaced=replaced, session_created=session_created, window=win_info, session=landed, held=held,
                        refused=refused, took=took, reused=reused, off_screen=off, say=say)


def tilde(p: str) -> str:
    return "~" + p[len(HOME):] if p == HOME or p.startswith(HOME + "/") else p


# ============================================================================ tool: assistant_layout
def _layout_checksum(s: str) -> str:
    c = 0
    for ch in s:
        c = ((c >> 1) + ((c & 1) << 15)) & 0xFFFF
        c = (c + ord(ch)) & 0xFFFF
    return "%04x" % c


def _layout_string(w: int, h: int, rows: list[list[str]]) -> str:
    """tmux window_layout for rows of pane ids: each row equal height, a 2-cell row split in equal halves"""
    k = len(rows)
    rh = (h - (k - 1)) // k
    parts = []
    y = 0
    for i, row in enumerate(rows):
        hh = rh if i < k - 1 else h - y
        ids = [p.lstrip("%") for p in row]
        if len(ids) == 1:
            parts.append(f"{w}x{hh},0,{y},{ids[0]}")
        else:
            cw = (w - (len(ids) - 1)) // len(ids)
            cells, x = [], 0
            for j, pid in enumerate(ids):
                ww = cw if j < len(ids) - 1 else w - x
                cells.append(f"{ww}x{hh},{x},{y},{pid}")
                x += ww + 1
            parts.append(f"{w}x{hh},0,{y}{{{','.join(cells)}}}")
        y += hh + 1
    body = parts[0] if k == 1 else f"{w}x{h},0,0[{','.join(parts)}]"
    return f"{_layout_checksum(body)},{body}"


def tidy_window(session: str, window: int) -> list[str]:
    """re-apply the quarters layout: pet top-left, then the other panes in their current positional order into top-right,
    bottom-left, bottom-right; a 5th+ pane gets its own full-width row below. A window without a pet is tiled."""
    ds = [d for d in list_panes(session) if d["window"] == window]
    if not ds:
        return []
    target = f"={session}:{window}"
    if len(ds) == 1:
        return [ds[0]["id"]]
    pos = sorted(ds, key=lambda x: (x["top"], x["left"]))
    pet = next((d for d in pos if d["state"] == "pet"), None)
    if pet is None:
        tm("select-layout", "-t", target, "tiled")
        return [d["id"] for d in pos]
    order = [pet["id"]] + [d["id"] for d in pos if d is not pet]
    rows = [order[:2]] if len(order) <= 2 else [order[:2], order[2:4]] + [[p] for p in order[4:]]
    w, h = ds[0]["win_w"], ds[0]["win_h"]
    tm("select-layout", "-t", target, _layout_string(w, h, rows))
    return order


class Move(BaseModel):
    pane_id: str
    from_name: str
    from_pane: str = Field(description="session:window.pane before the move")
    to_name: str
    to_window: int
    state: str = Field(default="", description="the pane's state when planned (running/waiting → needs_force)")
    last_line: str = Field(default="", description="its last screen line (for the yes/change/cancel table)")
    line: str = Field(description="`name (from) → name (to)` for the moves table")


class LayoutResult(BaseModel):
    action: str
    done: bool = Field(description="the action was carried out (false: refused or dry run)")
    dry_run: bool = False
    reason: str = Field(default="", description="why it was refused, '' when done")
    moves: list[Move] = Field(default_factory=list, description="panes moved (or, in a dry run, planned)")
    closed: list[str] = Field(default_factory=list, description="panes / windows ended, as `name (session:window.pane, %id) closed (exit)` / `closed (killed after 5 s)` or `window N`: the detail behind `say`")
    say: str = Field(default="", description="the reply's clauses for this call, project and agent first: what closed, how many panes moved, live work that was cut off. Pane names and ids stay in `moves`, `closed` and `panes`")
    reply_rule: str = Field(default="If the order needs another move or close, call it now and write nothing in between. The reply is written once, "
                                    "after the last call: `say` and little else, with nothing about later.",
                            description="how the reply to the user is written; the same on every layout call")
    windows: list[int] = Field(default_factory=list, description="windows touched (one phone picture each in phone mode)")
    needs_force: bool = Field(default=False, description="a running/waiting pane blocks the action. When the order named that pane, window or project, the order is the yes: call again with force=True, confirmed=True and say what was cut off")
    panes: list[Pane] = Field(default_factory=list, description="fresh assistant_panes rows for the touched windows after the action")
    skipped_self: str = Field(default="", description="set when the assistant's own pane sat in the swept window / fill-gaps source and was left alone")
    duplicates: list[str] = Field(default_factory=list, description="projects with two or more agent panes, as in assistant_panes; no layout action closes one of them unless a close order names it")
    new_sessions: list[str] = Field(default_factory=list, description="tmux sessions this call opened, each with whether its window is on screen")
    ambiguous: list[str] = Field(default_factory=list, description="when a bare name matched several panes: the candidates: settle from what the order and the panes say, else one AskUserQuestion")
    sessions: list[str] = Field(default_factory=list, description="tmux sessions touched")
    pets: list[str] = Field(default_factory=list, description="retile: windows that shared a pet, fixed so there is one of each (`window 2:1's second squid restarted as a dog`; agent panes untouched)")
    time_et: str = ""


def _self_pane() -> str:
    """the pane the assistant itself runs in (ASSISTANT_SELF_PANE overrides TMUX_PANE); '' when unknown"""
    return os.environ.get("ASSISTANT_SELF_PANE") or _env().get("TMUX_PANE", "")


def _find_pane(ds: list[dict], target: str, session: str = "") -> dict | None | list[dict]:
    """the pane for a %id, session:window.pane, or `name [in|@|/ [window] N] [in|@|/ session S]`; a bare name is looked
    up in `session` first (the assistant's own), then everywhere. Returns a list when the name is ambiguous."""
    t = (target or "").strip()
    m = re.match(r"^([\w-]+):(\d+\.\d+)$", t)
    if m:                                             # an address through a grouped session's name
        t = f"{_canon(m.group(1))}:{m.group(2)}"
    session = _canon(session) if session else session
    for d in ds:
        if t in (d["id"], d["pane"]):
            return d
    m = re.match(r"^([\w-]+)(?:\s*(?:@|in|/)\s*(?:window\s*)?(\d+))?(?:\s*(?:@|in|/)\s*(?:session\s*)?([\w-]+))?$", t, re.I)
    if not m:
        return None
    name, win, sess = m.group(1), m.group(2), m.group(3)
    sess = _canon(sess) if sess else sess
    hits = [d for d in ds if d["name"] == name and (win is None or d["window"] == int(win)) and (sess is None or d["session"] == sess)]
    if len(hits) > 1 and sess is None and session:
        mine = [d for d in hits if d["session"] == session]
        hits = mine or hits
    if len(hits) == 1:
        return hits[0]
    return hits if hits else None


def _one(ds: list[dict], target: str, session: str) -> dict | None:
    d = _find_pane(ds, target, session)
    return d if isinstance(d, dict) else None


def _win_of(ds: list[dict], target: str, session: str) -> tuple[str, int] | None:
    """(session, window) for 'N', 'window N', 'S:N', 'window N in session S', 'the dog window [in session S]' or a
    pane target; `session` is the session for bare numbers / pet names (the one the user named, else the assistant's)"""
    t = (target or "").strip()
    session = _canon(session) if session else session
    m = re.match(r"^(?:the\s+)?(squid|cat|dog|capybara)\s+window(?:\s*(?:in|@|/)\s*(?:session\s*)?([\w-]+))?$", t, re.I)
    if m:
        s = _canon(m.group(2) or session)
        wins = sorted({d["window"] for d in ds if d["session"] == s and d["state"] == "pet" and d.get("pet") == m.group(1).lower()})
        return (s, wins[0]) if wins else None
    m = re.match(r"^(?:window\s+)?(\d+)(?:\s*(?:in|@|/)\s*(?:session\s*)?([\w-]+))?$", t, re.I)
    if m:
        s, w = m.group(2) or session, int(m.group(1))
    else:
        m = re.match(r"^([\w-]+):(\d+)$", t)
        if m:
            s, w = m.group(1), int(m.group(2))
        else:
            d = _one(ds, t, session)
            return (d["session"], d["window"]) if d else None
    s = _canon(s)
    return (s, w) if any(d["session"] == s and d["window"] == w for d in ds) else None


def _mention(d: dict) -> str:
    return f"{d['name']} ({d['pane']}, {d['id']})"


def _busy(d: dict) -> bool:
    return d["state"] in ("running", "waiting")


def _pane_alive(pane_id: str) -> bool:
    return any(r["id"] == pane_id for r in _pane_rows())


def _shell_only(pane_pid: str) -> bool:
    """True when nothing but a shell runs under the pane (the program exited, the prompt is back)"""
    shells = {"bash", "zsh", "sh", "fish", "dash"}
    return all(c in shells for _, c, _ in _proc_tree(pane_pid)) if pane_pid else True


CLOSE_GRACE = float(os.environ.get("ASSISTANT_CLOSE_GRACE") or 5)


def _idle_shell_cmd() -> str:
    """the shell an empty quarter runs: tmux's default-command when set, else its default-shell / $SHELL"""
    for opt in ("default-command", "default-shell"):
        try:
            v = tm("show-options", "-gv", opt).strip()
        except RuntimeError:
            v = ""
        if v:
            return v
    return os.environ.get("SHELL") or "bash"


def _reset_pane(pane_id: str) -> None:
    """turn the pane into an idle shell at ~ keeping its %id: respawn-pane kills whatever ran there and starts the
    shell (an explicit command — without one tmux would re-run the pane's original command, the agent launch)"""
    tm("respawn-pane", "-k", "-c", PET_HOME, "-t", pane_id, _idle_shell_cmd())
    tm("set-option", "-p", "-t", pane_id, "-u", "remain-on-exit")
    tm("clear-history", "-t", pane_id)
    time.sleep(0.3)


def graceful_close(d: dict, force: bool = False, reset: bool = False) -> str:
    """end a pane the orderly way, whoever started it: a Claude pane gets Escape, Ctrl-U, `/exit`, Enter (Claude finishes
    writing its transcript, the shell prompt returns), then `exit`, Enter; a plain shell gets `exit` at once; a shell
    with a foreground program (force) gets Ctrl-C first. Polls every 0.5 s; the pane still there after CLOSE_GRACE
    seconds is killed with kill-pane. With reset=True the quarter is kept: once Claude has left (or at the deadline)
    the pane is respawned as an idle shell at ~ and keeps its %id. Returns the route: 'exit' or 'killed after N s'."""
    pid, ppid = d["id"], ""
    row = _pane_by_id(pid)
    if row:
        ppid = row["pane_pid"]
    t0 = time.monotonic()
    deadline = t0 + CLOSE_GRACE
    if reset:
        # a pane whose only process is Claude (no shell behind it) would vanish on /exit: keep it until the respawn
        tm("set-option", "-p", "-t", pid, "remain-on-exit", "on")

    def dead() -> bool:
        r = _pane_by_id(pid)
        return bool(r and r["dead"])

    if d.get("process") == "claude":
        tm("send-keys", "-t", pid, "Escape")
        time.sleep(0.15)
        tm("send-keys", "-t", pid, "C-u")
        time.sleep(0.1)
        tm("send-keys", "-t", pid, "-l", "/exit")
        time.sleep(0.15)
        tm("send-keys", "-t", pid, "Enter")
        exited = False
        while time.monotonic() < deadline:
            time.sleep(0.5)
            if not _pane_alive(pid):
                return "exit"
            if dead() or _shell_only(ppid):
                exited = True
                break
        if not exited:
            if reset:
                _reset_pane(pid)
            else:
                tm("kill-pane", "-t", pid)
            return f"killed after {int(CLOSE_GRACE)} s"
    elif d["state"] not in ("idle-bash",) and not _shell_only(ppid):
        tm("send-keys", "-t", pid, "C-c")       # a foreground program (vim, ssh, a build): only after force
        time.sleep(0.4)
    if reset:
        if _pane_alive(pid):
            _reset_pane(pid)
        return "exit"
    if _pane_alive(pid):
        tm("send-keys", "-t", pid, "C-u")
        time.sleep(0.1)
        tm("send-keys", "-t", pid, "-l", "exit")
        time.sleep(0.1)
        tm("send-keys", "-t", pid, "Enter")
    while time.monotonic() < deadline:
        time.sleep(0.5)
        if not _pane_alive(pid):
            return "exit"
    if _pane_alive(pid):
        tm("kill-pane", "-t", pid)
        return f"killed after {int(CLOSE_GRACE)} s"
    return "exit"


# ============================================================================ one agent per project (R1–R4)
def _same_dir(a: str, b: str) -> bool:
    try:
        return os.path.realpath(a) == os.path.realpath(b)
    except OSError:
        return a == b


def _is_agent_pane(d: dict) -> bool:
    """a Claude pane that belongs to a project: not a pet, not a bare shell, not the assistant's own pane"""
    return d.get("process") == "claude" and d["state"] not in ("pet", "idle-bash", "other") and d["id"] != _self_pane()


def _project_panes(ds: list[dict], path: str) -> list[dict]:
    return [d for d in ds if _is_agent_pane(d) and _root(d["cwd"]) == _root(path)]


def _activity(d: dict) -> float:
    """last activity of a pane: the mtime of its tty (updated on every write to the screen); 0 when unknown"""
    try:
        tty = tm("display", "-p", "-t", d["id"], "#{pane_tty}")
        return os.stat(tty).st_mtime if tty else 0.0
    except (RuntimeError, OSError):
        return 0.0


def _by_activity(ds: list[dict]) -> list[dict]:
    """oldest first"""
    return sorted(ds, key=lambda d: (_activity(d), d["session"], d["window"], d["index"]))


def _duplicate_groups(ds: list[dict]) -> list[list[dict]]:
    """agent panes sharing a project folder, each group oldest first (by last activity)"""
    groups: dict[str, list[dict]] = {}
    for d in ds:
        if _is_agent_pane(d):
            groups.setdefault(_root(d["cwd"]), []).append(d)
    return [_by_activity(g) for g in groups.values() if len(g) > 1]


def _dup_line(group: list[dict]) -> str:
    """`worker-building has two agents open: a running worker and an idle planner; the older is the worker.`"""
    n = {2: "two", 3: "three", 4: "four"}.get(len(group), str(len(group)))

    def what(d: dict) -> str:
        return f"{d['state']} {d.get('agent') or 'agent'}"
    return (f"{_pname(group[0]['cwd'])} has {n} agents open: " + _and([_a(what(d)) for d in group])
            + f"; the older is the {what(group[0])}.")


def _a(words: str) -> str:
    return ("an " if words[:1].lower() in "aeiou" else "a ") + words


def _loss(d: dict) -> str:
    """the clause for live work that was ended, project and agent first; '' when the pane was finished or idle"""
    who = f"{_pname(d.get('cwd', ''))}'s {d.get('agent') or 'agent'}"
    last = (d["tail"][-1].strip()[:90] if d.get("tail") else "")
    if d.get("state") == "running":
        return f"{who} was cut off mid-run" + (f" at \"{last}\"" if last else "") + "; its transcript can be resumed"
    if d.get("state") in ("waiting", "trust"):
        q = (d.get("question") or "").strip()[:90]
        return f"{who} was closed while it waited on " + (f"\"{q}\"" if q else "a prompt") + "; its transcript can be resumed"
    return ""


def _layout_say(said: list[str], moves: list, done: bool, dry: bool, needs_force: bool, reason: str, action: str) -> str:
    """the reply's clauses for a layout call; pane names and ids are stripped from a failure's reason"""
    parts = list(said)
    moves = [m for m in moves if m.pane_id]
    if moves and done and action != "close":
        parts.append(f"{len(moves)} pane{'s' if len(moves) != 1 else ''} moved")
    if not done and not dry and not needs_force:
        why = re.sub(r"\s*\([\w-]+:\d+\.\d+, %\d+\)", "", reason)
        parts.append("nothing needed moving" if why.startswith("nothing to do") else f"not done: {why}")
    if done and not parts:
        parts.append("the windows are in order")
    return "; ".join(parts + LOSSES)


LOSSES: list[str] = []      # loss clauses of the tool call in hand (takeover and close add to it)


def duplicates(ds: list[dict]) -> list[str]:
    return [_dup_line(g) for g in _duplicate_groups(ds)]


def _dups_safe(ds: list[dict] | None = None) -> list[str]:
    try:
        return duplicates(ds if ds else list_panes())
    except RuntimeError:
        return []


def _cut_off_line(d: dict) -> str:
    last = d["tail"][-1][:160] if d.get("tail") else ""
    s = f"{_mention(d)} {d.get('agent') or 'claude'} {d['state']}" + (f" ({d['why']})" if d.get("why") else "")
    if d["state"] in ("waiting", "trust") and d.get("question"):
        s += f"; was on the menu {d['question']!r}" + (f" {d['options']}" if d.get("options") else "")
    return s + f"; last line: {last}; transcript resumable (reopen {_pname(d['cwd'])})"


def _end_pane(d: dict, ds: list[dict]) -> tuple[str, bool]:
    """close one project pane for a takeover: in a pet window of 4 or fewer it is reset to an idle shell (the quarter
    keeps its place), elsewhere it is removed. Returns (route, ok): ok when the pane is a shell or gone afterwards."""
    if _test_fail("ASSISTANT_TEST_UNCLOSABLE", d["id"]):
        return "still " + d["state"] + " (did not close)", False
    prs = _window_panes(ds, d["session"], d["window"])
    reset = _is_pet_window(ds, d["session"], d["window"]) and len(prs) <= 4
    route = graceful_close(d, force=True, reset=reset)
    ok = False
    for _ in range(12):
        if not _pane_alive(d["id"]):
            ok = not reset
            break
        fresh = next((x for x in list_panes(d["session"]) if x["id"] == d["id"]), None)
        if fresh and fresh["state"] == "idle-bash":
            ok = True
            break
        time.sleep(0.25)
    return ("reset" if reset else "closed") + f" ({route})", ok


LAST_TOOK: dict = {}        # the finished pane of another project a launch closed and reused
LAST_TAKEN: dict = {}       # the pane takeover() reset as the slot, as it was before (the launch's `held`)


def takeover(path: str, keep: str = "") -> tuple[str, list[str], str]:
    """R1/R2: a project has one agent pane. Every agent pane whose cwd is `path` (other than `keep`) is ended; the
    most recently active one is reset in place and its id returned as the slot for the new agent (keep='' only).
    Returns (slot pane id or '', replaced lines, failure: the pane that would not close, '' when all went)."""
    ds = list_panes()
    others = [d for d in _project_panes(ds, path) if d["id"] != keep]
    if not others:
        return "", [], ""
    others = _by_activity(others)
    slot_d = None if keep else others[-1]
    if slot_d:
        LAST_TAKEN.update(slot_d)
    replaced, slot, fail = [], "", ""
    for d in others:
        if d is slot_d and _test_fail("ASSISTANT_TEST_UNCLOSABLE", d["id"]):
            route, ok = _end_pane(d, ds)
        elif d is slot_d:
            route = graceful_close(d, force=True, reset=True)
            ok = False
            for _ in range(12):
                fresh = next((x for x in list_panes(d["session"]) if x["id"] == d["id"]), None)
                if fresh and fresh["state"] == "idle-bash":
                    ok = True
                    break
                time.sleep(0.25)
            route = f"reset ({route})"
            if ok:
                slot = d["id"]
        else:
            route, ok = _end_pane(d, ds)
        replaced.append(_cut_off_line(d) + f"; {route}")
        if _loss(d):
            LOSSES.append(_loss(d))
        if not ok:
            fail = _mention(d)
    log.info("takeover %s: %d replaced, slot %s, fail %r", path, len(replaced), slot, fail)
    return slot, replaced, fail


# ============================================================================ a new tmux session in its own terminal window (R5/R6)
def _is_wsl() -> bool:
    if WT_EXE:
        return True
    try:
        return "microsoft" in open("/proc/version", encoding="utf-8").read().lower()
    except OSError:
        return False


def _next_session_name() -> str:
    names = set(tm("list-sessions", "-F", "#{session_name}").split("\n"))
    n = 1
    while str(n) in names:
        n += 1
    return str(n)


def _run(cmd: list[str], timeout: float = 20) -> tuple[int, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def _my_terminal_rect() -> tuple[str, list[int]]:
    """the user's terminal window: win.sh me → `me: HWND L T W H MAX`, else the foreground window (fginfo)"""
    for args in (["me"], ["fginfo"]):
        rc, out = _run([WIN_SH, *args], timeout=30)
        m = re.search(r"(\d+) (-?\d+) (-?\d+) (\d+) (\d+)", out.split("\n")[0] if out else "")
        if rc == 0 and m:
            return m.group(1), [int(x) for x in m.groups()[1:]]
    return "", []


def open_terminal_below(session: str) -> dict:
    """show tmux session `session` in a new Windows Terminal window (wt.exe -w new -p <profile> --title <session>
    ... tmux attach -t <session>, the restore-sessions form) placed directly below the user's terminal window, same
    width and height (win.sh place). Never raises: `opened`/`placed` false with `note` saying why, and `attach` the
    command that reaches the session by hand."""
    out = {"session": session, "opened": False, "placed": False, "attach": f"tmux attach -t {session}", "note": "", "below": ""}
    if not _is_wsl():
        out["note"] = "not WSL: no terminal window opened"
        return out
    wt = WT_EXE or shutil.which("wt.exe")
    if not wt:
        out["note"] = "wt.exe not found: no terminal window opened"
        return out
    rc, g = _run([GAME_GUARD, f"assistant: open session {session}"], timeout=30)
    if rc == 0:
        out["note"] = "deferred: " + (g.split("\n")[0] if g else "a game is running") + "; not shown on screen"
        return out
    hwnd_src, rect = _my_terminal_rect()
    sock = _tm_base()[1:]
    cmd = [wt, "-w", "new", "-p", WT_PROFILE, "--title", session, "--suppressApplicationTitle",
           "wsl.exe", "-d", os.environ.get("WSL_DISTRO_NAME") or "Ubuntu", "--", "tmux", *sock, "attach", "-t", f"={session}"]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as e:
        out["note"] = f"wt.exe failed ({e}); {out['attach']}"
        return out
    try:
        rc = proc.wait(timeout=1.0)        # real wt.exe returns 0 at once after spawning the window; a failure returns non-zero
    except subprocess.TimeoutExpired:
        rc = 0
    if rc:
        out["note"] = f"wt.exe exited {rc} without opening a window; {out['attach']}"
        return out
    out["opened"] = True
    for _ in range(int(WT_WAIT * 2)):
        try:
            if [ln for ln in tm("list-clients", "-F", "#{session_name}").split("\n") if ln == session]:   # no `-t =1`: bare numbers misresolve
                out["attached"] = True
                break
        except RuntimeError:
            pass
        time.sleep(0.5)
    hwnd = ""
    for _ in range(int(WT_WAIT * 2)):
        rc, f = _run([WIN_SH, "find", session], timeout=30)
        m = re.match(r"(\d+) ", f + " ")
        if rc == 0 and m and m.group(1) != hwnd_src:
            hwnd = m.group(1)
            break
        time.sleep(0.5)
    if not hwnd:
        out["note"] = f"window opened but win.sh did not find it (title {session}); not placed"
        return out
    _run([WIN_SH, "reg", hwnd, session])
    if not rect:
        out["note"] = "win.sh found no terminal window of yours to place it under; opened where Windows put it"
        return out
    left, top, w, h = rect
    rc, p = _run([WIN_SH, "place", hwnd, str(left), str(top + h), str(w), str(h)], timeout=30)
    if rc == 0:
        out["placed"] = True
        out["below"] = f"{left} {top + h} {w} {h} (under your window {left} {top} {w} {h})"
    else:
        out["note"] = f"win.sh place failed: {p[:120]}"
    return out


def new_session_with_pet(agent: str = "") -> tuple[str, str]:
    """R5: a new tmux session (next free numeric name) holding one pet window; returns (session, pet pane id)"""
    pet = _free_pet() or "squid"
    s = _next_session_name()
    tm("new-session", "-d", "-s", s, "-n", agent or "pet", "-c", PET_HOME, "-x", "200", "-y", "50")
    pet_pane = next(r["id"] for r in _pane_rows(s))             # list-panes -a filtered: `-t =1:` can misresolve a numeric name
    tm("send-keys", "-t", pet_pane, "-l", _pet_cmd(pet))
    tm("send-keys", "-t", pet_pane, "Enter")
    time.sleep(0.3)
    return s, pet_pane


def _window_line(w: dict) -> str:
    """the reply's sentence for a new session: `new session 1, opened below your window` or how to reach it"""
    if w.get("placed"):
        return f"new session {w['session']}, opened below your window"
    if w.get("opened"):
        return f"new session {w['session']}, opened in a new terminal window ({w['note'] or 'not placed'})"
    return f"new session {w['session']}, not shown on screen ({w['note']})"


def _window_panes(ds: list[dict], session: str, window: int) -> list[dict]:
    return sorted((d for d in ds if d["session"] == session and d["window"] == window), key=lambda x: (x["top"], x["left"]))


def _is_pet_window(ds: list[dict], session: str, window: int) -> bool:
    prs = _window_panes(ds, session, window)
    return bool(prs) and prs[0]["state"] == "pet"


def _is_shell(d: dict) -> bool:
    return d["state"] == "idle-bash" and d["id"] != _self_pane()


NEW_SESSIONS: list[dict] = []     # open_terminal_below results of this call (read into the layout / launch result)


def _new_pet_window(session: str, name: str = "pet") -> tuple[str, int]:
    """R5: a place beyond every pet window of `session` is a NEW tmux session (next free numeric name) with a pet
    window, shown in its own terminal window below the user's (never a detached window in the current session, which
    the user cannot see). Returns (new session name, window index). Call ensure_quarters after the first pane is in."""
    s, _ = new_session_with_pet(name)
    NEW_SESSIONS.append(open_terminal_below(s))
    return s, int(tm("display", "-p", "-t", f"={s}:", "#{window_index}"))


def _join_into(pane_id: str, session: str, window: int) -> None:
    """join a pane into a pet window's free quarter: an idle shell's place (the shell is killed) or a new split"""
    if _test_fail("ASSISTANT_TEST_FAIL_MOVE", pane_id):
        raise RuntimeError("tmux join-pane failed: the pane did not move")
    ds = list_panes(session)
    prs = _window_panes(ds, session, window)
    shells = [d for d in prs if _is_shell(d) and d is not prs[0]]
    if shells and len(prs) >= 4:
        sh = shells[-1]
        tm("join-pane", "-d", "-s", pane_id, "-t", sh["id"])
        tm("kill-pane", "-t", sh["id"])
    else:
        tm("join-pane", "-d", "-s", pane_id, "-t", _last_pane_id(session, window))
    tidy_window(session, window)


def place_pane(pane_id: str, session: str, exclude: tuple[str, int] | None = None, after: int = 0) -> tuple[str, int]:
    """R1 placement: the first pet window of `session` (index > after) with a free quarter — an idle shell or fewer
    than 4 panes — else a new tmux session with a pet window (R5); the pane is joined there. Returns (session, window)."""
    ds = list_panes(session)
    for w in sorted({d["window"] for d in ds}):
        if w <= after or (exclude and (session, w) == exclude):
            continue
        prs = _window_panes(ds, session, w)
        if not prs or prs[0]["state"] != "pet":
            continue
        if len(prs) < 4 or any(_is_shell(d) for d in prs[1:]):
            _join_into(pane_id, session, w)
            return session, w
    ns, w = _new_pet_window(session)
    tm("join-pane", "-d", "-h", "-s", pane_id, "-t", f"={ns}:{w}")
    ensure_quarters(ns, w)
    return ns, w


def ensure_quarters(session: str, window: int, keep: str = "") -> list[str]:
    """R1: a pet window ends with exactly 4 panes — missing quarters get an idle shell at ~, a 5th+ pane (never the
    pet, never `keep`/my own pane when another will do) is placed in the next window with a free quarter or a new pet
    window. Returns the lines of what moved. A window without a pet is only tidied."""
    out: list[str] = []
    ds = list_panes(session)
    prs = _window_panes(ds, session, window)
    if not prs:
        return out
    if prs[0]["state"] != "pet":
        tidy_window(session, window)
        return out
    me = _self_pane()
    while len(prs) > 4:
        extras = [d for d in prs[4:]] if len(prs) > 4 else []
        shells = [d for d in prs[1:] if _is_shell(d) and d["id"] != keep]
        if shells:                                  # a spare shell is just a gap: drop it, the agents stay
            tm("kill-pane", "-t", shells[-1]["id"])
            out.append(f"{_mention(shells[-1])} shell dropped (window had {len(prs)} panes)")
        else:
            cand = [d for d in extras if d["id"] not in (me, keep)] or [d for d in prs[1:] if d["id"] not in (me, keep) and d["state"] != "pet"]
            mv = cand[-1]
            place_pane(mv["id"], session, exclude=(session, window), after=window)
            fresh = {d["id"]: d for d in list_panes()}
            nd = fresh.get(mv["id"], mv)
            out.append(f"{_mention(mv)} → {nd['name']} ({nd['pane']})")
        ds = list_panes(session)
        prs = _window_panes(ds, session, window)
    while len(prs) < 4:
        tm("split-window", "-d", "-t", _last_pane_id(session, window), "-c", PET_HOME, _idle_shell_cmd())
        ds = list_panes(session)
        prs = _window_panes(ds, session, window)
    tidy_window(session, window)
    return out


def plan_retile(ds: list[dict], session: str) -> tuple[list[Move], list[int], list[Move]]:
    """simulate one session's retile: every pet window (ascending) pulls the newest agent pane (highest later window,
    highest index; never a pet, a shell or the assistant's own pane) into each free quarter (a shell counts as free);
    later windows left with pet + shells only close. Returns (moves, windows to close, moves of running/waiting panes)."""
    me = _self_pane()
    sim = {d["id"]: dict(d) for d in ds if d["session"] == session}
    moves, closed = [], []
    wins = sorted({d["window"] for d in sim.values()})
    for w in wins:
        prs = [d for d in sim.values() if d["window"] == w]
        if not prs:
            continue
        tl = min(prs, key=lambda x: (x["top"], x["left"]))
        if tl["state"] != "pet":
            continue
        theme = THEMES.get(tl.get("pet") or "squid", THEMES["squid"])
        while True:
            prs = [d for d in sim.values() if d["window"] == w]
            agents = [d for d in prs if d["state"] != "pet" and not _is_shell(d)]
            if len(agents) >= 3:
                break
            srcs = [d for d in sim.values() if d["window"] > w and d["state"] != "pet" and not _is_shell(d) and d["id"] != me]
            if not srcs:
                break
            src = max(srcs, key=lambda x: (x["window"], x["index"]))
            n = len(agents) + 1
            moves.append(Move(pane_id=src["id"], from_name=src["name"], from_pane=src["pane"], to_name=theme[n], to_window=w,
                              state=src["state"], last_line=(src["tail"][-1][:160] if src.get("tail") else ""),
                              line=f"{src['name']} ({src['pane']}, {src['id']}) → {theme[n]} ({session}:{w}.{n + 1})"))
            sw = src["window"]
            src.update(window=w, index=n + 1, top=10**6, left=10**6, name=theme[n], pane=f"{session}:{w}.{n + 1}")
            left = [d for d in sim.values() if d["window"] == sw]
            if left and min(left, key=lambda x: (x["top"], x["left"]))["state"] == "pet" and all(d["state"] == "pet" or _is_shell(d) for d in left):
                closed.append(sw)
                for d in left:
                    del sim[d["id"]]
    # windows that are already pet + shells only close too
    for w in wins:
        left = [d for d in sim.values() if d["window"] == w]
        if w not in closed and left and min(left, key=lambda x: (x["top"], x["left"]))["state"] == "pet" \
                and all(d["state"] == "pet" or _is_shell(d) for d in left) and w != min(wins):
            closed.append(w)
    busy = [m for m in moves if m.state in ("running", "waiting", "trust")]
    return moves, sorted(set(closed)), busy


plan_fill = lambda ds, session: plan_retile(ds, session)[:2]    # noqa: E731  (old name)


def _last_pane_id(session: str, window: int) -> str:
    rows = [r for r in _pane_rows(session) if r["window"] == window]
    return max(rows, key=lambda r: r["index"])["id"]


def _do_moves(session: str, moves: list[Move]) -> list[int]:
    touched = []
    for mv in moves:
        src_win = int(mv.from_pane.split(":")[1].split(".")[0])
        _join_into(mv.pane_id, session, mv.to_window)
        touched += [src_win, mv.to_window]
        still = [r for r in _pane_rows(session) if r["window"] == src_win]
        if still:
            tidy_window(session, src_win)
    fresh = {x["id"]: x for x in list_panes(session)}
    for mv in moves:
        nd = fresh.get(mv.pane_id)
        if nd:
            mv.to_name, mv.line = nd["name"], f"{mv.from_name} ({mv.from_pane}, {mv.pane_id}) → {nd['name']} ({nd['pane']})"
    return sorted(set(touched))


def _close_empty_pet_windows(session: str, wins: list[int]) -> list[str]:
    """kill windows holding only their pet (and idle shells); the first window of a session is kept. Highest index
    first: with `renumber-windows on` killing a lower window shifts the higher ones down and a later kill by the old
    index would hit the wrong window"""
    out = []
    for w in sorted(set(wins), reverse=True):
        ds = list_panes(session)
        all_w = sorted({d["window"] for d in ds})
        prs = _window_panes(ds, session, w)
        if prs and prs[0]["state"] == "pet" and all(d["state"] == "pet" or _is_shell(d) for d in prs) and (len(all_w) > 1):
            tm("kill-window", "-t", f"={session}:{w}")
            out.append(f"window {session}:{w} closed")
    return out


@mcp.tool(name="assistant_layout", annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=True,
                                                               openWorldHint=False, idempotentHint=False))
def assistant_layout(action: Literal["close", "move", "swap", "tidy", "retile", "fill-gaps"] = Field(description="close a pane (= reset its quarter to an idle shell) or a whole window; move a pane into another window (any session); swap two panes; tidy a window's layout (restores pet + 3 quarters); retile consolidates every tmux session (fill-gaps is the same action)"),
                     target: str = Field(default="", description="the pane: %id, session:window.pane (any tmux session, e.g. '1:1.2'), or a name with its window ('kelp in 1', 'coral@2', 'kelp in 1 in session 1'); for close/tidy also a window ('1:2', 'window 2', 'window 1 in session 1', 'the dog window'); '' for retile / tidy = every session"),
                     to: str = Field(default="", description="move: the destination window ('2', '1:2', 'window 1 in session 1', 'the dog window'); a bare number or pet name is looked up in `session` when given, else in the mover's session"),
                     slot: str = Field(default="", description="move: the destination quarter by name (kelp, coral, oyster…); '' = the next free one"),
                     other: str = Field(default="", description="swap: the second pane"),
                     force: bool = Field(default=False, description="close / retile a running or waiting pane anyway: when the user's order names that pane or its project, with confirmed=True; `say` then carries what was cut off"),
                     include_self: bool = Field(default=False, description="close: also end the assistant's own pane (the one this conversation runs in). Only when the directive names it outright ('close yourself', 'close the assistant', 'close window N' where it lives) and the user answered yes to `this closes me too`; a sweep never sets it"),
                     session: str = Field(default="", description="tmux session the directive named ('in session 1'): bare names / window numbers / pet names resolve there; retile / tidy with '' cover every session, a bare pane name with '' is looked up in the assistant's own session first"),
                     dry_run: bool = Field(default=False, description="retile: only plan (moves table + windows that would close); use it when the user asks what it would do, then call again without dry_run"),
                     confirmed: bool = Field(default=False, description="set with force=True when the user's order names the running/waiting pane or its project that would close or move (the order is the yes); the PreToolUse hook blocks force=True without it"),
                     self: bool = Field(default=False, description="alias of include_self: the directive named the assistant's own pane outright and the user said yes to `this closes me too`; the PreToolUse hook blocks a close of the own pane without it")) -> LayoutResult:
    """Keep every pet window at exactly pet + 3 quarters (an empty quarter is an idle shell at ~), across every tmux
    session. `close` on a pane RESETS its quarter: the Claude pane gets Escape, Ctrl-U, `/exit`, Enter (transcript
    written, resumable later), then `exit` once the shell is back, a pane still there after 5 s is killed, and the
    quarter is respawned (respawn-pane) as an idle shell with the same %id, cwd ~, so the window stays 2x2; the entry
    reads `kelp (1:1.2, %5) reset (exit)` or `reset (killed after 5 s)`. A pane outside a pet window, or a 5th+ pane,
    is removed instead (`closed (exit)`). `close` on a window ('1:2', 'window 1 in session 1', 'the dog window') ends
    every pane in it whatever it holds — pet only, pet + shells, pet + done agents — and kills the window: entries
    per pane plus `window 1:1 closed`; a session left with no windows is gone; done=false with the reason when nothing
    closed. `retile` (= 'tidy', 'tidy up', 'close the gaps', '2x2', fill-gaps) works over every session (or `session`):
    per session, agent panes move from later windows into earlier pet windows' free quarters (idle shells count as free
    and are replaced), windows left with pet + shells close, every remaining pet window gets missing shells and the
    quarters layout. Panes never cross sessions unless the directive names a destination session (`move` with
    to='1:1' / session='1' / to='the dog window' + session). It runs at once when only idle/done/error panes move;
    when a running or waiting pane would move it returns needs_force=true with those moves (state + last line in
    `moves`): moving keeps the process, so an order to retile is carried out with force=True, confirmed=True. reason 'nothing to do' = every window already
    matches. Moves keep the process (join-pane); nothing is restarted. Retile and tidy close no agent pane: two agent panes in one project are listed in `duplicates` and in `say`, and closing one takes a `close` that names it. Retile does its moves first and closes the windows left with pet + shells after; when a step fails it stops there, returns done=false and `say` names what moved, what did not and what was not attempted. A `move` returns done=true exactly when the pane ended in the window (and `slot`) asked for. `move`
    into a full window is refused with the free quarters named, and nothing moves. `swap` exchanges two panes;
    `tidy` restores a window's shape (shells into missing quarters, a 5th pane moved on) — with no target, every window.
    Rules enforced: a `pet` pane is never closed alone, moved or swapped (its window can be closed); closing or moving
    a `running`/`waiting`/`trust` pane needs force=True, confirmed=True (an order naming it is the yes); the
    assistant's own pane is skipped by sweeps (`skipped_self`) and refused with `this closes me too` until
    include_self=True. A name matching several panes comes back `ambiguous`. `done` is true only when tmux changed
    as the entries say; `say` holds the reply's clauses."""
    if not in_tmux():
        raise ValueError("not inside tmux: no panes to arrange")
    include_self = include_self or self
    LOSSES.clear()
    said: list[str] = []
    del confirmed   # checked by scripts/hooks/guard.py before the call reaches here
    NEW_SESSIONS.clear()
    ds = list_panes()
    explicit = _canon((session or "").strip())
    session = explicit or my_session()
    me = _self_pane()
    touched: list[int] = []
    moves: list[Move] = []
    closed: list[str] = []
    skipped_self = ""
    ambiguous: list[str] = []
    touched_sessions: set[str] = set()

    pets: list[str] = []

    def res(done: bool, reason: str = "", needs_force: bool = False, dry: bool = False) -> LayoutResult:
        panes = []
        fresh = []
        if done or dry:
            try:
                fresh = list_panes()
            except RuntimeError:
                fresh = []
            sess = touched_sessions or {session}
            for d in fresh:
                if d["session"] in sess and (not touched or d["window"] in touched):
                    d = dict(d, tail=[ln.strip()[:240] for ln in d["tail"][-3:]])
                    panes.append(Pane(**{k: v for k, v in d.items() if k in Pane.model_fields}))
        dups = _dups_safe(fresh or None)
        dup_said = ([x.rstrip(".") + ", and both stay open until a close order names one" for x in dups]
                    if action in ("retile", "fill-gaps", "tidy") and not needs_force else [])
        return LayoutResult(action=action, done=done, dry_run=dry, reason=reason, moves=moves, closed=closed,
                            windows=sorted(set(touched)), needs_force=needs_force, panes=panes, time_et=now_et(),
                            skipped_self=skipped_self, ambiguous=ambiguous, sessions=sorted(touched_sessions),
                            new_sessions=[_window_line(w) for w in NEW_SESSIONS],
                            say=_layout_say(said + dup_said, moves, done, dry, needs_force, reason, action),
                            duplicates=dups, pets=pets)

    def who(pane_id: str) -> str:
        d = next((x for x in ds if x["id"] == pane_id), None)
        if d is None:
            return pane_id
        return f"{_pname(d['cwd'])}'s {d.get('agent') or 'agent'} ({d['name']})" if d.get("process") == "claude" else f"the {d.get('process') or 'pane'} in {d['name']}"

    def close_one(d: dict, reset: bool) -> None:
        route = graceful_close(d, force, reset=reset)
        if d.get("process") == "claude":
            said.append(f"{_pname(d['cwd'])}'s {d.get('agent') or 'agent'} is closed")
            if _loss(d):
                LOSSES.append(_loss(d))
        closed.append(f"{_mention(d)} {'reset' if reset else 'closed'} ({route})")
        touched_sessions.add(d["session"])
        log.info("layout %s %s (%s)", "reset" if reset else "close", d["id"], route)

    if action == "close":
        is_win = re.match(r"^(?:[\w-]+:)?\d+$|^window\s+\d+|^(?:the\s+)?(squid|cat|dog|capybara)\s+window", target.strip(), re.I)
        if is_win:
            sw = _win_of(ds, target, session)
            if sw is None:
                return res(False, f"no window {target!r}" + (f" in session {session}" if explicit else "") +
                           "; windows come from assistant_panes (session:window)")
            s, win = sw
            prs = [d for d in ds if d["session"] == s and d["window"] == win]
            busy = [d for d in prs if _busy(d) or d["state"] == "trust"]
            if busy and not force:
                return res(False, "window %s:%d has %s; an order that names the window is the yes: force=True, confirmed=True, and say what was cut off" % (
                    s, win, ", ".join(f"{_mention(d)} {d['state']}" + (f" — {d['why']}" if d['why'] else "") for d in busy)), needs_force=True)
            mine = next((d for d in prs if d["id"] == me), None)
            if mine and not include_self:
                skipped_self = f"left my own pane alone: {_mention(mine)}"
            for d in [d for d in prs if d["state"] != "pet" and d is not mine and not _is_shell(d)]:
                close_one(d, reset=False)
            rest = [r for r in _pane_rows(s) if r["window"] == win]
            if mine and not include_self:
                touched = [win]
                touched_sessions.add(s)
                if rest and len(rest) > 1:
                    ensure_quarters(s, win)
                return res(True)
            if rest:
                left = {r["id"] for r in rest}
                for d in prs:                           # pets and idle shells go with the window: name each
                    if d["id"] in left and d is not mine:
                        closed.append(f"{_mention(d)} closed (window)")
                tm("kill-window", "-t", f"={s}:{win}")
            n_windows = len({d["window"] for d in ds if d["session"] == s})
            closed.append(f"window {s}:{win} closed" + (f" (session {s} gone)" if n_windows == 1 else ""))
            said.append("the window is closed")
            if mine and include_self:
                closed.append(f"{_mention(mine)} closed (window, last)")
            touched = []
            touched_sessions.add(s)
            log.info("layout close window %s:%d", s, win)
            still = [r for r in _pane_rows(s) if r["window"] == win]
            return res(not still, "" if not still else f"window {s}:{win} is still there")
        d = _find_pane(ds, target, session)
        if isinstance(d, list):
            ambiguous = [f"{_mention(x)} — {x['agent'] or x['process']}: {_pname(x['cwd'])}, {x['state']}" for x in d]
            return res(False, f"{target!r} matches {len(d)} panes: settle it from the order and the panes, else one AskUserQuestion")
        if d is None:
            return res(False, f"no pane {target!r}: use %id, session:window.pane or 'name in <window>' from assistant_panes")
        if d["state"] == "pet":
            return res(False, f"{_mention(d)} is the window's pet: never closed alone (close the window instead)")
        if (_busy(d) or d["state"] == "trust") and not force:
            return res(False, f"{_mention(d)} is {d['state']}" + (f" — {d['why']}" if d["why"] else "") +
                       f"; last line: {d['tail'][-1][:160] if d['tail'] else ''}. An order that names it is the yes: force=True, confirmed=True, and say what was cut off", needs_force=True)
        if d["id"] == me and not include_self:
            return res(False, f"{_mention(d)} is my own pane: this closes me too. Ask yes/no once (only if the order named "
                       f"me outright), then include_self=True; in a sweep it is skipped")
        s, win = d["session"], d["window"]
        if d["id"] == me:
            closed.append(f"{_mention(d)} closed (exit, last)")
            touched_sessions.add(s)
            tm("send-keys", "-t", d["id"], "Escape")
            tm("send-keys", "-t", d["id"], "C-u")
            tm("send-keys", "-t", d["id"], "-l", "/exit")
            tm("send-keys", "-t", d["id"], "Enter")
            touched = [win]
            return res(True)
        prs = _window_panes(ds, s, win)
        reset = _is_pet_window(ds, s, win) and len(prs) <= 4
        if d["state"] == "idle-bash" and reset:
            return res(False, f"{_mention(d)} is already an idle shell (an empty quarter); nothing to close")
        close_one(d, reset=reset)
        touched = [win]
        if [r for r in _pane_rows(s) if r["window"] == win]:
            ensure_quarters(s, win)
        ok = True
        if reset:
            ok = False
            for _ in range(12):                 # a real login shell takes a moment to print its prompt
                fresh = next((x for x in list_panes(s) if x["id"] == d["id"]), None)
                ok = bool(fresh and fresh["state"] == "idle-bash")
                if ok:
                    break
                time.sleep(0.25)
        return res(ok, "" if ok else f"{_mention(d)} did not come back as an idle shell")

    if action == "swap":
        a, b = _one(ds, target, session), _one(ds, other, session)
        if a is None or b is None:
            return res(False, f"unknown or ambiguous pane: {target!r} / {other!r}")
        if a["state"] == "pet" or b["state"] == "pet":
            return res(False, "a pet pane is never swapped")
        if a["id"] == b["id"]:
            return res(False, "same pane twice")
        mine = _self_pane()
        if mine in (a["id"], b["id"]) and not (include_self or self):
            x = a if a["id"] == mine else b
            return res(False, f"{_mention(x)} is the assistant's own pane (this conversation runs there): swap with another "
                              f"done or idle quarter of that window instead")
        tm("swap-pane", "-d", "-s", a["id"], "-t", b["id"])
        touched = sorted({a["window"], b["window"]})
        touched_sessions |= {a["session"], b["session"]}
        for x in (a, b):
            tidy_window(x["session"], x["window"])
        fresh = {d["id"]: d for d in list_panes()}
        for x, y in ((a, b), (b, a)):
            nx = fresh.get(x["id"], x)
            moves.append(Move(pane_id=x["id"], from_name=x["name"], from_pane=x["pane"], to_name=nx["name"], to_window=nx["window"],
                              line=f"{_mention(x)} → {nx['name']} ({nx['pane']})"))
        return res(True)

    if action == "move":
        d = _one(ds, target, session)
        if d is None:
            return res(False, f"no pane {target!r} (or the name matches several)")
        if d["state"] == "pet":
            return res(False, f"{_mention(d)} is the window's pet: never moved")
        if (_busy(d) or d["state"] == "trust") and not force:
            return res(False, f"{_mention(d)} is {d['state']}; last line: {d['tail'][-1][:160] if d['tail'] else ''}. "
                       f"An order that names it is the yes: force=True, confirmed=True, and say what was cut off", needs_force=True)
        sw = _win_of(ds, to, explicit or d["session"])
        if sw is None:
            return res(False, f"no window {to!r}" + (f" in session {explicit}" if explicit else "") + "; e.g. to='2', to='1:2', to='the dog window'")
        s, win = sw
        src_s, src_win = d["session"], d["window"]
        same = (s, win) == (src_s, src_win)
        if same and not slot:
            return res(False, f"{_mention(d)} is already in window {s}:{win}; use swap or slot=")
        dest = _window_panes(ds, s, win)
        dest_wid = dest[0]["win_id"]
        pet_win = dest[0]["state"] == "pet"
        if slot:
            theme = THEMES.get(dest[0].get("pet") or "squid", THEMES["squid"]) if pet_win else [""] + [x["name"] for x in dest]
            if pet_win and slot == theme[0]:
                return res(False, f"{slot} is the pet's quarter; nothing moved. Window {s}:{win} has the quarters {', '.join(theme[1:])}: pass one of those as slot")
            if slot not in theme[1:]:
                return res(False, f"no quarter named {slot!r} in window {s}:{win}; nothing moved. Its quarters are "
                                  f"{', '.join(theme[1:])}: pass one of those as slot, or leave slot empty for the next free one")
        if not same and pet_win and len(dest) >= 4 and not any(_is_shell(x) for x in dest[1:]):
            free = _free_quarters(ds)
            return res(False, f"window {s}:{win} is full; nothing moved. Free quarters: {_and(free) if free else 'none'}. "
                              f"Move it to one of those, or exchange it with a pane of that window (action='swap')")
        touched_sessions |= {s, src_s}
        nd = None
        try:
            if not same and pet_win:
                _join_into(d["id"], s, win)
                ensure_quarters(s, win, keep=d["id"])
            elif not same:
                if _test_fail("ASSISTANT_TEST_FAIL_MOVE", d["id"]):
                    raise RuntimeError("tmux join-pane failed: the pane did not move")
                tm("join-pane", "-d", "-s", d["id"], "-t", _last_pane_id(s, win))
                tidy_window(s, win)
            fresh = {x["id"]: x for x in list_panes()}
            nd = fresh.get(d["id"])
            if slot and nd and nd["win_id"] == dest_wid and nd["name"] != slot:
                occ = next((x for x in fresh.values() if x["win_id"] == dest_wid and x["name"] == slot), None)
                if occ is not None and occ["state"] != "pet" and occ["id"] != me:
                    tm("swap-pane", "-d", "-s", d["id"], "-t", occ["id"])
                    tidy_window(nd["session"], nd["window"])
                    fresh = {x["id"]: x for x in list_panes()}
                    nd = fresh.get(d["id"])
        except RuntimeError as e:
            row = _pane_by_id(d["id"])
            return res(False, f"the move of {who(d['id'])} failed ({e}); it is {'in ' + row['pane'] if row else 'gone'}. "
                              f"Read assistant_panes before any other step")
        if nd is None:
            return res(False, f"{who(d['id'])} is gone after the move; read assistant_panes before any other step")
        landed = nd["win_id"] == dest_wid and (not slot or nd["name"] == slot)
        moves.append(Move(pane_id=d["id"], from_name=d["name"], from_pane=d["pane"], to_name=nd["name"], to_window=nd["window"],
                          state=d["state"], line=f"{_mention(d)} → {nd['name']} ({nd['pane']})"))
        touched = sorted({src_win, nd["window"]} if nd["session"] == src_s else {nd["window"]})
        if not landed:
            return res(False, f"{who(d['id'])} is in {nd['pane']} as {nd['name']}, not {('the ' + slot + ' quarter of ') if slot else ''}"
                              f"window {s}:{win}; nothing else was changed. Read assistant_panes before any other step")
        if not same:
            try:                                  # the source window: closed when only its pet and shells are left
                if [r for r in _pane_rows(src_s) if r["window"] == src_win]:
                    closed += _close_empty_pet_windows(src_s, [src_win])
                    if [r for r in _pane_rows(src_s) if r["window"] == src_win]:
                        ensure_quarters(src_s, src_win)
            except RuntimeError as e:
                said.append(f"the window it left was not put back in order ({e})")
        return res(True)

    if action == "tidy":
        if target.strip():
            sw = _win_of(ds, target, session)
            if sw is None:
                return res(False, f"no window {target!r}")
            plan = [sw]
        else:
            sessions = [explicit] if explicit else sorted({d["session"] for d in ds})
            plan = [(s, w) for s in sessions for w in sorted({d["window"] for d in ds if d["session"] == s})]
        for s, w in plan:
            if not [r for r in _pane_rows(s) if r["window"] == w]:
                continue
            for line in ensure_quarters(s, w):
                pm = re.search(r"%\d+", line)
                moves.append(Move(pane_id=pm.group(0) if pm else "", from_name="", from_pane="", to_name="", to_window=w, line=line))
            touched_sessions.add(s)
            if len(plan) == 1:
                touched = [w]
        return res(True)

    # retile (fill-gaps is the same): moves first, then the windows left empty are closed. No agent pane is closed.
    sessions = [explicit] if explicit else sorted({d["session"] for d in ds})

    def plan_all(ds: list[dict]):
        all_moves: list[tuple[str, list[Move], list[int]]] = []
        busy_all: list[Move] = []
        for s in sessions:
            mv, to_close, busy = plan_retile(ds, s)
            all_moves.append((s, mv, to_close))
            busy_all += busy
        short = [(s, w) for s in sessions for w in sorted({d["window"] for d in ds if d["session"] == s})
                 if _is_pet_window(ds, s, w) and len(_window_panes(ds, s, w)) != 4
                 and w not in next(tc for ss, _, tc in all_moves if ss == s)]
        return all_moves, busy_all, short

    for s in sessions:
        if me and any(d["id"] == me and d["session"] == s and d["window"] > min(x["window"] for x in ds if x["session"] == s)
                      and d["state"] != "pet" for d in ds):
            skipped_self = "left my own pane alone"
    all_moves, busy_all, short_wins = plan_all(ds)
    moves = [m for _, mv, _ in all_moves for m in mv]
    touched_sessions |= set(sessions)
    if busy_all and not force:
        moves = busy_all
        return res(False, "retile would move running/waiting panes: " + "; ".join(
            f"{m.from_name} ({m.from_pane}) {m.state} — {m.last_line}" for m in busy_all) +
            ". A move keeps the process running. Retile was the order: call again with force=True, confirmed=True", needs_force=True)
    if dry_run:
        touched = sorted({m.to_window for m in moves} | {int(m.from_pane.split(":")[1].split(".")[0]) for m in moves})
        closed = [f"window {s}:{w} would close" for s, _, tc in all_moves for w in tc]
        pets[:] = fix_pets(dry=True)
        return res(False, "dry run: the moves table shows what would happen" if (moves or closed or short_wins or pets) else "nothing to do", dry=True)
    pets[:] = fix_pets()
    if not moves and not any(tc for _, _, tc in all_moves) and not short_wins:
        if pets:
            return res(True)
        return res(False, "nothing to do: every pet window already has pet + 3 quarters")
    moved: list[Move] = []
    failed: list[str] = []
    pending: list[Move] = []
    for s, mv, to_close in all_moves:
        if failed:                               # after a failed step nothing further is moved or closed
            pending += mv
            continue
        for i, m in enumerate(mv):
            src_win = int(m.from_pane.split(":")[1].split(".")[0])
            try:
                _join_into(m.pane_id, s, m.to_window)
                if [r for r in _pane_rows(s) if r["window"] == src_win]:
                    tidy_window(s, src_win)
                row = _pane_by_id(m.pane_id)
                if row is None:
                    raise RuntimeError("the pane is gone")
                if (row["session"], row["window"]) != (s, m.to_window):
                    raise RuntimeError(f"it is in {row['pane']}, not in window {s}:{m.to_window}")
            except RuntimeError as e:
                failed.append(f"{who(m.pane_id)} ({e})")
                pending += mv[i + 1:]
                break
            moved.append(m)
            touched += [src_win, m.to_window]
        if failed:
            continue
        try:
            closed += _close_empty_pet_windows(s, to_close)
            for w in sorted({d["window"] for d in list_panes(s)}):
                if _is_pet_window(list_panes(s), s, w):
                    for line in ensure_quarters(s, w):
                        moves.append(Move(pane_id="", from_name="", from_pane="", to_name="", to_window=w, line=line))
        except RuntimeError as e:
            failed.append(f"the windows of session {s} were not put in order ({e})")
    try:
        fresh_by = {x["id"]: x for x in list_panes()}
    except RuntimeError:
        fresh_by = {}
    for m in moved:
        nd = fresh_by.get(m.pane_id)
        if nd:
            m.to_name, m.line = nd["name"], f"{m.from_name} ({m.from_pane}, {m.pane_id}) → {nd['name']} ({nd['pane']})"
    touched = sorted(set(touched)) if len(sessions) == 1 else []
    log.info("layout retile: %d moved, %d failed, closed %s", len(moved), len(failed), closed)
    if failed:
        return res(False, "; ".join(x for x in [
            ("moved: " + _and([who(m.pane_id) for m in moved])) if moved else "nothing moved",
            "did not move: " + _and(failed),
            ("not attempted: " + _and([who(m.pane_id) for m in pending])) if pending else "",
            "no agent pane was closed and nothing further was done"] if x))
    return res(True)


# ============================================================================ tools: assistant_schedule / assistant_jobs
def _ra_env(pane_id: str, human: bool) -> dict:
    env = _env()
    if pane_id:
        env["TMUX_PANE"] = pane_id
    if human:
        env["RUN_AGENT_HUMAN"] = "1"
    env.pop("RUN_AGENT_FROM", None)
    return env


class ScheduleResult(BaseModel):
    scheduled: bool
    line: str = Field(description="the `scheduled #N: … at <time ET> (…)` line exactly as run-agent prints it")
    job_id: int = 0
    pane_id: str = Field(default="", description="the pane the job will respawn at fire time ('' = a new window)")
    run_at_et: str = ""
    command: str = ""
    project: str = ""
    say: str = Field(default="", description="the reply's clause for this job, used word for word and joined with the "
                                             "other jobs' into one sentence: `#2 starts planner-building's worker at 8:00 PM`")
    note: str = ""


@mcp.tool(name="assistant_schedule", annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=False,
                                                                 openWorldHint=False, idempotentHint=False))
def assistant_schedule(agent: str = Field(description="planner | worker | evaluator | …"),
                       prompt: str = Field(default="", description="the agent's prompt, verbatim; '' = its default ('.' for worker/evaluator)"),
                       project: str = Field(default="", description="absolute path or idea phrase; '' = the pane's cwd (or the current folder)"),
                       flags: str = Field(default="", description="claude flags verbatim, e.g. '--model opus --effort medium'"),
                       at: str = Field(default="after window", description="when, in run-agent's words: 'after window' / 'after the window resets', 'at 3pm', 'in 2 hours', 'tomorrow 9am'"),
                       pane_id: str = Field(default="", description="pane (%N) that the run replaces when it fires: the done pane the directive targets. '' = open a new tmux window at fire time")) -> ScheduleResult:
    """Schedule a run for later through the production run-agent scheduler (one `scheduled #N` job; `assistant_jobs`
    lists and cancels). "start all the workers after the window resets" = one call per target pane with its pane_id;
    the reply shows every `scheduled #N` line. A usage-limit pane ("usage limit reached … resets at 3pm") gets one job
    with at="at 3pm" and pane_id=that pane. Times in the line are US Eastern. Example:
    assistant_schedule(agent="worker", project="~/files/curling_simulator", at="after window", pane_id="%7")."""
    if not agent or not re.match(r"^[\w.-]+$", agent):
        raise ValueError("agent must be a name like worker; example: assistant_schedule(agent=\"worker\", at=\"after window\", pane_id=\"%7\")")
    res = resolve_project(project)
    if res["candidates"]:
        return ScheduleResult(scheduled=False, line="", note=res["note"] + "; candidates: " + ", ".join(res["candidates"]))
    path = res["path"]
    if not path and pane_id:
        row = _pane_by_id(pane_id)
        if row is None:
            raise ValueError(f"no pane {pane_id}; ids come from assistant_panes, e.g. pane_id=\"%7\"")
        path = row["cwd"]
    path = path or os.getcwd()
    if not os.path.isdir(path):
        os.makedirs(path)
        subprocess.run(["git", "init", "-q", path], capture_output=True)
    at_words = at.strip() or "after window"
    at_words = re.sub(r"^after the window( resets?)?$", "after window", at_words, flags=re.I)
    if re.match(r"^\d{1,2}(:\d{2})?\s*(am|pm)$", at_words, re.I):
        at_words = "at " + at_words
    raw = f"{agent} {shlex.quote(prompt) if prompt else ''} {at_words}".strip()
    try:
        d = ra_launch.parse(raw)
    except Exception as e:  # noqa: BLE001
        raise ValueError(f"run-agent could not parse {raw!r}: {e}; example: at=\"after window\" or at=\"at 3pm\"") from e
    if not d.get("at"):
        raise ValueError(f"run-agent found no time in {at!r} (unsure: {d.get('unsure')}); use 'after window', 'at 3pm', 'in 2 hours'")
    args = ra_launch.run_args(d)
    if "--" in args:
        k = args.index("--")
        args = args[:k] + ["--cwd", path] + args[k:]
    else:
        args += ["--cwd", path]
    fl = shlex.split(flags) if flags else []
    if fl:
        args += ([] if "--" in args else ["--"]) + fl
    if not pane_id:
        k = args.index("--cwd")
        args = args[:k] + ["--target", "window"] + args[k:]
    r = subprocess.run([ra_launch.S_REAL, *args], capture_output=True, text=True, cwd=path, env=_ra_env(pane_id, not pane_id))
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    line = next((ln for ln in out.split("\n") if ln.startswith("scheduled #")), "")
    m = re.match(r"scheduled #(\d+):", line)
    _log_launch(pane_id or "-", agent, path, line or out)
    if not m:
        return ScheduleResult(scheduled=False, line=out, project=path, note="run-agent did not schedule; its output is in `line`")
    when = re.search(r" at ([^()]*?)(?: ET)?\s*(?:\(|$)", line)
    say = f"#{m.group(1)} starts {_pname(path)}'s {agent} at {when.group(1).strip() if when else d.get('at_shown', '')}"
    try:                                   # a start on the weekly reset says so itself: the reply needs no second time
        wk = usage_resets().get("weekly")
        wk = (datetime.datetime.fromtimestamp(wk, ZoneInfo("America/New_York")).strftime("%-I:%M %p")
              if wk and 0 < wk - time.time() < 86400 else "")
    except Exception:
        wk = ""
    if when and wk and when.group(1).strip().endswith(wk):
        say += ", when the weekly limit resets"
    return ScheduleResult(scheduled=True, line=line, job_id=int(m.group(1)), pane_id=pane_id, run_at_et=d.get("at_shown", ""),
                          command=d.get("command", ""), project=path, say=say)


class Job(BaseModel):
    job_id: int
    command: str
    run_at_et: str
    at_text: str
    pane_id: str = ""
    cwd: str = ""
    agent: str = ""
    runner: str = Field(default="", description="sleeping (pid N) | dead | errored: … | waiting: no pane")


class JobsResult(BaseModel):
    action: str
    jobs: list[Job]
    listing: str = Field(description="run-agent's own --jobs text (or the cancel line)")
    cancelled: str = ""
    recent: list[str] = Field(default_factory=list, description="the last lines of run-agent's jobs.log (scheduled, fired, cancelled, waiting), times ET: look here for 'the scheduled run', 'did the 9 PM job go' before asking the user anything")
    five_hour_reset_et: str = Field(default="", description="when the 5-hour usage window resets (ET); '' when unknown")
    weekly_reset_et: str = Field(default="", description="when the weekly usage limit resets (ET), read from the account's usage endpoint; '' when it could not be read (usage_note says why)")
    usage_note: str = Field(default="", description="where the reset times came from, with the used percentages; or why they are missing. When weekly_reset_et is '' and the user has stated the time, use theirs for the rest of the session")
    note: str = ""


USAGE_CACHE = os.path.join(os.path.dirname(LOG_TSV), "usage.json")


def usage_resets() -> dict:
    """{five_hour, weekly: epoch or None, note}: the reset times of the 5-hour window and the weekly limit, from the
    same OAuth usage endpoint run-agent's parse.fetch_reset reads (it keeps only five_hour; the reply also carries
    seven_day.resets_at). RUN_AGENT_USAGE_FILE (a JSON file) stands in for the API; the answer is cached 10 minutes
    because the endpoint answers 429 when asked often. The harness never calls the network."""
    import urllib.request
    path = os.environ.get("RUN_AGENT_USAGE_FILE")
    data, src = None, ""
    try:
        if path:
            data, src = json.load(open(path, encoding="utf-8")), path
        elif os.environ.get("ASSISTANT_TEST_SOCKET"):
            return {"five_hour": None, "weekly": None, "note": "usage not read under the test harness (no RUN_AGENT_USAGE_FILE)"}
        else:
            try:
                c = json.load(open(USAGE_CACHE, encoding="utf-8"))
                if time.time() - c.get("saved", 0) < 600:
                    data, src = c["data"], "the usage endpoint (cached)"
            except (OSError, ValueError, KeyError):
                pass
            if data is None:
                tok = json.load(open(os.path.join(HOME, ".claude", ".credentials.json"), encoding="utf-8"))["claudeAiOauth"]["accessToken"]
                req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage",
                                             headers={"Authorization": f"Bearer {tok}", "anthropic-beta": "oauth-2025-04-20"})
                with urllib.request.urlopen(req, timeout=10) as r:
                    data = json.load(r)
                src = "the usage endpoint (api.anthropic.com/api/oauth/usage)"
                try:
                    os.makedirs(os.path.dirname(USAGE_CACHE), exist_ok=True)
                    json.dump({"saved": time.time(), "data": data}, open(USAGE_CACHE, "w", encoding="utf-8"))
                except OSError:
                    pass
    except Exception as e:  # noqa: BLE001
        five = None
        try:
            five = json.load(open(ra_parse.cache_path(), encoding="utf-8")).get("reset")
        except (OSError, ValueError):
            pass
        return {"five_hour": five if five and five > time.time() else None, "weekly": None,
                "note": f"weekly reset not readable ({type(e).__name__}: {str(e)[:80]}); the 5-hour time is run-agent's cached one"}

    def ep(key: str):
        v = data.get(key) if isinstance(data, dict) else None
        try:
            return datetime.datetime.fromisoformat(v["resets_at"].replace("Z", "+00:00")).timestamp(), v.get("utilization")
        except (TypeError, KeyError, ValueError, AttributeError):
            return None, None
    (five, fu), (week, wu) = ep("five_hour"), ep("seven_day")
    used = ", ".join(f"{n} {int(u)}% used" for n, u in (("5-hour", fu), ("week", wu)) if u is not None)
    return {"five_hour": five, "weekly": week, "note": f"from {src}" + (f"; {used}" if used else "")
            + ("" if week else "; no seven_day.resets_at in the reply")}


def _fmt_day_et(ts: float) -> str:
    from zoneinfo import ZoneInfo
    return datetime.datetime.fromtimestamp(ts, ZoneInfo("America/New_York")).strftime("%a %b %-d, %-I:%M %p %Z")


def _recent_jobs(n: int = 8) -> list[str]:
    try:
        lines = [ln.rstrip() for ln in open(ra_jobs.LOG, encoding="utf-8", errors="replace") if ln.strip()]
    except (OSError, AttributeError):
        return []
    return [ln[:260] for ln in lines[-n:]]


@mcp.tool(name="assistant_jobs", annotations=ToolAnnotations(readOnlyHint=True, destructiveHint=False,
                                                             openWorldHint=False, idempotentHint=True))
def assistant_jobs(action: Literal["list", "cancel"] = Field(default="list", description="list pending scheduled runs, or cancel one"),
                   job_id: str = Field(default="", description="for cancel: the job number from a `scheduled #N` line, e.g. '12' or '#12'")) -> JobsResult:
    """Pending run-agent jobs (the `scheduled #N` runs) as run-agent's --jobs shows them, with pane/cwd/agent per job;
    action="cancel" with job_id removes one (readOnly only applies to list). Times are US Eastern. `recent` holds the
    last lines of jobs.log (what was scheduled, fired or cancelled, and when): "the scheduled run" or "the 9 PM job"
    is found there. `five_hour_reset_et` and `weekly_reset_et` are the usage limits' reset times: read them here
    before asking the user when a limit resets.
    Examples: assistant_jobs() ; assistant_jobs(action="cancel", job_id="12")."""
    jobs_py = ra_jobs.__file__
    if action == "cancel":
        if not str(job_id).strip():
            raise ValueError("cancel needs job_id, e.g. assistant_jobs(action=\"cancel\", job_id=\"12\")")
        r = subprocess.run([sys.executable, jobs_py, "cancel", str(job_id).lstrip("#")], capture_output=True, text=True, env=_env())
        out = (r.stdout + r.stderr).strip()
        if r.returncode:
            raise ValueError(f"could not cancel #{job_id}: {out}; list jobs with assistant_jobs() and pass one of its ids")
        cancelled = out
    else:
        cancelled = ""
    rows = []
    for jid in ra_jobs.pending():
        try:
            j = ra_jobs.load(jid)
        except Exception:  # noqa: BLE001
            continue
        rows.append(Job(job_id=jid, command=j.get("shown", ""), run_at_et=ra_parse.fmt_et(j["run_at"]), at_text=j.get("at_text", ""),
                        pane_id=("" if j.get("target") else j.get("pane", "") or ""), cwd=j.get("cwd", ""), agent=j.get("agent", ""), runner=ra_jobs.state(j)))
    r = subprocess.run([sys.executable, jobs_py, "list"], capture_output=True, text=True, env=_env())
    u = usage_resets()
    return JobsResult(action=action, jobs=rows, listing=(r.stdout + r.stderr).strip(), cancelled=cancelled,
                      recent=_recent_jobs(), usage_note=u["note"],
                      five_hour_reset_et=ra_parse.fmt_et(u["five_hour"]) if u["five_hour"] else "",
                      weekly_reset_et=_fmt_day_et(u["weekly"]) if u["weekly"] else "")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--classify"]:
        # dev helper: `server.py --classify [procs-json]` reads a screen on stdin, prints
        # classify() as JSON; procs-json is the optional process tree, e.g. [["1","terminal-pet",["terminal-pet","--pet","dog"]]]
        procs = [tuple(x) for x in json.loads(sys.argv[2])] if len(sys.argv) > 2 else []
        print(json.dumps(classify(sys.stdin.read(), procs)))
        sys.exit(0)
    if sys.argv[1:2] == ["--usage"]:
        # dev helper: the reset times assistant_jobs returns, read the same way
        u = usage_resets()
        print(json.dumps({"five_hour_reset_et": ra_parse.fmt_et(u["five_hour"]) if u["five_hour"] else "",
                          "weekly_reset_et": _fmt_day_et(u["weekly"]) if u["weekly"] else "", "usage_note": u["note"]}))
        sys.exit(0)
    mcp.run(transport="stdio")
