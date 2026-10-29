---
name: run-agent
description: Replace the current claude session (or open a brand-new tmux window, `split` / `window`; several runs joined by `+` share one new tiled window) with a new one running a chosen agent (helper, planner, worker, evaluator or a built-in) in the same tmux pane, now or at a time (`at 9pm`, `in 2h`, `after window` = when the 5-hour usage window resets, `until <time>` to cap the wait), in this directory or another one (`in <dir>`, created if missing). Loose phone typing is fine: `fable low effort`, `model=opus`, em-dash flags, typos. `jobs` lists scheduled runs, `cancel` drops one. User-invoked only.
argument-hint: <agent> ["prompt"] [in <dir>] [model/effort/claude flags...] [at <time> | in <delay> | after window [until <time>]] [split|window] [dry] [force] [+ <another run>...] | jobs | cancel [id]
---

# /run-agent

Run exactly one Bash call and then stop. Do not parse, reason about or confirm anything yourself: the script hands
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

(Also: `S --parse '<raw>'` prints the parse as JSON; `S --handoff <agent> ["prompt"] [-- flags]` is the worker's
usage-limit handoff; `S --next <agent> ["prompt"]` prints an agent's closing next step (sentence, `/run-agent` line, `claude` line); `bin/run-agent` is
the same skill as a shell command.)
