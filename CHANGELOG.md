# Changelog

## Unreleased

- run-agent: a failed usage-API lookup never stops a run or a schedule and never shows as an error. A 429 is retried (1 s, 3 s); then the last live reset (cached in the state dir as `usage-reset.json` on every live answer) stands in while it is still ahead; then an estimate from session transcripts (first timestamp and last write of each recent session, 5-hour windows); then now + 5 h (no window open). `two hours before the window` schedules under all four, and the shown time names the source (`cached`, `estimated from session activity`, `assumed: …`). `dry` prints `usage reset: <time> (<source>)`, never `HTTPError`/`429` text.
- run-agent: `/run-agent` costs no tokens. A `UserPromptExpansion` hook in `settings.json` (matcher `run-agent`, 90 s timeout) runs `run-agent.sh --relaunch` on the typed words and shows its output in place of a model turn; the skill stays as the fallback when the hook is off. install.sh installs the hook with the settings merge and `--check` has a PASS/FAIL line for it, plus one for the health of pending scheduled runs.
- run-agent: time phrases resolve in `parse.py` without a model: `tomorrow at 1am` (the next calendar day), `1am tomorrow`, `tonight` / `this evening` (7 PM), `today at 5pm`, `noon`, `midnight`, weekday names, `in 2 hours 10 min`, `two hours before the window`, `1 hr before the current window`, `30 min after the window ends`, `2 h before 9pm`. The shown time names the derivation: `6:20 PM ET (two hours before window 8:20 PM, in 20m)`. A time already past is an error, not a question.
- run-agent: the haiku confirm step owns no logic. It gets the current ET time and the window reset in its prompt, has only AskUserQuestion and one Bash form (`run-agent.sh --step '<words>'`), appends every answer verbatim after ` | `, and the script decides: ask once about a word it cannot place (`Part of the prompt` / `Drop it`), resolve an unparsed time phrase itself (`| time: at 5:30 AM`), schedule, or after three answers without a run reply `nothing changed` and the words to type by hand. It never asks when the window ends and never reads a word next to a time word as a flag. The confirm session is named `run-agent: <agent> <folder> [at <time>]`, runs with `--session-id`, and its transcript is deleted when it exits, so `claude --resume` stays clean.
- run-agent: a scheduled run is a fixed five-line sleeper that `exec`s the repo's `runner.sh` as it is at fire time, so editing or committing under `skills/run-agent` while runs sleep changes nothing until they fire; it never sleeps a negative time, and one that wakes less than an hour late fires at once (`jobs.log`: `fired late`). `/run-agent jobs` shows each runner's state: `sleeping (pid N)`, `dead`, `errored: <last runner.log line>`, `waiting: no pane`; `run-agent.sh --health` exits 1 (and `install.sh --check` prints FAIL) when a pending runner is dead or errored.
- run-agent: only a human may open tmux windows. From an agent session (`--agent` on the parent claude, or `RUN_AGENT_FROM`), `split`, `window` and `+` are answered `ignored: agents replace their own pane`; immediate and scheduled runs replace the agent's own pane, and when that pane is gone at fire time the run waits (`waiting: no pane`) until the next human `/run-agent` or `run-agent` call on that tmux server starts it in a new window.

- run-agent: `/run-agent` is one Bash call now. `SKILL.md` shrank to `run-agent.sh --relaunch '<args>'`, which answers `jobs`, `cancel`, `dry` and errors itself and hands every confirmation to a short `claude --model haiku --effort low` session in the same pane. A launch either replaces the calling pane or opens a brand-new tmux window: `split` and `window` both open a new window holding only the agent, and nothing is ever added to an existing window (scheduled runs too).
- run-agent: several runs joined by `+` start together after one confirm, in one new tmux window tiled (four = 2x2), each in its own folder: `/run-agent planner "Plan part A" in ~/a + planner "Plan part B" in ~/b + …`. Works the same from the `run-agent` shell command.
- `bin/run-agent` is the same thing as a shell command (confirms with `read`, or a tmux popup); install.sh links it into `~/.local/bin` and `--check` has a line for it.
- The planner, worker and evaluator end with their next step (`run-agent.sh --next`): a sentence saying what to run and when, the `/run-agent <agent> "<prompt>" <model> <effort>` line on its own, then the plain `claude --agent …` form on its own labelled line.
- `bin/run-agent` confirms in the terminal again on Python 3.14 (opening `/dev/tty` read-write failed, so it fell back to a popup and changed nothing).
- run-agent: scheduled runs survive a reboot or WSL restart. `run-agent-revive.service` (a systemd user service install.sh enables; the shell rc on macOS) runs `run-agent.sh --revive` at boot, silently: a run still ahead gets a new runner, and one that came due while the machine was down is skipped and logged as `skipped` in `jobs.log`. After a tmux restart the run opens a new window instead of reusing an old pane id. `/run-agent jobs` marks runs whose runner is gone.

