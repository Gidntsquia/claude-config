#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.12"
# dependencies = ["mcp>=1.2,<2"]
# ///
"""PreToolUse guard for the assistant agent (frontmatter `hooks:`): rules that do not bend, checked before the
tool call runs. Reads the hook JSON on stdin, exits 2 with a one-line reason on stderr to block (the agent relays
that line), exits 0 to allow.

  a. assistant_send / assistant_layout close whose target is a pet pane (a whole-window close stays allowed), or the
     assistant's own pane (TMUX_PANE / ASSISTANT_SELF_PANE) unless self=True (layout: include_self=True also counts).
  b. assistant_send(answer=…) into a pane whose menu is a judgement call (the server tags `judgement=True`: an
     evaluator's Works / Doesn't work / Not what I meant, a planner's choice between ideas).
  c. assistant_layout(force=True) on a running / waiting pane (or a retile / window close that would move or end one)
     unless confirmed=True, which the agent sets after an AskUserQuestion yes or a standing order (stop asking before restarts).
  d. assistant_launch(force=True) without confirmed=True: an occupied pane is taken only on purpose.
  e. Bash: a tmux subcommand other than list-*, display-message and capture-pane (reading is allowed, changing goes
     through the assistant tools); a command naming this repo's mcp/, scripts/hooks/ or .claude/agents/ (the operator
     does not read or edit its own server, hook or agent file); run_in_background (no watch scripts). Each reason
     names the assistant tool that does the job.

Pane facts come from mcp/server.py's list_panes (the same tmux server the tool will use), imported from the file next
to this script's repo; nothing is typed or changed here. ASSISTANT_GUARD_LOG=<path> appends one line per decision."""
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "..", "mcp", "server.py")


