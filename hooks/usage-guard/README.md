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
| Parallel runs | more than 2 headless `claude` runs at once: `-j N`, `xargs -P N`, `parallel -j N`, `&` in a loop, several `&`, plus runs already going | `blocked by usage-guard: 4 parallel headless claude runs (max 2). Run: bash tests/agent-replay/run.sh -j 2` |
| Daily cap | more than 30 launches a day (ET) in a project; a suite counts one per scene | `blocked by usage-guard: 27/30 headless launches used today for assistant-agent; this adds 39. 3 left today: Run: bash tests/agent-replay/run.sh -j 1 a01 a02 a03` |
| Big run | 3 or more launches that take over half of what is left today: turned back once, nothing counted | `blocked by usage-guard: this takes 11 of your 18 left today. Pick fewer scenes, or send the same command again to confirm.` |
| Budget flags | a headless launch without `--max-budget-usd` or `--max-turns` | `blocked by usage-guard: headless claude launch lacks --max-turns. Add --max-budget-usd 0.50 --max-turns 15.` |
| Subagents at once | a 4th subagent while 3 run | `blocked by usage-guard: 3 subagents running (max 3); wait for one to finish` |
| Repeat subagent | a description, or a whole prompt, already dispatched today | `blocked by usage-guard: "Transcribe VOD igDPMTZCnwg" was already dispatched today at 9:24 PM; reuse its output` |
| Guard state | any command or edit that touches the guard's files, `settings.json`, `settings.local.json`, `worker.md`, or runs `guard allow` | `blocked by usage-guard: guard state is edited by the user only` |

A headless launch is `claude` (by any path, or through a variable set from `command -v claude`) with `-p`,
`--print`, `--agent` or `--bg`, or a script that starts one. Scripts are read (first 200 lines) and followed three
levels down, so `run.sh` → `scene.sh` → `drive.py` is seen. `claude --version`, `-h`, `auth` and `agents` are not
launches, and neither is text that only mentions `claude -p`: the arguments of `git commit`, `echo`, `printf`,
`grep` and `cat`, string literals inside a `python3 - <<E` heredoc, a heredoc written to a file the command does
not run, a `$(cat <<E … E)` commit message. Such a command counts 0 and runs at 30/30. A heredoc written to a path
and run in the same command (`cat > d.sh <<E … E; bash d.sh`) is read as that script, a `$(…)` whose command starts
a launch script counts that launch, and `env $vars "$REAL" -p` counts 1.

## What the worker is told

A block ends with a smaller command that fits, not with a way around the limit: the same script at `-j 2` (or
`-j 1` when one run is already going) for the parallel rule; the same script at `-j 1` with the first K scenes for
the daily cap, K being the launches left; `use checks that start no claude` at 0. No block names `guard allow`.

The worker sees its count while it fills:

- at session start: `usage-guard: 19/30 launches already used today for <project>, 11 left` (at 0 too);
- on every allowed launch, Bash or Agent: `usage-guard: 12/30 used today, 18 left`;
- on the launch that reaches 20, and again at 25: `usage-guard: 20/30 used, 10 left today: plan the remaining
  checks to fit`;
- a command of 3 or more launches that would take over half of what is left is refused once and counts nothing;
  the identical command sent again within 10 minutes runs.

After a launch command ends, a PostToolUse hook counts the headless sessions it really started (session files of
the project whose first record is newer than the command). If that is more than was counted, the count is raised,
the log gets a `RECOUNT` line and the worker is told.

A log line is cut at 120 characters. When the launch sits past the cut (`git commit -m "…" && bash run.sh -j 2`),
the line shows the first 50 characters, ` … `, then the part that launches, so a counted commit can be told from
a miscount. On 15 Nov eight such lines looked like edits and commits counted as launches; each ended in a real
`run.sh` call (`fixtures/nov15-commands.json` holds them in full).

For a script that builds the claude command itself, the worker can pass the flags through `CLAUDE_GUARD_FLAGS` when
the script reads that variable (`CLAUDE_GUARD_FLAGS="--max-budget-usd 0.50 --max-turns 15" bash run.sh -j 2 a01`),
or edit the script.

Subagents also count toward the 30. Every subagent a worker starts is rewritten to the `helper` type (40 turns,
low effort) and the hook sets its model on the call itself: Sonnet, or Haiku when the worker asked for Haiku. An
expensive request is logged as `model=opus requested, forced sonnet`. A model set on the call outranks the agent
file, so a `helper.md` a project supplies cannot raise it.

One type is left as it is: `report-writer`. A worker's `report-writer` subagent keeps its type and runs on Opus
(logged as `report-writer kept on opus`). It still counts 1 toward the 30, and the at-once and repeat rules apply.

`run-agent` starts every worker with `CLAUDE_CODE_SUBAGENT_MODEL=sonnet CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3
CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` is not set: under it Claude Code
ignores a model set on the call, and a `report-writer` subagent ran on Sonnet (checked on 2.1.325, 14 Nov). The
hook does the forcing instead. With depth 1 a `report-writer` subagent cannot start its own checker subagent; the
headless route (`claude -p --agent report-writer … --max-budget-usd N --max-turns N`) can.

## Your commands

```
guard status                 today's count, unlock, what is running (project of the current directory)
guard allow 2h               lift the parallel limit and the daily cap for this project (also: 45m, until 9pm)
guard revoke                 end the unlock now
guard log [n]                the last n decisions (default 20)
guard usage [today|week|YYYY-MM-DD] [project]
                             FE tokens and API dollars: main session / subagents / headless runs, by model,
                             and the five most expensive subagents
guard recount [n]            set today's count from the log's ALLOW and RECOUNT lines, or to n
```

`guard allow` and `guard recount` are yours alone: they refuse to run from inside a Claude session, and the hook
blocks a worker that types them. A past day's `guard usage` is saved on its first read
(`<project>/<date>.usage.json`); later calls answer from the save in under a second. While it is in force the budget and turn flags are still required. The longest unlock is 24 hours.

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
~/.cache/claude-guard/<project>/runs/<tool_use_id> an allowed launch command, until its PostToolUse recount
~/.cache/claude-guard/<project>/confirm/<hash>     a big run turned back once, waiting for the resend (10 minutes)
~/.cache/claude-guard/<project>/<date>.usage.json  a past day's `guard usage` totals
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
"PostToolUse":   [{"matcher": "Bash|Monitor", "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10}]}],
"SessionStart":  [{"hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10}]}],
"SubagentStart": [{"hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10}]}],
"SubagentStop":  [{"hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/usage-guard/usage_guard.py", "timeout": 10}]}]
```

Needs Claude Code 2.1.296 or later (`autoCompactWindow` in `helper.md`; hook input `agent_type`) and `python3` on
PATH. `onFailure: block` means a hook that cannot run blocks the tool: without `python3`, every Bash call of every
session is refused until the hooks are removed from `settings.json`.

To turn the guard off, delete those entries from `~/.claude/settings.json` (and the repo's `settings.json`).

## Tests

```
bash hooks/usage-guard/test.sh           286 cases in a temp HOME with a fake claude, then the Bash replay below
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
- The first `guard usage` of a past day reads every log of the project: 30 s to a few minutes on a large one
  (199 s for slay-the-spire-advisor on 15 Nov, 0.2 s after that).
- The PostToolUse recount needs real session files, so it sees nothing for a background command (it ends before
  the launches do) or a fake `claude`.
