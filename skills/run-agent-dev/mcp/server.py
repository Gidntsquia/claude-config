#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.12"
# dependencies = ["mcp>=1.2,<2"]
# ///
"""run-agent as an MCP server (stdio, server name `run-agent`): what an agent does with run-agent.sh, as typed tools.

Tools: schedule / cancel / jobs / handoff / next. Each calls this copy's run-agent.sh (--relaunch, --cancel, --jobs,
--handoff, --next) and returns the text it prints. The calling pane is the tmux pane of the parent `claude` process
(its /proc environ: TMUX, TMUX_PANE), so a run replaces the session that called the tool and a scheduled job targets
that same pane, exactly as a typed /run-agent does (the server's own TMUX/TMUX_PANE first; claude passes them on). Why a server at all: an allow rule `mcp__run-agent__*` resolves
before the auto-mode classifier reads the call, while a Bash rule only covers a command whose every part matches a
rule. Registered for every session by `claude mcp add --transport stdio --scope user run-agent -- <this file>`.
With RUN_AGENT_MCP_DEBUG=1 each start appends its environment (own TMUX/TMUX_PANE, the parent's) to
<RUN_AGENT_HOME>/mcp-env.txt.
"""
from __future__ import annotations

import builtins as _builtins
import os
import shlex
import subprocess
import sys
import time

from mcp.server.fastmcp import FastMCP

HERE = os.path.dirname(os.path.realpath(__file__))
SCRIPTS = os.path.join(os.path.dirname(HERE), "scripts")
sys.path.insert(0, SCRIPTS)
import jobs as jobs_mod  # noqa: E402  (the dev copy's store: RUN_AGENT_HOME or ~/.claude/run-agent-dev)
from launch import claude_argv, claude_environ  # noqa: E402

S = os.path.join(SCRIPTS, "run-agent.sh")
T0 = time.time()

mcp = FastMCP("run-agent", instructions="Schedule, list, cancel and hand off `claude --agent` runs through run-agent. "
              "A run replaces the calling session's tmux pane now or at the given time.")


def _env() -> dict:
    """the server's environment plus the parent claude's pane (TMUX, TMUX_PANE) and agent (RUN_AGENT_FROM)"""
    env = dict(os.environ)
    ce = claude_environ()
    for k in ("TMUX", "TMUX_PANE", "PATH", "SHELL", "HOME"):
        if ce.get(k) and not env.get(k):
            env[k] = ce[k]
    argv = claude_argv()
    if "--agent" in argv[:-1] and not env.get("RUN_AGENT_FROM"):
        env["RUN_AGENT_FROM"] = argv[argv.index("--agent") + 1]
    return env


def _cwd() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def _run(args: list[str], stdin: str | None = None) -> str:
    r = subprocess.run([S, *args], capture_output=True, text=True, env=_env(), cwd=_cwd(), input=stdin)
    out = ((r.stdout or "") + (r.stderr or "")).rstrip("\n")
    return out or ("done" if r.returncode == 0 else f"exit {r.returncode}")


def _since_claude_start_ms() -> int:
    """ms between the parent claude process's start (/proc stat starttime) and now; -1 when unknown"""
    try:
        st = open(f"/proc/{os.getppid()}/stat").read().rsplit(")", 1)[1].split()
        ticks = int(st[19])  # field 22, clock ticks since boot
        up = float(open("/proc/uptime").read().split()[0])
        return int((up - ticks / os.sysconf("SC_CLK_TCK")) * 1000)
    except (OSError, ValueError, IndexError):
        return -1


