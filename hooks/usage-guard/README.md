# usage-guard

A hard stop on the worker agent's expensive launches. It is a Claude Code hook: plain Python 3 (standard library),
no network, no model call. The same input always gets the same answer.

It exists because of two weeks in which a worker spent most of the weekly allowance by itself: 47 full runs of a
39-scene `claude -p` suite at `-j 4` in three days, and 63 subagents (many at once, two of them repeats) in one
week. Instructions in the worker's prompt did not stop either. A hook does: a blocked command never runs.

## What it blocks

It acts only in a session started as `claude --agent worker`, and in that session's subagents. Every other
session (you, the planner, the evaluator) is untouched and nothing is logged for it.

| Rule | Blocked | The line the worker sees |
| :- | :- | :- |
| Parallel runs | more than 2 headless `claude` runs at once: `-j N`, `xargs -P N`, `parallel -j N`, `&` in a loop, several `&`, plus runs already going | `blocked by usage-guard: 4 parallel headless claude runs (max 2). Run -j 2 or one scene; ask the user to run `guard allow` for a full suite.` |
| Daily cap | more than 30 launches a day (ET) in a project; a suite counts one per scene | `blocked by usage-guard: 28/30 headless launches used today for assistant-agent; this adds 39. ...` |
| Budget flags | a headless launch without `--max-budget-usd` or `--max-turns` | `blocked by usage-guard: headless claude launch lacks --max-turns. Add --max-budget-usd 0.50 --max-turns 15.` |
| Subagents at once | a 4th subagent while 3 run | `blocked by usage-guard: 3 subagents running (max 3); wait for one to finish` |
| Repeat subagent | a description, or a whole prompt, already dispatched today | `blocked by usage-guard: "Transcribe VOD igDPMTZCnwg" was already dispatched today at 9:24 PM; reuse its output` |
| Guard state | any command or edit that touches the guard's files, `settings.json`, `settings.local.json`, `worker.md`, or runs `guard allow` | `blocked by usage-guard: guard state is edited by the user only` |

A headless launch is `claude` (by any path, or through a variable set from `command -v claude`) with `-p`,
`--print`, `--agent` or `--bg`, or a script that starts one. Scripts are read (first 200 lines) and followed three
levels down, so `run.sh` → `scene.sh` → `drive.py` is seen. `claude --version`, `-h`, `auth` and `agents` are not
launches, and neither is text that only mentions `claude -p` (a grep, a heredoc, a commit message).

For a script that builds the claude command itself, the worker can pass the flags through `CLAUDE_GUARD_FLAGS` when
the script reads that variable (`CLAUDE_GUARD_FLAGS="--max-budget-usd 0.50 --max-turns 15" bash run.sh -j 2 a01`),
or edit the script.

Subagents also count toward the 30. Every subagent a worker starts is rewritten to the `helper` type (Sonnet, 40
turns, low effort) and an expensive `model` request is dropped; the log line says
`model=opus requested, forced sonnet`. `run-agent` starts every worker with
`CLAUDE_CODE_SUBAGENT_MODEL=sonnet CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3
CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`, so Claude Code enforces the same limits itself.

## Your commands

```
guard status                 today's count, unlock, what is running (project of the current directory)
guard allow 2h               lift the parallel limit and the daily cap for this project (also: 45m, until 9pm)
guard revoke                 end the unlock now
guard log [n]                the last n decisions (default 20)
guard usage [today|week|YYYY-MM-DD] [project]
                             FE tokens and API dollars: main session / subagents / headless runs, by model,
                             and the five most expensive subagents
```

`guard allow` is yours alone: it refuses to run from inside a Claude session, and the hook blocks a worker that
types it. While it is in force the budget and turn flags are still required. The longest unlock is 24 hours.

The status line shows `guard 7/30 12.4M FE` once a project has a counted launch today, and
`guard 7/30 12.4M FE unlocked→21:00` during an unlock. At zero it shows nothing.

## Files

```
~/.cache/claude-guard/log                          every decision: time (ET) | project | ALLOW/BLOCK | count | command | reason
~/.cache/claude-guard/<project>/<date>.count       launches counted today (ET date)
~/.cache/claude-guard/<project>/<date>.dispatched  subagent tasks allowed today (for the repeat check)
~/.cache/claude-guard/<project>/<date>.fe          today's FE tokens, for the status line
~/.cache/claude-guard/<project>/allow              unlock: expiry (epoch, then ET text)
~/.cache/claude-guard/<project>/live/<agent_id>    one file per running subagent (ignored after 2 hours)
~/.cache/claude-guard/sessions/<session_id>        sessions known to be worker sessions
```

The project is the name of the git root above the working directory (the directory itself outside a repo).

## Install

`install.sh` links `~/.claude/hooks/usage-guard` to this directory and `~/.local/bin/guard` to `guard`, and the
repo's `settings.json` carries the hooks:

```json
"PreToolUse": [
  {"matcher": "Bash|Monitor", "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10, "onFailure": "block"}]},
  {"matcher": "Agent", "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10, "onFailure": "block"}]},
  {"matcher": "Edit|Write|NotebookEdit", "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10, "onFailure": "block"}]}
],
"SubagentStart": [{"hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10}]}],
"SubagentStop":  [{"hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10}]}]
```

Needs Claude Code 2.1.296 or later (`autoCompactWindow` in `helper.md`; hook input `agent_type`) and `python3` on
PATH. `onFailure: block` means a hook that cannot run blocks the tool: without `python3`, every Bash call of every
session is refused until the hooks are removed from `settings.json`.

To turn the guard off, delete those entries from `~/.claude/settings.json` (and the repo's `settings.json`).

## Tests

```
bash hooks/usage-guard/test.sh           150 cases in a temp HOME with a fake claude, then the Bash replay below
python3 hooks/usage-guard/replay_bash.py <log dir> [--all] [-v]
                                         real Bash commands from a project's logs through the hook; by default
                                         the assistant-agent commands since Nov 4 (51 of 51 full-suite -j 4 runs blocked)
python3 hooks/usage-guard/replay_agents.py
                                         the 63 Agent launches of Oct 25-31 (Spire) through the hook, one row each
```

None of them starts a real `claude`: the only one on PATH is a fake that exits 99 and leaves a marker, and each test
fails if the marker appears. `--now <epoch>` and `--live <n>` on the hook's command line set the clock and the
number of running headless processes for these tests; the installed command passes neither, and no environment
variable changes what the hook decides.

## Limits

- The scanner reads shell text; it does not run it. A launch hidden well enough (a script generated and run in two
  separate commands is still caught; a base64 blob piped to a shell is not) gets through. It is a seat belt against
  a worker that is not trying to cheat, with the guard-state rule for the obvious cheats.
- A script that can launch is treated as launching whatever subcommand is given (`e2e.sh clean` is held to the same
  flags as `e2e.sh run`).
- An unknown list size (`while read`, `$SCENES`) is assumed to be more than 2 when run in parallel.
- Two descriptions that match exactly are a repeat even when the prompts differ, so a worker that names two
  different tasks the same way must rename one.
- `guard usage` for a past day reads every log of the project and can take most of a minute on a large one.
