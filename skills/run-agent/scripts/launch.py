#!/usr/bin/env python3
"""launch.py: the /run-agent steps 0-6 as code, so the calling session only runs one Bash line. Stdlib only.

  launch.py relaunch '<raw>'        the /run-agent skill. Answers what needs no question at once (jobs, cancel,
                                    errors, unknown agent, dry runs) and runs force runs. Anything that needs a
                                    question goes to a haiku session (`claude --model haiku --effort low`) started
                                    with a fixed prompt holding the question and the exact command: the calling
                                    pane is respawned into it, or with split/window a new pane/window opens with it
                                    and the calling session goes on. Yes there runs the command (which replaces the
                                    haiku pane); No leaves it saying `nothing changed`.
  launch.py step [--here] '<raw>[ | <answer>]...'
                                    the confirm's state machine. The haiku session owns no logic: it runs this with
                                    the words it was given plus every user answer appended verbatim after ` | `, and
                                    does what the output says (ask one question, or stop). The script applies the
                                    answers in order (Yes -> run; No -> nothing changed; an unsure word -> the user's
                                    reading, `Part of the prompt` or `Drop it`; an agent name; a job id) and either
                                    runs the command itself or prints the next question. Time words the parser cannot
                                    place are resolved by haiku itself (current time and window reset are in its
                                    prompt) and handed back as `| time: at <clock>` / `| time: in <delay>`; it never
                                    asks the user when the window ends. After three answers without a run: `nothing
                                    changed` plus the words to type by hand. --here: the confirm already runs in its
                                    own new pane, so the run replaces that pane (target dropped).
  launch.py hook                    the UserPromptExpansion hook: reads the hook JSON on stdin, runs relaunch on
                                    command_args, and blocks the expansion with that output as the reason (no model
                                    turn, original prompt suppressed).
  launch.py cli <words...>          bin/run-agent: the same steps in a terminal, asking with read (or a tmux popup).
  launch.py group [--here] '<raw>'  several runs joined by a lone `+` or `;` (`planner "A" in ~/a + planner "B" in
                                    ~/b`): one new tmux window holding only their panes, tiled (four = 2x2); the
                                    calling pane is left alone. --here: this pane (the confirm, alone in the window
                                    it opened) becomes the first run. relaunch/cli confirm a group once.
  launch.py next <agent> [prompt]   the closing next step an agent ends with: a sentence saying what the command does
                                    and when to run it, the `/run-agent <agent> ["prompt"] <model> <effort>` line,
                                    then a labelled line with the plain `claude --agent ...` form; model/effort read
                                    from this session's claude process (flags, then --name).
"""
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
S_REAL = os.path.join(HERE, "run-agent.sh")
S_HOME = os.path.expanduser("~/.claude/skills/run-agent/scripts/run-agent.sh")
NEXT_PROMPT = {"worker": ".", "evaluator": ".", "helper": "."}


def s_path():
    try:
        if os.path.exists(S_HOME) and os.path.samefile(S_HOME, S_REAL):
            return S_HOME
    except OSError:
        pass
    return S_REAL


def tilde(p):
    home = os.path.expanduser("~")
    return "~" + p[len(home):] if p == home or p.startswith(home + "/") else p


def sq(s):
    """single-quote for a shell line"""
    return "'" + s.replace("'", "'\\''") + "'"


def S(*args, capture=True):
    r = subprocess.run([S_REAL, *args], capture_output=capture, text=True)
    return r.returncode, ((r.stdout or "") + (r.stderr or "")).rstrip("\n") if capture else ""


def parse(raw):
    rc, out = S("--parse", raw)
    return json.loads(out)


IGNORED = "ignored: agents replace their own pane"


def from_agent():
    """the agent name when this call comes from an agent session (worker/evaluator/planner/helper), else "" """
    if os.environ.get("RUN_AGENT_HUMAN"):
        return ""
    if os.environ.get("RUN_AGENT_FROM"):
        return os.environ["RUN_AGENT_FROM"]
    argv = claude_argv()
    if "--agent" in argv[:-1]:
        return argv[argv.index("--agent") + 1]
    name = next((argv[i + 1] for i, a in enumerate(argv[:-1]) if a in ("--name", "-n")), "")
    m = re.match(r"^(planner|worker|evaluator|helper):", name)
    return m.group(1) if m else ""