def _record_env() -> None:
    os.makedirs(jobs_mod.HOME, exist_ok=True)
    ce = claude_environ()
    with open(os.path.join(jobs_mod.HOME, "mcp-env.txt"), "a") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S%z')} pid={os.getpid()} ppid={os.getppid()} "
                f"own TMUX={os.environ.get('TMUX', '')!r} own TMUX_PANE={os.environ.get('TMUX_PANE', '')!r} "
                f"claude TMUX_PANE={ce.get('TMUX_PANE', '')!r} CLAUDE_PROJECT_DIR={os.environ.get('CLAUDE_PROJECT_DIR', '')!r} "
                f"cwd={os.getcwd()!r} ready_ms={int((time.time() - T0) * 1000)} "
                f"since_claude_start_ms={_since_claude_start_ms()}\n")


@mcp.tool()
def schedule(agent: str, prompt: str = "", dir: str = "", model: str = "", effort: str = "", at: str = "",
             dry: bool = False) -> str:
    """Run `claude --agent <agent> "<prompt>"` through run-agent: now (this replaces the calling tmux pane) or at a
    time (`at`: the same words as /run-agent, e.g. "in 10 min", "after window", "tomorrow 9am"; returns the
    `scheduled #N ...` line). dir = folder to start in; model/effort as for claude; dry=True only prints what
    would run."""
    words = [agent]
    if prompt:
        words.append('"' + prompt.replace('"', "'") + '"')
    if dir:
        words += ["in", dir]
    if model:
        words.append(model)
    if effort:
        words.append(effort)
    if at:
        words.append(at)
    if dry:
        words.append("dry")
    return _run(["--relaunch", " ".join(words)])


@mcp.tool()
def cancel(id: int) -> str:
    """Cancel pending run-agent job #id (any job, whoever made it). Returns run-agent's `cancelled #id` line."""
    return _run(["--cancel", str(id)])


@mcp.tool()
def jobs() -> str:
    """List the pending run-agent jobs (id, command, time, runner state)."""
    return _run(["--jobs"])


@mcp.tool()
def handoff(prompt: str, done: str, in_progress: str, next: str, model: str = "", effort: str = "") -> str:
    """Usage-limit handoff: schedule `claude --agent worker "<prompt>"` after the usage window in the calling pane,
    append a "Stopped at usage limit" section (Done / In progress / Next) to plans/WORKER_NOTES.md and commit the
    project files as WIP. Returns the Note: / Commit: / Relaunch: lines."""
    args = ["--handoff", "worker", prompt]
    flags = []
    if model:
        flags += ["--model", model]
    if effort:
        flags += ["--effort", effort]
    if flags:
        args += ["--", *flags]
    text = f"Done: {done}\nIn progress: {in_progress}\nNext: {next}\n"
    return _run(args, stdin=text)


@mcp.tool()
def next(agent: str, prompt: str = "", run: bool = False) -> str:
    """The closing next step an agent ends its turn with: returns the three lines `run-agent.sh --next <agent>
    ["<prompt>"]` prints (a sentence, the `/run-agent` line, a `Without run-agent: claude ...` line) for the agent to
    print as they are. agent = worker | evaluator | planner | helper. run=True also starts that agent 2 s later in
    the calling tmux pane (this session is replaced); leave it False unless the user asked for the handoff to run."""
    args = ["--next", agent] + ([prompt] if prompt else [])
    out = _run(args)
    if not run:
        return out
    line = _builtins.next((x for x in out.splitlines() if x.startswith("/run-agent ")), "")
    if not line:
        return out + "\nnot started: no /run-agent line"
    env = _env()
    if not (env.get("TMUX") and env.get("TMUX_PANE")):
        return out + "\nnot started: the calling session is not inside tmux"
    # detached and delayed so this result reaches the session before its pane is replaced
    subprocess.Popen(["bash", "-c", 'sleep 2; exec "$0" --relaunch "$1"', S, line[len("/run-agent "):]],
                     env=env, cwd=_cwd(), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return out + f"\nrunning in 2 s: {line} (pane {env['TMUX_PANE']} is replaced)"


if __name__ == "__main__":
    if os.environ.get("RUN_AGENT_MCP_DEBUG") == "1":
        _record_env()
    mcp.run()