## v1.2.1 — 2026-10-26

Installing this setup is now one sentence to Claude, and the install adds to what you already have instead of replacing it. Everything since v1.2.0 (2026-10-25) is here.

### Highlights ✨

- Paste `Install https://github.com/Gidntsquia/claude-config following its INSTALL.md` into Claude Code. Claude clones the repo to `~/.claude-config`, asks four questions (projects folder, terminal setup, status line, settings), runs the install, checks it and gives a five-step tour that ends with your first project.
- iTerm2 no longer crashes on a Mac that isn't mine. Older installs pointed iTerm2's whole preferences at this repo, with profiles for folders only my Mac has. The install now adds one "Claude tmux" profile and undoes the old setting.
- Your files win by default. `settings.json` is merged (your values stay, lists like `permissions.deny` are combined, the original is kept as `settings.json.pre-link`), your CLAUDE.md is left alone, and an agent or skill with the same name as one of mine stops the install so you choose: keep yours, use mine, or skip.
- Every push runs the install on Ubuntu, macOS and Windows in GitHub Actions, in an empty `~/.claude` and in one that already has its own settings, CLAUDE.md and planner agent. `test/docker-install.sh` runs the same two cases on a fresh Ubuntu, and `test/windows-sandbox/` on a clean Windows with WSL.

### Install 🧰

- `install.sh` takes `--projects`, `--terminal`, `--default-profile`, `--statusline squid|plane|keep`, `--settings merge|keep|replace` and `--agent-clash keep|replace|skip` (or per name, `planner=keep`). `--theme` still works.
- Choices are saved in `~/.claude/claude-config.json`. Running `./install.sh` with no flags reapplies them and prints "reusing saved choices".
- `./install.sh --check` prints one PASS, FAIL or SKIP line per installed item, including `claude doctor`, the status line preview, tmux, the Windows Terminal or iTerm2 profile and the volume task, and exits 1 on any FAIL.
- Terminal setup is a choice now. Without `--terminal` the install leaves tmux, starship, `.tmux.conf` and terminal profiles alone. With `--default-profile` it also makes the tmux profile the one new windows open with, and prints how to undo it.
- Native Windows without WSL installs the agents, skills, settings and CLAUDE.md from Git Bash and says what it skipped (status line, tmux, terminal setup).
- tmux-quad moved to `bin/` and opens its panes in your projects folder, falling back to your home folder.
- No file in the repo names my home folder anymore. Windows paths come from `%USERPROFILE%` and `%LOCALAPPDATA%`, and `wsl/local-tools/win-app.sh` finds Firefox, VS Code and Windows Terminal.

### Agents 🤖

- report-writer finds Playwright through `$PLAYWRIGHT_DIR`, the project's `node_modules`, your projects folder or the global npm folder, and says what to install when none has it.
- evaluator opens Firefox and VS Code through `win-app.sh`, and helper starts your first project in your projects folder, instead of using paths from my PC.

### Settings ⚙️

- The default model in `settings.json` is Sonnet. With the merge, your own `model` stays.
- `UPDATING.md` finds the clone through `~/.claude/claude-config.json`, so it works when `settings.json` is merged rather than linked.

### Known issues

- The Windows Sandbox test needs nested virtualization for WSL inside the Sandbox, which some PCs don't have.

### Agent versions 📄

- planner.md at 19ecb18 (2026-10-23)
- worker.md at 8206204 (2026-10-24)
- evaluator.md at 36b2e06 (2026-10-26)
- helper.md at 36b2e06 (2026-10-26)
- report-writer.md at 36b2e06 (2026-10-26)
- report-checker.md at 06a0875 (2026-10-25)

## v1.2.0 — 2026-10-25