def now_et():
    import datetime
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo(os.environ.get("RUN_AGENT_TZ", "America/New_York"))
    except Exception:  # noqa: BLE001
        tz = None
    ts = float(os.environ.get("RUN_AGENT_NOW") or 0) or None
    d = datetime.datetime.fromtimestamp(ts, tz) if ts else datetime.datetime.now(tz)
    return d.strftime("%A %Y-%m-%d %-I:%M %p ET")


def run_args(d, here=False):
    """the parse's run string as argv for run-agent.sh (S dropped); --here drops --target"""
    a = shlex.split(d["run"])[1:]
    if here and "--target" in a:
        k = a.index("--target")
        if "--" not in a or k < a.index("--"):
            del a[k:k + 2]
    return a


def run_line(d, here=False):
    line = s_path() + " " + " ".join(shlex.quote(x) for x in run_args(d, here))
    if d.get("dir_state") == "missing":
        line = "mkdir -p " + shlex.quote(d["dir"]) + " && " + line
    return line


def question(d):
    """(header, question, yes label): the step-5 confirmation text, unchanged from the old SKILL.md"""
    where = tilde(d["dir"] or os.getcwd()) + (", will be created" if d.get("dir_state") == "missing" else "")
    if d.get("at") != "":
        header, yes = "Schedule?", "Yes, schedule it"
        when = d["at_shown"] + (f" until {d['until_shown']}" if d.get("until_shown") else "")
        q = f"Schedule: {d['command']} at {when} (in {where})"
    else:
        header, yes = "Run?", "Yes, replace this session"
        q = f"Replace this session with: {d['command']}  (in {where})"
    if d.get("corrections"):
        q += " (read: " + ", ".join(d["corrections"]) + ")"
    if re.search(r"(^| )--continue( |$)", d.get("flags", "")) and d["dir"] and d["dir"] != os.getcwd():
        q += f" (note: --continue resumes the latest session in {tilde(d['dir'])}, not this one)"
    return header, q + "?", yes


def dry_text(d):
    lines = [f"command: {d['command']}",
             f"dir: {tilde(d['dir'] or os.getcwd())}" + (" (will be created)" if d.get("dir_state") == "missing" else ""),
             f"run at: {d['at_shown'] or 'now'}" + (f" until {d['until_shown']}" if d.get("until_shown") else "")]
    if d.get("target"):
        lines.append(f"opens in: a new {'pane' if d['target'] == 'split' else 'tmux window'}")
    lines.append(f"usage reset: {d.get('reset_shown') or 'unavailable'}")
    lines.append("dry run: nothing scheduled, nothing replaced")
    return "\n".join(lines)


def without(raw, tok):
    return re.sub(r"\s+", " ", raw.replace(tok, " ", 1)).strip()


def into_prompt(raw, d, tok):
    rest = without(raw, tok)
    p = d.get("prompt") or ""
    for qs in ('"%s"', "'%s'", "“%s”"):
        if p and p != "." and (qs % p) in rest:
            return rest.replace(qs % p, '"%s %s"' % (p, tok), 1)
    return rest + ' "%s"' % tok


def decide(raw):
    """the next step for this raw string: ("say", text, rc) | ("run", d) | ("ask", kind, d, extra)"""
    raw = raw.strip()
    first = raw.split()[0].lower() if raw else ""
    if first in ("jobs", "list", "scheduled", "pending"):
        return ("say", S("--jobs")[1], 0)
    if first == "cancel":
        ids = re.findall(r"#?(\d+)", raw)
        if ids:
            rc, out = S("--cancel", ids[0]); return ("say", out, rc)
        rc, out = S("--jobs")
        n = len([x for x in out.splitlines() if x.startswith("#")])
        if n <= 1:
            rc, out = S("--cancel"); return ("say", out, rc)
        return ("ask", "cancel", None, out)
    d = parse(raw)
    if d.get("error"):
        return ("say", d["error"], 2)
    if d.get("at_error"):
        return ("say", d["at_error"], 2)
    if d.get("skipped"):
        return ("say", d["skipped"], 0)
    if not d["agent"]:
        if d["force"]:
            return ("say", 'usage: /run-agent <agent> ["prompt"] [in <dir>] [split|window] [flags...] [at <time>]', 2)
        return ("ask", "agent", d, S("--list")[1])
    if not d["agent_ok"]:
        lst = S("--list")[1]
        return ("say", f"unknown agent: {d['agent']}\nvalid agents:\n" + "\n".join("  " + x for x in lst.splitlines()), 2)
    if d["unsure"]:
        return ("ask", "unsure", d, d["unsure"][0])
    if d["dry"]:
        return ("say", (IGNORED + "\n" if d.get("target_ignored") else "") + dry_text(d), 0)
    if d["force"]:
        return ("run", d)
    return ("ask", "confirm", d, None)


