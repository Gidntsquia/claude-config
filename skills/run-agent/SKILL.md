---
name: run-agent
description: Replace the current claude session with a new one running a chosen agent (helper, planner, worker, evaluator or a built-in) in the same tmux pane, now or at a time (`at 9pm`, `in 2h`, `after window` = when the 5-hour usage window resets, `until <time>` to cap the wait), in this directory or another one (`in <dir>`, created if missing). Loose phone typing is fine: `fable low effort`, `model=opus`, em-dash flags, typos. `jobs` lists scheduled runs, `cancel` drops one. User-invoked only.
argument-hint: <agent> ["prompt"] [in <dir>] [model/effort/claude flags...] [at <time> | in <delay> | after window [until <time>]] [dry] [force] | jobs | cancel [id]
---

# /run-agent — swap this session for `claude --agent <agent> ["<prompt>"]`, now or at a time

Script: `~/.claude/skills/run-agent/scripts/run-agent.sh` (call it `S`). The script parses the arguments; you never
parse flags, words or times yourself. Nothing runs until step 5 says yes, unless the parse says `force: 1`: then
step 5 is skipped and step 6 runs at once.

## 0. Scheduled runs: `jobs` / `cancel`
If `$ARGUMENTS` is `jobs` (or the user asks what is scheduled / pending): run `S --jobs` and relay the output as is
(`#<id>  <command>  at <time> ET (<words>, in Nh Mm)  [until <time>]`, or `no scheduled runs`). Stop.
If it is `cancel [id]` (or the user asks to cancel a scheduled run): with an id run `S --cancel <id>`; with none and
`S --jobs` showing one run, run `S --cancel`; with several and no id, AskUserQuestion which one (options from `S --jobs`),
then `S --cancel <id>`. Relay the script's line (`... #<id>  cancelled  <command>`). Stop.

## 1. Parse
Bash: `S --parse '<raw $ARGUMENTS>'` (single-quoted; escape `'` as `'\''`; keep newlines). It prints one JSON object:

| key | meaning |
|---|---|
| `agent`, `agent_ok` | agent name (typos already corrected); `agent_ok` false = not in `S --list` |
| `prompt` | the quoted prompt (straight or curly quotes), or the default `"."` for worker/evaluator/helper; `""` = none |
| `dir`, `dir_state`, `dir_typed` | resolved absolute dir and `exists`/`missing` (from `in <dir>`, `--cwd`, `-C`, a `/` or `~` token) |
| `flags` | claude flags in `--long` form, e.g. `--model fable --effort low` (from `fable low effort`, `model=fable`, `—model fable`, `opus+medium`, `with opus`, `yolo`, `resume`...) |
| `force`, `dry` | 1 = skip the Run? question (force words, `worker!`, trailing `!`); 1 = dry run (`dry`, `dry run`, `--dry-run`) |
| `at`, `at_text`, `at_shown` | run time as epoch, the words read (`at 9pm`, `in 1h30`, `after window`), and `9:40 PM ET (at 9:40pm, in 3h 12m)` |
| `until`, `until_shown` | cap for a window run (`after window until 7am`) |
| `reset`, `reset_shown` | the 5-hour usage window reset the script fetched (`8:20 PM ET`), when a time or `dry` was given |
| `at_error` | the usage API gave no reset: relay this line verbatim and stop; nothing is scheduled |
| `corrections` | near-miss words auto-corrected, `["fabel -> fable"]` |
| `unsure` | tokens it could not place |
| `error` | two directories or a bad path: relay the line and stop |
| `command`, `run` | the claude command for the confirmation; the exact `S ...` call for step 6 |

Accepted forms (so you can explain what was read): flags with `--`, `-`, `—`, `–`; `model=x`, `model: x`, `model x`,
a bare model word (fable, opus, sonnet, haiku); `effort=x`, `low effort`, `effort low`, a bare effort word (low, medium,
high, xhigh, max); `opus+medium`; commas as separators; times `at 9pm|9:30pm|21:40|2140|9`, `in 2h|90m|1h30|2 hours|45 min`,
`after window|after the window|next window|when the window resets|after reset|window`, `--at/--in/--after ...`,
`until <time>` after a window phrase.