A week of new skills and two new agents for writing reports, and every session now uses the one-hour prompt cache. Everything since v1.1.0 (2026-10-15) is here.

### Highlights ✨

- `/write-report` is a new skill for anything that compares or measures two options. It offers the report-writer agent, which turns a folder of study data into a short report that leads with the verdict and traces every figure back to a file, and has the report-checker agent read it a second time.
- `/run-agent` can schedule a run with `at 9pm`, `in 2h` or `after window`, and it understands loose phone typing such as `model=fable` or `fabel`. When the worker hits the usage limit it saves its work with a short note and schedules its own relaunch for when the window resets.
- `/restore-sessions` was rebuilt. It reopens one session per project with the model each one had, shows every tmux window in its own terminal, looks back 60 minutes from the stop and skips sessions you closed with `/exit`.

### Skills 🧰

- write-report is loaded by the planner when a plan compares or benchmarks something.
- run-agent: `until 7am` caps how long a scheduled run waits. If the pane is gone by then, the run starts in a new tmux window. `/run-agent jobs` lists the waiting runs and `cancel` drops one. `dry` shows the command and the start time without running anything. The script reads the arguments itself (`--parse`), fixes near-miss typos and shows the fix, and asks only about words it can't place. `--need-tmux` stops early outside tmux, and `--handoff` does the worker's usage-limit steps in one call.
- restore-sessions opens restored windows with the Ubuntu Windows Terminal profile, and they no longer stay always on top. It leaves out empty sessions, and `keep <id>` brings one back.
- weekly-roundup prices Sonnet 5.5 cache reads at 0.05x input and adds the Oct 11-18 week to the archive with its own project colors.

### Agents 🤖

- report-writer (model Fable) writes the report page and phone cards with the verdict, the deciding number, one chart and a list of what could be wrong. When the data can't decide, it writes `plans/DATA_REQUEST.md` with what to measure, and the worker collects it and reruns.
- report-checker (model Opus) answers the question cold from the data, then checks every claim and figure in the report and writes findings. The writer fixes what was flagged over up to two loops, and anything still open is listed in the report..
- worker writes a three-line note and a WIP commit at the usage limit. `docs/agent-style.md` lists the house rules for agent files, each with the Anthropic guidance it comes from.
- evaluator has a phone path. `claude --agent evaluator "phone"` shows each item as a phone-sized picture and opens no windows. The window-control rules moved into the agent file, and the file is shorter with every rule kept.
- helper knows the git-init fix for the MCP approval dialog that keeps coming back, and says the cache stays warm for about an hour.
- planner has the Skill tool and calls for a report-writer report when a plan compares or measures something.

### Settings ⚙️

- Default model is Opus.
- Main sessions and subagents use the one-hour prompt cache, including report-writer and report-checker. `promptCacheTtl` and `subagentPromptCacheTtl` are both `1h`, and `ENABLE_PROMPT_CACHING_1H` is set as a backup.
- `autoContinueAtUsageLimit` is off, so the worker's scheduled relaunch is the only thing that restarts work when the usage window resets.
- Deny rules hide the planner, worker, evaluator and helper from the Agent tool, since they run as main sessions.
- The `run-agent.sh` Bash call is allowed, so auto mode doesn't block the worker's handoff.
- The status line has a plane theme. Set `CLAUDE_STATUSLINE_THEME=plane` or run `./install.sh --theme plane`, and `bash statusline.sh --preview plane` lists every easter egg.
- `UPDATING.md` has the steps for an AI to update your clone to the latest release.

### Known issues

- None known.

### Agent versions 📄

- planner.md at 19ecb18 (2026-10-23)
- worker.md at 8206204 (2026-10-24)
- evaluator.md at 7a8394b (2026-10-23)
- helper.md at 06a0875 (2026-10-25)
- report-writer.md at 06a0875 (2026-10-25)
- report-checker.md at 06a0875 (2026-10-25)

## v1.1.0 — 2026-10-15

Full release of all four agents, plus new skills and a leaner Claude Code setup. Everything since v1.0.0 (2026-10-09) is here, including the Windows fixes from @dotcomstar.

### Highlights ✨

- **Helper agent added.** `claude --agent helper` guides beginners through the planner, worker and evaluator workflow.
- **`/run-agent` added.** Swap your current tmux session for any agent without leaving the pane.
- **Overall improvements to Worker / Evaluator / Planner.** Workers finish the plan, evaluators show results faster, and the planner now suggests the exact `claude --agent <name> "."` command to start the next session.