# ----------------------------------------------------------------- several runs in one call
SEPS = ("+", ";")


def split_runs(raw):
    """raw split on a lone `+` or `;` outside quotes; one item when there is none"""
    parts, cur, q = [], [], None
    closing = {'"': '"', "'": "'", "\u201c": "\u201d"}
    for tok in re.findall(r'\S+|\s+', raw):
        if q is None and tok in SEPS:
            parts.append("".join(cur).strip()); cur = []; continue
        cur.append(tok)
        for ch in tok:
            if q is None and ch in closing:
                q = closing[ch]
            elif q is not None and ch == q:
                q = None
    parts.append("".join(cur).strip())
    return [x for x in parts if x] if len(parts) > 1 else [raw.strip()]


def decide_group(runs):
    """("say", text, rc) | ("run", [d...]) | ("ask", "group", [d...], None) for two or more runs"""
    ds = []
    for n, r in enumerate(runs, 1):
        st = decide(r)
        if st[0] == "say":
            if st[2] != 0 or not (st[1].startswith("command:")):
                return ("say", f"run {n} ({r}): {st[1]}", st[2] or 2)
            st = ("run", parse(r))
        if st[0] == "ask":
            kind, d, extra = st[1], st[2], st[3]
            if kind == "unsure":
                return ("say", f"run {n} ({r}): could not place `{extra}`; retype that run (or start it on its own)", 2)
            if kind == "agent":
                return ("say", f"run {n} ({r}): no agent named; start it with planner, worker, evaluator or helper", 2)
            if kind == "cancel":
                return ("say", f"run {n}: jobs and cancel cannot be combined with other runs", 2)
        d = st[1] if st[0] == "run" else st[2]
        if d.get("at") not in ("", None):
            return ("say", f"run {n} ({r}): runs started together start now; schedule each run on its own", 2)
        ds.append(d)
    if any(d["dry"] for d in ds):
        out = []
        for n, d in enumerate(ds, 1):
            out.append(f"run {n}:\n" + "\n".join("  " + x for x in dry_text(d).splitlines()
                                                 if not x.startswith(("opens in:", "dry run:", "usage reset:"))))
        out.append(f"opens in: one new tmux window, {len(ds)} panes tiled")
        out.append("usage reset: " + next((d["reset_shown"] for d in ds if d.get("reset_shown")), "unavailable"))
        out.append("dry run: nothing scheduled, nothing replaced")
        return ("say", "\n".join(out), 0)
    if any(d["force"] for d in ds):
        return ("run", ds)
    return ("ask", "group", ds, None)


def group_question(ds):
    items = []
    for d in ds:
        where = tilde(d["dir"] or os.getcwd()) + (", will be created" if d.get("dir_state") == "missing" else "")
        items.append(f"{d['command']} (in {where})")
    q = f"Start {len(ds)} sessions in one new tmux window, this one left as is: " + "; ".join(items) + "?"
    return "Run?", q, f"Yes, start all {len(ds)}"


def group_line(raw, here):
    return f"{s_path()} --group{' --here' if here else ''} {sq(raw)}"


def run_group(raw, here):
    """launch every run of raw (no confirm): a new window with run 1, the rest split into it, tiled"""
    if agent_mode():
        print(IGNORED); return 2
    st = decide_group(split_runs(raw))
    if st[0] == "say":
        print(st[1]); return st[2]
    ds = st[1] if st[0] == "run" else st[2]
    for d in ds:
        if d.get("dir_state") == "missing":
            os.makedirs(d["dir"], exist_ok=True)
    if not os.environ.get("TMUX") or not os.environ.get("TMUX_PANE"):
        print("not inside tmux; run each in its own terminal:")
        for d in ds:
            a = run_args(d, here=True)
            r = subprocess.run([S_REAL, *a, "--dry-run"], capture_output=True, text=True)
            print(next((x[len("command: "):] for x in r.stdout.splitlines() if x.startswith("command: ")), d["command"]))
        return 1
    me = os.environ["TMUX_PANE"]
    if here:  # this pane is alone in the window the confirm opened: add runs 2.., then become run 1
        for d in ds[1:]:
            r = subprocess.run([S_REAL, *run_args(d, here=True), "--target", "into:" + me])
            if r.returncode:
                return r.returncode
        subprocess.run(["tmux", "rename-window", "-t", me, f"{len(ds)} agents"], capture_output=True)
        return subprocess.run([S_REAL, *run_args(ds[0], here=True)]).returncode
    r = subprocess.run([S_REAL, *run_args(ds[0], here=True), "--target", "window"], capture_output=True, text=True)
    print(r.stdout.rstrip("\n"), flush=True) if r.stdout.strip() else None
    m = re.search(r"\((%\d+)\)", r.stdout)
    if r.returncode or not m:
        print(r.stderr.rstrip("\n")); return r.returncode or 2
    first = m.group(1)
    for d in ds[1:]:
        r = subprocess.run([S_REAL, *run_args(d, here=True), "--target", "into:" + first])
        if r.returncode:
            return r.returncode
    subprocess.run(["tmux", "rename-window", "-t", first, f"{len(ds)} agents"], capture_output=True)
    return 0