def load_server():
    spec = importlib.util.spec_from_file_location("assistant_server", SERVER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def block(reason: str) -> None:
    _log("BLOCK " + reason)
    print(reason, file=sys.stderr)
    sys.exit(2)


def _log(line: str) -> None:
    p = os.environ.get("ASSISTANT_GUARD_LOG")
    if p:
        with open(p, "a", encoding="utf-8") as f:
            f.write(line + "\n")


def truthy(v) -> bool:
    return v is True or (isinstance(v, str) and v.lower() in ("true", "1", "yes"))


REPO = os.path.realpath(os.path.join(HERE, "..", ".."))
TMUX_READ = {"display-message", "display", "capture-pane", "capturep", "ls", "lsp", "lsw", "lsc", "lsb", "lsk", "lscm"}
TMUX_TOOL = [
    (("send-keys", "send", "send-prefix", "paste-buffer", "pasteb", "set-buffer", "setb", "load-buffer", "loadb"),
     "assistant_send types into a pane and reads back that the text arrived"),
    (("new-window", "neww", "split-window", "splitw", "new-session", "new", "respawn-pane", "respawnp", "respawn-window",
      "respawnw"), "assistant_launch starts an agent in an empty shell"),
    (("kill-pane", "killp", "kill-window", "killw", "kill-session", "kill-server", "move-pane", "movep", "join-pane",
      "joinp", "break-pane", "breakp", "swap-pane", "swapp", "swap-window", "swapw", "move-window", "movew",
      "select-layout", "selectl", "resize-pane", "resizep", "link-window", "linkw", "unlink-window", "unlinkw",
      "rename-window", "renamew", "rename-session", "rename"),
     "assistant_layout closes, moves, swaps and retiles panes and reports each step"),
]
# tmux where a command starts: the start of the line, after a separator, an opening quote of `bash -c`, or a wrapper word
TMUX_AT = re.compile(r"""(?:^|[;&|(){}`\n]|["'])\s*(?:(?:exec|command|sudo|env|nohup|time|xargs(?:\s+-\S+)*)\s+)*(?:[\w/.~$-]*/)?tmux(?=\s|$|["'`;&|)])""", re.M)
PATH_PART = re.compile(r"""([^\s"'`=:;|&()<>,]*?)(?<![\w-])(mcp/|scripts/hooks/|\.claude/agents/|mcp(?=[\s"'`;|&)]|$)|scripts/hooks(?=[\s"'`;|&)]|$)|\.claude/agents(?=[\s"'`;|&)]|$))""")


def tmux_denial(cmd: str) -> str:
    """'' when every tmux command in `cmd` only reads, else the reason"""
    for m in TMUX_AT.finditer(cmd):
        rest = re.split(r"(?<!\\)[;&|\n)`]", cmd[m.end():], maxsplit=1)[0]
        words = [w.strip("\"'") for w in rest.split()]
        sub = ""
        i = 0
        while i < len(words):
            w = words[i]
            if w in ("-L", "-S", "-f", "-T", "-c"):
                i += 2
                continue
            if w.startswith("-"):
                i += 1
                continue
            sub = w
            break
        chained = re.search(r"""\\;|';'|";"|\s\\$""", cmd[m.end():m.end() + len(rest) + 3])
        if sub and (sub.startswith("list-") or sub in TMUX_READ) and not chained:
            continue
        tool = next((t for names, t in TMUX_TOOL if sub in names), "")
        if not tool:
            tool = "assistant_panes reads every pane; assistant_send, assistant_launch and assistant_layout change them"
        what = f"`tmux {sub}`" if sub else "a bare `tmux`"
        if chained and (sub.startswith("list-") or sub in TMUX_READ):
            what = "a chained tmux command"
        return (f"blocked: {what} is not run from the shell. From Bash only tmux list-*, display-message and "
                f"capture-pane are allowed, one per command; use the assistant tool instead: {tool}")
    return ""


def repo_denial(cmd: str, cwd: str) -> str:
    """'' unless `cmd` names this repo's mcp/, scripts/hooks/ or .claude/agents/ (or the installed agent file)"""
    home = os.path.expanduser("~")
    for m in PATH_PART.finditer(cmd):
        pre, part = m.group(1), m.group(2).rstrip("/")
        pre = pre.replace("${HOME}", home).replace("$HOME", home)
        pre = os.path.expanduser(pre)
        if "$" in pre:
            continue
        if not os.path.isabs(pre):
            if not cwd:
                continue
            pre = os.path.join(cwd, pre)
        hit = os.path.realpath(os.path.join(pre, part))
        if part == ".claude/agents":
            f = os.path.realpath(os.path.join(pre, part, "assistant.md"))
            ok = not (f == os.path.join(REPO, ".claude", "agents", "assistant.md") or hit == os.path.join(REPO, ".claude", "agents"))
        else:
            ok = hit != os.path.join(REPO, part)
        if not ok:
            return (f"blocked: the command names {m.group(0)!r}, the operator's own {('server' if part == 'mcp' else 'hook' if part == 'scripts/hooks' else 'agent file')}; "
                    f"it is not read, run or edited from the shell. Use assistant_panes for what is on the panes, and report a tool "
                    f"result that looks wrong to the user as it came back")
    return ""


def guard_bash(data: dict, inp: dict) -> None:
    cmd = str(inp.get("command") or "")
    if truthy(inp.get("run_in_background")):
        block("blocked: no background commands and no watch scripts. Nothing runs between the user's messages; a step for "
              "later is booked with assistant_schedule, and the state is read again with assistant_panes on the next order")
    why = tmux_denial(cmd) or repo_denial(cmd, str(data.get("cwd") or ""))
    if why:
        block(why)
    _log("allow bash " + cmd[:200])
    sys.exit(0)


def targets_of_send(inp: dict) -> list[str]:
    ids = inp.get("pane_ids", [])
    if isinstance(ids, str):
        ids = [x for x in re.split(r"[\s,]+", ids) if x]
    return [str(x) for x in ids]


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)
    tool = data.get("tool_name", "")
    inp = data.get("tool_input") or {}
    if tool == "Bash":
        guard_bash(data, inp)
    if tool == "mcp__assistant__assistant_launch":
        if truthy(inp.get("force")) and not truthy(inp.get("confirmed")):
            block("blocked: assistant_launch(force=True) takes an occupied pane and needs confirmed=True, set when the pane is "
                  "this project's own done or idle pane and the order starts its next agent, or when the user's order names "
                  "what to replace. Without force the launch goes into an empty shell")
        _log("allow launch " + json.dumps(inp)[:200])
        sys.exit(0)
    if tool not in ("mcp__assistant__assistant_send", "mcp__assistant__assistant_layout"):
        sys.exit(0)
    srv = load_server()
    if not srv.in_tmux():
        sys.exit(0)
    try:
        ds = srv.list_panes()
    except RuntimeError:
        sys.exit(0)
    me = srv._self_pane()
    mention = srv._mention

    if tool == "mcp__assistant__assistant_send":
        own_ok = truthy(inp.get("self"))
        for t in targets_of_send(inp):
            d = srv._one(ds, t, srv.my_session())
            if d is None:
                continue
            if d["state"] == "pet":
                block(f"blocked: {mention(d)} is the {d.get('pet') or 'terminal'} pet; pets take no text (close its window instead if that is the order)")
            if me and d["id"] == me and not own_ok:
                block(f"blocked: {mention(d)} is my own pane; typing into it needs self=True and an order that names it")
            if inp.get("answer") and d.get("judgement"):
                block(f"blocked: {mention(d)} is on a judgement call ({d.get('question')!r}, options {d.get('options')}); quote it to the user instead of answering")
        _log("allow send " + json.dumps(inp)[:200])
        sys.exit(0)

    action = inp.get("action", "")
    target = str(inp.get("target") or "")
    session = str(inp.get("session") or "") or srv.my_session()
    own_ok = truthy(inp.get("self")) or truthy(inp.get("include_self"))
    force = truthy(inp.get("force"))
    confirmed = truthy(inp.get("confirmed"))
    d = srv._one(ds, target, session) if target else None
    if action == "close" and d is not None:
        if d["state"] == "pet":
            block(f"blocked: {mention(d)} is the {d.get('pet') or 'terminal'} pet; close its window (`close the {d.get('pet')} window`) to end it with the window")
        if me and d["id"] == me and not own_ok:
            block(f"blocked: {mention(d)} is my own pane; it closes only when the order names me and you answered yes to `this closes me too` (then self=True)")
    if force and not confirmed:
        if d is not None and d["state"] not in ("running", "waiting", "trust"):
            pass   # force on a pane that is not busy changes nothing: allowed
        else:
            what = mention(d) if d is not None else (f"window {target}" if target else "the retile")
            block(f"blocked: force=True on {what} needs confirmed=True, set after the user said yes to an AskUserQuestion naming the pane, or gave a standing order such as 'stop asking before restarts'")
    _log("allow layout " + json.dumps(inp)[:200])
    sys.exit(0)


if __name__ == "__main__":
    main()