### Helper 🧭

- New agent for people starting out. Asks where you are in the workflow, then helps one step at a time in plain English.
- Answers only from the agent files, the wiki and the Claude Code docs, which it reads through the new helper-wiki MCP server.
- Walks first-time users through the setup page one section at a time, with pictures, using `~/my-first-app` as the example folder.

### Worker 🔧

- Keeps building until everything in the plan that isn't blocked is done, including after you give feedback. Anything it's unsure about is left for the evaluator.
- Never ends on "not checked" or "did not view", re-checks earlier criteria, and no longer asks permission for plan work.

### Evaluator ⚡

- Opens every item before the first question and places it next to the terminal the moment you answer. It only moves windows it opened and puts your terminal back exactly as it was.
- Points the planner at `plans/EVAL.md` when a change is too big, and suggests `claude --agent <name> "."` so the next session starts immediately.

### Planner 📝

- Builds the plan from menu questions, where each option is a specific idea and one is the default.
- Suggests `claude --agent <name> "."` for the next step.

### Skills 🧰

- **run-agent:** `/run-agent <agent> ["prompt"]` swaps the tmux pane's session for the chosen agent. `in <dir>` starts it in another folder (created after you say Yes), force words (`force`, `-f`, `now`, `go`, `worker!`) skip the question, sessions are named `<agent>: <repo folder> (<model>)`, and the planner with no prompt starts with an empty input box.
- **restore-sessions:** reopens the Claude sessions a Windows Update restart or WSL stop killed, in a tmux layout you approve.
- **weekly-roundup:** usage-by-day chart, per-person color palettes, pooling usage across machines on one account, double-tap a pie slice to jump to its deep dive, Haiku 5.5 pricing, and Windows fixes by @dotcomstar (PR #2).

### Settings and context trimming ✂️

- Default model is Sonnet. The dangerous-mode permission prompt is skipped.
- Workflow tool denied, `skillOverrides` hide unused skills, and claude.ai MCP servers are off, to save context.
- The tag `pre-trim-2026-10-08` is the way back to the config before the trimming.

### Known issues

- None known: the weekly-roundup tests (18) and run-agent tests all pass at this tag. PR #2 reported `test_shared_project_keeps_other_machine` failing on its own; it passes after the merge.

### Agent versions 📄

- planner.md — 2edf13f (2026-10-08)
- worker.md — 618d56b (2026-10-10)
- evaluator.md — 4063712 (2026-10-11)
- helper.md — 1985699 (2026-10-11)

## v1.1.0-beta.1 — 2026-10-12

Pre-release of all agents at b19fa96.

- New helper agent that guides beginners through the planner, worker and evaluator workflow.
- The worker finishes plans more reliably.
- The evaluator shows results faster and places its windows next to the terminal.
- The planner asks menu questions to build the plan.

### Helper 🧭

- New agent, run with `claude --agent helper`. Asks where you are first, answers only from the agent files, the wiki and the Claude Code docs (via the helper-wiki MCP server), and walks first-timers through setup with pictures.

### Worker 🔧

- Keeps building until everything in the plan that isn't blocked is done, including after feedback. Doubts are left for the evaluator.

### Evaluator ⚡

- Opens every item before the first question and places it next to the terminal as soon as you answer. Only moves windows it opened and restores your terminal.

### Planner 📝

- Builds the plan from menu questions with a marked default; uses the preferred stack if none is named (React + TypeScript + Vite + Tailwind + shadcn/ui with Bun, or Python with uv, FastAPI and PostgreSQL).

Agent versions: planner 2edf13f (2026-10-08), worker 618d56b (2026-10-10), evaluator 4063712 (2026-10-11), helper 1985699 (2026-10-11).

## v1.0.0 — 2026-10-09

All current config files (settings, skills, statusline, install scripts, iTerm2, WSL), with these agent definitions:

- planner.md: original, from 52646fe (2026-09-19)
- worker.md: from ae9707d (2026-09-19), pinned to Sonnet at low effort
- evaluator.md: from e083934 (2026-09-27), Opus at medium effort; the version used from 2026-09-27 to 2026-10-07

The trial evaluator-new agent is left out.