# ----------------------------------------------------------------- haiku instructions
def instructions(raw, here):
    if len(split_runs(raw)) > 1:
        st = decide_group(split_runs(raw))
        if st[0] == "say":
            return "Reply with exactly these lines and stop:\n" + st[1]
        if st[0] == "run":
            return f"Run this Bash command exactly, then reply with its output and stop:\n{group_line(raw, here)}"
        header, q, yes = group_question(st[2])
        return (f'1. Call AskUserQuestion once: header "{header}", question text exactly:\n{q}\n'
                f'   options: "{yes}" and "No".\n'
                f"2. {yes}: run this Bash command exactly, then stop (this session ends when it works; if it prints "
                f"an error, reply with that output):\n{group_line(raw, here)}\n"
                "   No, or anything else: reply exactly `nothing changed` and stop.")
    return step(raw, here)


ANSWER_SEP = " | "
TIMEY_RE = re.compile(r"\d|^(am|pm|h|hr|hrs|m|min|mins|hours?|minutes?|noon|midnight|tonight|tomorrow|today|window|"
                      r"before|after|at|in|the|current|this|evening|morning|afternoon|night|week|next|"
                      r"mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|"
                      r"sunday|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|half|o'?clock|"
                      r"early|late|around|by|later|reset|resets|ends|until|day|days|week|weeks|usage|my)$", re.I)


def timey(extra):
    """an unsure chunk made of time-ish words (digits, units, day words) that haiku may resolve itself"""
    words = re.sub(r"\(already past\)$", "", extra).replace("--", "").split()
    return bool(words) and all(TIMEY_RE.search(w.strip(",.")) for w in words)


def apply_answer(cur, st, ans):
    """fold one user answer into the words; returns (new raw, action) where action is None | "run" | "stop" |
    ("cancel", id) | ("say", text)"""
    kind, d, extra = st[1], st[2], st[3]
    a = ans.strip()
    low = a.lower()
    if kind == "confirm":
        if low.startswith("yes") or low in ("y", "run", "run it", "schedule", "schedule it", "ok", "go"):
            return cur, "run"
        if low in ("no", "n", "cancel", "stop", "nothing"):
            return cur, "stop"
        return cur + " " + a, None  # free text: more words for the command
    if kind == "unsure":
        if low.startswith("time:"):
            # haiku resolved the time: every time-ish unsure chunk and the time the parser did read go, the answer stays
            new = cur
            for u in d.get("unsure") or [extra]:
                u0 = re.sub(r" \(already past\)$", "", u)
                if timey(u0):
                    new = without(new, u0)
            if d.get("at_text"):
                new = without(new, d["at_text"])
            return new + " " + a[5:].strip(), None
        if low in ("drop it", "drop", "d"):
            return without(cur, re.sub(r" \(already past\)$", "", extra)), None
        if low in ("part of the prompt", "prompt", "p"):
            return into_prompt(cur, d, re.sub(r" \(already past\)$", "", extra)), None
        if low in ("no", "n", "stop", "nothing"):
            return cur, "stop"
        return cur.replace(re.sub(r" \(already past\)$", "", extra), a, 1), None
    if kind == "agent":
        if low in ("no", "n", "stop", "nothing", "none"):
            return cur, "stop"
        return a.split()[0] + " " + cur, None
    if kind == "cancel":
        m = re.search(r"\d+", a)
        if not m or low in ("none", "no"):
            return cur, "stop"
        return cur, ("cancel", m.group(0))
    return cur, "stop"


