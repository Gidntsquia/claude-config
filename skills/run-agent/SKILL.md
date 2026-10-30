---
name: run-agent
description: Replace the current claude session (or open a brand-new tmux window, `split` / `window`; several runs joined by `+` share one new tiled window) with a new one running a chosen agent (helper, planner, worker, evaluator or a built-in) in the same tmux pane, now or at a time (`at 9pm`, `in 2h`, `after window` = when the 5-hour usage window resets, `until <time>` to cap the wait), in this directory or another one (`in <dir>`, created if missing). Loose phone typing is fine: `fable low effort`, `model=opus`, em-dash flags, typos. `jobs` lists scheduled runs, `cancel` drops one. User-invoked only.
argument-hint: <agent> ["prompt"] [in <dir>] [model/effort/claude flags...] [at <time> | in <delay> | after window [until <time>]] [split|window] [dry] [force] [+ <another run>...] | jobs | cancel [id]
---

# /run-agent

Normally this skill never reaches a model: the `UserPromptExpansion` hook in `settings.json` (matcher `run-agent`)
runs `run-agent.sh --relaunch` on the typed words itself and shows its output. You are reading this only because the
hook did not run (older settings, hook disabled): then run exactly one Bash call and then stop. Do not parse, reason about or confirm anything yourself: the script hands
every question to a short haiku session (`claude --model haiku --effort low`) that asks, then runs or schedules.

```
~/.claude/skills/run-agent/scripts/run-agent.sh --relaunch '<raw $ARGUMENTS>'
```

Single-quote the arguments (escape `'` as `'\''`, keep newlines). Relay its output as is. Exit 0 means this pane
now runs the confirm step (or a new tmux window opened with it) or the script answered itself (`jobs`, `cancel`,
`dry`, errors); exit 1 = not inside tmux, relay the `run-agent ...` line to type by hand; exit 2 = relay the message.

Forms: `<agent> ["prompt"] [in <dir>] [split|window] [model/effort words] [at <time> | in <delay> | after window
[until <time>]] [dry] [force]`, `jobs`, `cancel [id]`. `split` and `window` both open a brand-new tmux window and
this session keeps going; without them the pane is replaced. A launch never adds a pane to an existing window.
Runs joined by a lone `+` (`planner "Plan A" in ~/a + planner "Plan B" in ~/b + ...`) start together, after one
confirm, in one new window tiled (four = 2x2), each in its own folder.

Time words resolve in `parse.py` without a model: `at 9pm`, `in 2h`, `in 2 hours 10 min`, `tomorrow [at] 1am`,
`1am tomorrow`, `tonight` / `this evening` (7 PM), `today at 5pm`, `noon`, `midnight`, a weekday name (the next one),
`after window`, `N h|min before|after the window` (or `… the current window`, `… window ends/resets`), `N h before|after
<clock>`. `jobs` shows each run's time and runner state (`sleeping (pid N)`, `dead`, `errored: <last log line>`,
`waiting: no pane`). When the parser cannot place a time word the haiku confirm step reads it (it is told the current
ET time and the window reset) and hands `--step '<words> | time: at <clock>'` back; it never asks the user when the
window ends. The window reset comes from the usage API; when that fails (429, no network) the last live answer, then an
estimate from session transcripts, then now + 5 h stand in, labelled, so a window-relative time always schedules. From an agent session (worker, evaluator, planner, helper) `split`, `window` and `+` are answered
`ignored: agents replace their own pane`: an agent only ever replaces its own pane, now or at the scheduled time; if
that pane is gone at fire time the run waits (`jobs.log`: `waiting: no pane`) until a human `/run-agent` or `run-agent`
call on that tmux server opens it in a new window.

(Also: `S --parse '<raw>'` prints the parse as JSON; `S --handoff <agent> ["prompt"] [-- flags]` is the worker's
usage-limit handoff; `S --next <agent> ["prompt"]` prints an agent's closing next step (short sentence, `/run-agent` line, `Without run-agent: claude …` line; no model/effort for worker and evaluator); `bin/run-agent` is
the same skill as a shell command.)
