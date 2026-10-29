#!/usr/bin/env python3
"""launch.py: the /run-agent steps 0-6 as code, so the calling session only runs one Bash line. Stdlib only.

  launch.py relaunch '<raw>'        the /run-agent skill. Answers what needs no question at once (jobs, cancel,
                                    errors, unknown agent, dry runs) and runs force runs. Anything that needs a
                                    question goes to a haiku session (`claude --model haiku --effort low`) started
                                    with a fixed prompt holding the question and the exact command: the calling
                                    pane is respawned into it, or with split/window a new pane/window opens with it
                                    and the calling session goes on. Yes there runs the command (which replaces the
                                    haiku pane); No leaves it saying `nothing changed`.
  launch.py step [--here] '<raw>'   the instructions for the next step as text (what the haiku session follows
                                    after rewriting an unsure word or choosing an agent). --here: the confirm already
                                    runs in its own new pane, so the run replaces that pane (target dropped).
  launch.py cli <words...>          bin/run-agent: the same steps in a terminal, asking with read (or a tmux popup).
  launch.py next <agent> [prompt]   the next-step line an agent ends with: `/run-agent <agent> ["prompt"] <model>
                                    <effort>  (claude --agent <agent> "prompt" --model <model> --effort <effort>)`,
                                    model/effort read from this session's claude process (flags, then --name).
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
        return ("say", dry_text(d), 0)
    if d["force"]:
        return ("run", d)
    return ("ask", "confirm", d, None)


# ----------------------------------------------------------------- haiku instructions
def instructions(raw, here):
    st = decide(raw)
    sp = s_path()
    step = f"{sp} --step{' --here' if here else ''} "
    if st[0] == "say":
        return "Reply with exactly these lines and stop:\n" + st[1]
    if st[0] == "run":
        return f"Run this Bash command exactly, then reply with its output and stop:\n{run_line(st[1], here)}"
    kind, d, extra = st[1], st[2], st[3]
    if kind == "confirm":
        header, q, yes = question(d)
        return (f'1. Call AskUserQuestion once: header "{header}", question text exactly:\n{q}\n'
                f'   options: "{yes}" and "No".\n'
                f"2. {yes}: run this Bash command exactly, then stop (this session ends when it works; if it prints "
                f"an error, reply with that output):\n{run_line(d, here)}\n"
                "   No, or anything else: reply exactly `nothing changed` and stop.")
    if kind == "unsure":
        drop, prm = without(raw, extra), into_prompt(raw, d, extra)
        return (f'1. Call AskUserQuestion once: header "Unsure", question "I could not place `{extra}` in: {raw}. '
                f'What is it?", options: your best reading first if you have one (e.g. "--effort low" for "efort lo"), '
                f'then "Part of the prompt", then "Drop it".\n'
                f"2. Then run in Bash and follow what it prints, the same way:\n"
                f"   best reading: {step}<the line above with `{extra}` replaced by your reading, single-quoted>\n"
                f"   Part of the prompt: {step}{sq(prm)}\n"
                f"   Drop it: {step}{sq(drop)}\n"
                "   No answer: reply exactly `nothing changed` and stop.")
    if kind == "agent":
        names = [x for x in extra.splitlines() if x]
        return (f'1. Call AskUserQuestion once: header "Agent", question "Which agent? (also: {", ".join(names[4:])})", '
                'options "planner", "worker", "evaluator", "helper".\n'
                f"2. Run in Bash: {step}'<agent> {raw.replace(chr(39), chr(39) + chr(92) + chr(39) + chr(39))}' "
                "(the chosen agent first) and follow what it prints, the same way.")
    if kind == "cancel":
        return (f'1. Call AskUserQuestion once: header "Cancel?", question "Which scheduled run do you want to cancel?", '
                f"one option per line below (label `#<id>`, description the rest of the line), plus \"None\":\n{extra}\n"
                f"2. Run in Bash: {sp} --cancel <id> and reply with its output. None: reply exactly `nothing changed`.")
    return "Reply exactly `nothing changed` and stop."


HAIKU_HEAD = ("You are the /run-agent confirm step, a short session that does exactly the steps below and nothing "
              "else: no other tools, no file reads, no commentary, no summary.\n\n")


def relaunch(raw):
    st = decide(raw)
    if st[0] == "say":
        print(st[1]); return st[2]
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
    prompt = HAIKU_HEAD + instructions(raw, here)
    cmd = ["claude", prompt, "--model", "haiku", "--effort", "low", "--name", "run-agent",
           "--tools", "Bash,AskUserQuestion"]
    shown = "claude --model haiku --effort low (run-agent confirm)"
    wrap = ["bash", "-c", 'printf "%s\\n" "$1"; "${@:3}"; exec "$2"', "run-agent",
            f"/run-agent {raw}", os.environ.get("SHELL", "bash"), *cmd]
    cwd = os.getcwd()
    if target:
        folder = os.path.basename(d["dir"] or cwd)
        r = subprocess.run([S_REAL, "--open", target, os.environ["TMUX_PANE"], cwd, f"{d['agent']}: {folder}", *wrap],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"tmux could not open a {target}: {r.stderr.strip()}"); return 2
        new = r.stdout.strip()
        where = subprocess.run(["tmux", "display", "-p", "-t", new, "#{session_name}:#{window_index}.#{pane_index}"],
                               capture_output=True, text=True).stdout.strip() or new
        print(f"opened {where} ({new}): confirm there to start {d['command']}")
        return 0
    print(f"this pane now asks to confirm: {d['command'] if d else raw}")
    sys.stdout.flush()
    r = subprocess.run(["tmux", "respawn-pane", "-k", "-t", os.environ["TMUX_PANE"], "-c", cwd, *wrap])
    return r.returncode


# ----------------------------------------------------------------- terminal (bin/run-agent)
def ask_line(prompt):
    """one line from the user: the terminal, else a tmux popup; None when neither exists"""
    try:
        with open("/dev/tty", "r+") as tty:
            tty.write(prompt); tty.flush()
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
    words = ["/run-agent", agent]
    plain = ["claude", "--agent", agent]
    if prompt:
        words.append('"%s"' % prompt); plain.append('"%s"' % prompt)
    for flag, v in (("--model", model), ("--effort", effort)):
        if v:
            words.append(v); plain += [flag, v]
    print(" ".join(words) + "  (" + " ".join(plain) + ")")
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
        print(instructions(" ".join(rest), here)); return 0
    if mode == "cli":
        return cli(rest)
    if mode == "next":
        return next_line(rest)
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main())