def step(raw, here):
    """the confirm state machine: apply the ` | answer` segments, then run, print the next question, or stop"""
    agent_mode()
    parts = raw.split(ANSWER_SEP)
    cur, answers = parts[0].strip(), parts[1:]
    sp = s_path()
    stepcmd = f"{sp} --step{' --here' if here else ''} "
    if len(split_runs(cur)) > 1:
        return group_step(cur, answers, here)
    st = decide(cur)
    for ans in answers:
        if st[0] != "ask":
            break
        cur, act = apply_answer(cur, st, ans)
        if act == "stop":
            return "Reply exactly `nothing changed` and stop."
        if act == "run":
            return do_run(st[2], here)
        if isinstance(act, tuple) and act[0] == "cancel":
            rc, out = S("--cancel", act[1]); return "Reply with exactly these lines and stop:\n" + out
        st = decide(cur)
    if st[0] == "say":
        return "Reply with exactly these lines and stop:\n" + st[1]
    if st[0] == "run":
        return do_run(st[1], here)
    kind, d, extra = st[1], st[2], st[3]
    if len(answers) >= 3:
        return ("Reply with exactly these lines and stop:\nnothing changed\n"
                f"type it by hand with the time spelled out, e.g.: /run-agent {cur}")
    def then(what):
        return (f"2. Then run in Bash exactly (nothing else, no guessed command):\n"
                f"   {stepcmd}{sq(cur + ANSWER_SEP)}<{what}>  -- i.e. the same words with ` | ` and {what} "
                f"appended inside the quotes, verbatim; then follow what it prints, the same way.")
    if kind == "confirm":
        header, q, yes = question(d)
        return (f'1. Call AskUserQuestion once: header "{header}", question text exactly:\n{q}\n'
                f'   options: "{yes}" and "No".\n' + then("the answer, Yes or No, or the free text the user typed"))
    if kind == "unsure":
        if timey(extra):
            tw = "`" + " ".join(re.sub(r" \(already past\)$", "", u) for u in d["unsure"] if timey(u)) + "`"
            if d.get("at_text"):
                tw += f" (and the parser's own reading `{d['at_text']}`, which your answer replaces)"
            return (f"Resolve the time words {tw} in: {cur} yourself, as the user would (see the current time "
                    f"and window reset above; no question to the user, never ask when the window ends). Then run in "
                    f"Bash exactly:\n   {stepcmd}{sq(cur + ANSWER_SEP + 'time: ')}<at <clock>|in <delay>>  -- the "
                    "words `at 5:30 AM` or `in 2h 10m` appended after `time: ` inside the quotes; then follow what it "
                    "prints, the same way.")
        return (f'1. Call AskUserQuestion once: header "Unsure", question "I could not place `{extra}` in: {cur}. '
                f'What is it?", options: "Part of the prompt", "Drop it" (the user may also type a replacement).\n'
                + then("the chosen option label or the typed text"))
    if kind == "agent":
        names = [x for x in extra.splitlines() if x]
        return (f'1. Call AskUserQuestion once: header "Agent", question "Which agent? (also: {", ".join(names[4:])})", '
                'options "planner", "worker", "evaluator", "helper".\n' + then("the chosen agent name"))
    if kind == "cancel":
        return (f'1. Call AskUserQuestion once: header "Cancel?", question "Which scheduled run do you want to cancel?", '
                f"one option per line below (label `#<id>`, description the rest of the line), plus \"None\":\n{extra}\n"
                + then("the chosen label, e.g. #12 or None"))
    return "Reply exactly `nothing changed` and stop."


def group_step(cur, answers, here):
    st = decide_group(split_runs(cur))
    if st[0] == "say":
        return "Reply with exactly these lines and stop:\n" + st[1]
    if answers:
        low = answers[0].strip().lower()
        if not (low.startswith("yes") or low in ("y", "run", "ok", "go")):
            return "Reply exactly `nothing changed` and stop."
        st = ("run", st[2] if st[0] == "ask" else st[1])
    if st[0] == "run":
        drop_transcript()
        sys.stdout.flush()
        rc = run_group(cur, here)
        return f"Reply with exactly these lines and stop:\n{'started' if rc == 0 else 'failed'}"
    header, q, yes = group_question(st[2])
    stepcmd = f"{s_path()} --step{' --here' if here else ''} "
    return (f'1. Call AskUserQuestion once: header "{header}", question text exactly:\n{q}\n'
            f'   options: "{yes}" and "No".\n'
            f"2. Then run in Bash exactly: {stepcmd}{sq(cur + ANSWER_SEP)}<the answer>  -- the same words with "
            "` | ` and the answer appended inside the quotes; then follow what it prints, the same way.")