## 2. Resolve what the script flagged
- `error` or `at_error` present: reply with that line and stop.
- `agent_ok` false: reply `unknown agent: <agent>` plus `S --list` output and stop. No agent at all (`agent` empty):
  with force reply `usage: /run-agent <agent> ["prompt"] [in <dir>] [flags...] [at <time>]` and stop; otherwise
  AskUserQuestion "Which agent?" (helper/planner/worker/evaluator first, built-ins named in the question text), then
  re-run `S --parse` with the agent prepended.
- `unsure` non-empty (even with force): one AskUserQuestion with your best reading as the first option, e.g.
  "I read `efort lo` as `--effort low`. Right?", options Yes / It is part of the prompt / Drop it. Then re-run
  `S --parse` with the string rewritten accordingly (the corrected words, or the token quoted into the prompt, or
  removed) and continue from step 2 with the new parse.
- `corrections` non-empty: nothing to ask; show them in the confirmation as `(read: fabel -> fable)`.

## 3. Directory
`dir_state` `missing` is allowed: the folder is created in step 6, never earlier. `S --resolve '<dir>'` is available
if you need to re-resolve one (prints `<absolute dir><TAB>exists|missing`, creates nothing).

## 4. Dry run (`dry: 1`)
Reply with the full `command`, the directory (`dir` or the cwd), the run time (`at_shown`, or `now`) and the usage
reset time (`reset_shown`), and stop. Schedule and run nothing. (`S --dry-run <run args>` prints the same from the
script alone.)

## 5. Confirm (every path without force)
AskUserQuestion, header "Run?" (or "Schedule?" with a time), question text exactly:
- now: `Replace this session with: <command>  (in <dir>[, will be created])?`
- with a time: `Schedule: <command> at <at_shown> (in <dir>[, will be created])?`
  e.g. `Schedule: claude --agent worker "." --model fable --effort low --name "worker: claude-config (fable)" at 2:40 AM ET (after window, in 3h 12m) (in /home/jaxon/files/claude-config)?`
- `until` set: append ` until <until_shown>` after `<at_shown>`.
- corrections: append ` (read: fabel -> fable, lo -> low)` before the final `?`.
- `--continue`/`resume` with a dir different from the cwd: append ` (note: --continue resumes the latest session in <dir>, not this one)`.
`<dir>` is the cwd when none was given. Options: "Yes, replace this session" / "No" (or "Yes, schedule it" / "No").
"No" -> reply exactly `nothing changed` and stop.

(`S --handoff <agent> ["prompt"] [-- flags]` is the worker's usage-limit handoff in one call: schedules the relaunch after the window (`--need-tmux` path, so outside tmux or without a reset time it still goes on), appends a `## Stopped at usage limit — <time> ET` section (stdin = Done / In progress / Next, then Uncommitted and `Relaunch: ...`) to `plans/WORKER_NOTES.md`, commits project files as `WIP: stopped at usage limit — ...`, and prints the `Note:` / `Commit:` / `Relaunch:` lines for the worker's final message; exit 0 in every handled case.)

## 6. Run or schedule
If `dir_state` is `missing`: `mkdir -p '<dir>'` first (only now, after Yes, or at once with force).
Then run the parse's `run` string with `S` expanded to the script path, unchanged.
- No time: exit 0 means the pane was respawned; this session is ending. Exit 1 = not inside tmux: relay its output
  (`not inside tmux; run: ...`) so the user can run it by hand. Exit 2: relay the message.
- With a time: the script writes `~/.claude/run-agent/jobs/<id>.json`, starts a detached runner that survives this
  session, prints `scheduled #<id>: <command> at 2:40 AM ET (after window, in 3h 12m)` and exits 0; this session
  continues. Relay that line and add: `S --jobs` lists it, `S --cancel <id>` drops it. For a window run the runner
  re-checks the reset at fire time and waits for it (one hour at most); the run then replaces this pane (new window in
  this tmux session if the pane is gone, new session if the server is gone), first line
  `scheduled run #<id> fired at <time> ET: <command>`. A `skipped: reset ... is after until ...` line means nothing
  was scheduled; relay it.