def drop_transcript():
    """delete this confirm session's transcript (its id is RUN_AGENT_CONFIRM_ID) so the resume picker stays clean"""
    sid = os.environ.get("RUN_AGENT_CONFIRM_ID", "")
    if not re.fullmatch(r"[0-9a-f-]{36}", sid):
        return
    import glob
    import shutil
    base = os.path.expanduser("~/.claude/projects")
    for f in glob.glob(os.path.join(base, "*", sid + ".jsonl")):
        try:
            os.remove(f)
        except OSError:
            pass
    for d in glob.glob(os.path.join(base, "*", sid)):
        shutil.rmtree(d, ignore_errors=True)


def do_run(d, here):
    """run the confirmed command now (this replaces the haiku pane, or schedules and returns its line)"""
    if d.get("dir_state") == "missing":
        os.makedirs(d["dir"], exist_ok=True)
    drop_transcript()
    sys.stdout.flush()
    r = subprocess.run([S_REAL, *run_args(d, here)], capture_output=True, text=True)
    out = ((r.stdout or "") + (r.stderr or "")).rstrip("\n")
    return "Reply with exactly these lines and stop:\n" + (out or ("started" if r.returncode == 0 else "failed"))


def haiku_head():
    rc, reset = S("--reset-shown")
    reset = reset.strip() if rc == 0 and reset.strip() else "unknown"
    return ("You are the /run-agent confirm step, a short session that does exactly the steps below and nothing "
            "else. Tools: AskUserQuestion, and Bash only in the one form `run-agent.sh --step '<words>'` given to "
            "you; no file reads, no grep, no other commands, no commentary, no summary. You never print a guessed "
            "command, never offer \"say run it\", never read a word next to a time word as a flag.\n"
            f"Current time: {now_et()}. The 5-hour usage window resets at {reset}. Read time words as the user "
            "would: tomorrow = the next calendar day even if that clock time is still ahead today; before the window "
            "= the reset time minus the span; after the window = the reset plus the span; tonight/this evening "
            "with no clock = 7 PM. Never ask when the window ends: it is written above.\n\n")


def agent_mode():
    """an agent session is calling: every parse from here on drops split/window words (target_ignored)"""
    who = from_agent()
    if who:
        os.environ["RUN_AGENT_IGNORE_TARGET"] = "1"
    return who


def relaunch(raw):
    group = len(split_runs(raw)) > 1
    agent_caller = agent_mode()
    if agent_caller and group:
        print(IGNORED); return 2
    st = decide_group(split_runs(raw)) if group else decide(raw)
    d0 = st[1] if st[0] == "run" else st[2] if st[0] == "ask" else None
    if agent_caller and isinstance(d0, dict) and d0.get("target_ignored"):
        print(IGNORED)
    if st[0] == "say":
        print(st[1]); return st[2]
    if group:
        if st[0] == "run" or not os.environ.get("TMUX") or not os.environ.get("TMUX_PANE"):
            return run_group(raw, False)
        st = ("ask", "group", {"target": "window", "agent": f"{len(st[2])} agents", "dir": "",
                               "command": f"{len(st[2])} sessions"}, None)
    if st[0] == "run":
        d = st[1]
        if d.get("dir_state") == "missing":
            os.makedirs(d["dir"], exist_ok=True)
        r = subprocess.run([S_REAL, *run_args(d)])
        return r.returncode
    d = st[2]
    if not os.environ.get("TMUX") or not os.environ.get("TMUX_PANE"):
        if d is not None and st[1] == "confirm" and d.get("at") == "":
            r = subprocess.run([S_REAL, *run_args(d)])  # prints "not inside tmux; run: ..."
            return r.returncode
        print("not inside tmux; run this in a terminal instead: run-agent " + raw)
        return 1
    target = (d or {}).get("target", "")
    here = bool(target)
    prompt = haiku_head() + step(raw, here)
    import uuid
    sid = str(uuid.uuid4())
    cwd = os.getcwd()
    if group:
        sname = f"run-agent: {d['agent']}"
    else:
        sname = f"run-agent: {d['agent']} {os.path.basename(d['dir'] or cwd)}"
        if d.get("at_shown"):
            sname += " at " + d["at_shown"].split(" (")[0]
    cmd = ["env", f"RUN_AGENT_CONFIRM_ID={sid}", "claude", prompt, "--model", "haiku", "--effort", "low",
           "--session-id", sid, "--name", sname, "--tools", "Bash,AskUserQuestion"]
    # on exit (No, or a scheduled run) the transcript goes; a Yes that respawns the pane deletes it first (do_run)
    cleanup = ('rm -f ~/.claude/projects/*/"$3".jsonl; rm -rf ~/.claude/projects/*/"$3"')
    wrap = ["bash", "-c", 'printf "%s\\n" "$1"; "${@:4}"; ' + cleanup + '; exec "$2"', "run-agent",
            f"/run-agent {raw}", os.environ.get("SHELL", "bash"), sid, *cmd]
    if target:
        wname = d["agent"] if group else f"{d['agent']}: {os.path.basename(d['dir'] or cwd)}"
        r = subprocess.run([S_REAL, "--open", "window", os.environ["TMUX_PANE"], cwd, wname, *wrap],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"tmux could not open a window: {r.stderr.strip()}"); return 2
        new = r.stdout.strip()
        where = subprocess.run(["tmux", "display", "-p", "-t", new, "#{session_name}:#{window_index}.#{pane_index}"],
                               capture_output=True, text=True).stdout.strip() or new
        print(f"opened new window {where} ({new}): confirm there to start {d['command']}")
        return 0
    print(f"this pane now asks to confirm: {d['command'] if d else raw}")
    sys.stdout.flush()
    r = subprocess.run(["tmux", "respawn-pane", "-k", "-t", os.environ["TMUX_PANE"], "-c", cwd, *wrap])
    return r.returncode


# ----------------------------------------------------------------- terminal (bin/run-agent)
def ask_line(prompt):
    """one line from the user: the terminal, else a tmux popup; None when neither exists"""
    try:
        with open("/dev/tty", "w") as out, open("/dev/tty") as tty:  # not "r+": a tty is not seekable (3.14)
            out.write(prompt); out.flush()
            return tty.readline().strip()
    except OSError:
        pass
    if os.environ.get("TMUX"):
        fd, f = tempfile.mkstemp(); os.close(fd)
        script = 'read -r -p "$1" a; printf %s "$a" > "$2"'
        subprocess.run(["tmux", "display-popup", "-E", "-w", "90%", "-h", "5", "-T", " run-agent ",
                        "bash -c " + shlex.quote(script) + " run-agent " + shlex.quote(prompt) + " " + shlex.quote(f)])
        try:
            return open(f).read().strip()
        finally:
            os.unlink(f)
    return None


def words_to_raw(words):
    out = []
    for w in words:
        if w == "" or re.search(r"\s", w):  # the shell took the quotes off; a prompt with spaces gets them back
            out.append('"%s"' % w if '"' not in w else "'%s'" % w)
        else:
            out.append(w)
    return " ".join(out)


def cli(words):
    raw = words_to_raw(words)
    if agent_mode() and len(split_runs(raw)) > 1:
        print(IGNORED); return 2
    if len(split_runs(raw)) > 1:
        st = decide_group(split_runs(raw))
        if st[0] == "say":
            print(st[1]); return st[2]
        if st[0] == "ask" and os.environ.get("TMUX"):
            a = ask_line(group_question(st[2])[1] + " [y/N] ")
            if a is None:
                print("no terminal to confirm in; add `force` to run without asking"); return 2
            if a.lower() not in ("y", "yes"):
                print("nothing changed"); return 0
        return run_group(raw, False)
    for _ in range(6):
        st = decide(raw)
        if st[0] == "say":
            print(st[1]); return st[2]
        if st[0] == "run":
            d = st[1]
        else:
            kind, d, extra = st[1], st[2], st[3]
            if kind == "cancel":
                print(extra)
                a = ask_line("cancel which id (empty = none)? ")
                if not a:
                    print("nothing changed"); return 0
                rc, out = S("--cancel", a); print(out); return rc
            if kind == "agent":
                a = ask_line("which agent (" + ", ".join(x for x in extra.splitlines() if x) + ")? ")
                if not a:
                    print("nothing changed"); return 0
                raw = a + " " + raw; continue
            if kind == "unsure":
                a = (ask_line(f"I could not place `{extra}`. [d]rop it, put it in the [p]rompt, or type a "
                              "replacement (empty = stop): ") or "")
                if not a:
                    print("nothing changed"); return 0
                raw = without(raw, extra) if a.lower() in ("d", "drop") else \
                    into_prompt(raw, d, extra) if a.lower() in ("p", "prompt") else raw.replace(extra, a, 1)
                continue
            if not os.environ.get("TMUX") and d.get("at") == "":
                break  # nothing can run here; run-agent.sh prints the command to run
            header, q, yes = question(d)
            if not os.environ.get("TMUX") or d.get("target"):
                q = q.replace("Replace this session with:", "Start:" if d.get("target") else "Run:")
            a = ask_line(q + " [y/N] ")
            if a is None:
                print("no terminal to confirm in; add `force` to run without asking"); return 2
            if a.lower() not in ("y", "yes"):
                print("nothing changed"); return 0
        if d.get("dir_state") == "missing":
            os.makedirs(d["dir"], exist_ok=True)
        break
    return subprocess.run([S_REAL, *run_args(d)]).returncode


# ----------------------------------------------------------------- next-step line
def claude_argv():
    pid = os.getppid()
    while pid > 1:
        try:
            argv = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
            argv = [a.decode(errors="replace") for a in argv if a]
            if argv and os.path.basename(argv[0]) == "claude":
                return argv
            pid = int(open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
    try:  # macOS: no /proc
        p = os.getppid()
        while p > 1:
            args = subprocess.run(["ps", "-o", "args=", "-p", str(p)], capture_output=True, text=True).stdout.strip()
            if args and os.path.basename(args.split()[0]) == "claude":
                return shlex.split(args) if '"' in args else args.split()
            p = int(subprocess.run(["ps", "-o", "ppid=", "-p", str(p)], capture_output=True, text=True).stdout.strip())
    except (OSError, ValueError):
        pass
    return []


def next_sentence(agent, prompt, caller):
    """one short sentence before the command: what it runs and when"""
    if agent == "worker" and caller == "evaluator":
        return "Next, after reading this eval, rerun the worker here:"
    if agent == "worker":
        return "Next, once the plan looks right, start the worker here:"
    if agent == "evaluator":
        return "Next, check this work with the evaluator" + (" on your phone:" if prompt == "phone" else " here:")
    if agent == "planner" and "EVAL" in prompt:
        return "Next, after reading this eval, replan here:"
    return f"Next, start the {agent} agent here:"


def next_line(args):
    agent = args[0] if args else "worker"
    prompt = args[1] if len(args) > 1 else NEXT_PROMPT.get(agent, "")
    argv = claude_argv()
    model = effort = name = ""
    for i, a in enumerate(argv):
        nxt = argv[i + 1] if i + 1 < len(argv) else ""
        if a in ("--model", "-m"):
            model = nxt
        elif a.startswith("--model="):
            model = a.split("=", 1)[1]
        elif a == "--effort":
            effort = nxt
        elif a.startswith("--effort="):
            effort = a.split("=", 1)[1]
        elif a in ("--name", "-n"):
            name = nxt
    if not model:
        m = re.search(r"\((\w+)\)\s*$", name)
        model = m.group(1) if m else ""
    caller = next((argv[i + 1] for i, a in enumerate(argv[:-1]) if a == "--agent"), "")
    words = ["/run-agent", agent]
    plain = ["claude", "--agent", agent]
    if prompt:
        words.append('"%s"' % prompt); plain.append('"%s"' % prompt)
    if agent in ("worker", "evaluator"):
        model = effort = ""  # workers and evaluators run on the default model and effort
    for flag, v in (("--model", model), ("--effort", effort)):
        if v:
            words.append(v); plain += [flag, v]
    print(next_sentence(agent, prompt, caller))
    print(" ".join(words))
    print("Without run-agent: " + " ".join(plain))
    return 0


def hook():
    """UserPromptExpansion hook: a typed `/run-agent <args>` runs relaunch with no model turn"""
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        data = {}
    args = (data.get("command_args") or "").strip()
    env = dict(os.environ, RUN_AGENT_HUMAN="1")  # a typed command is the human's, even inside an agent session
    r = subprocess.run([S_REAL, "--relaunch", args], capture_output=True, text=True, env=env)
    out = ((r.stdout or "") + (r.stderr or "")).strip() or ("done" if r.returncode == 0 else f"exit {r.returncode}")
    print(json.dumps({"decision": "block", "reason": out,
                      "hookSpecificOutput": {"hookEventName": "UserPromptExpansion", "suppressOriginalPrompt": True}}))
    return 0


def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    mode, rest = sys.argv[1], sys.argv[2:]
    if mode == "relaunch":
        return relaunch(" ".join(rest))
    if mode == "step":
        here = bool(rest) and rest[0] == "--here"
        if here:
            rest = rest[1:]
        print(step(" ".join(rest), here)); return 0
    if mode == "hook":
        return hook()
    if mode == "cli":
        return cli(rest)
    if mode == "group":
        here = bool(rest) and rest[0] == "--here"
        return run_group(" ".join(rest[1:] if here else rest), here)
    if mode == "next":
        return next_line(rest)
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main())
