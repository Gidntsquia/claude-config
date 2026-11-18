# v1.3.0-beta.3 — 2026-11-18

Six things are new since v1.2.1 (2026-10-26), listed in no order of importance. This is a pre-release for testing, and v1.2.1 stays the latest release until it's promoted.

## Highlights ✨

- The worker can build while you're away. It never stops on a question, writes a blocker down as the command it ran and its error, schedules its own relaunch when only waiting is left, and every agent ends with its next step.
- `/run-agent worker` swaps the Claude session in a tmux pane for another agent, at once or at a time like `in 2h`. Agents call it through an MCP server so auto mode never blocks a handoff, and scheduled runs survive a reboot.
- usage-guard stops a worker before it starts too many headless `claude` runs or subagents at once, or more than 30 launches a day per project. The worker sees its count after every launch, and the `guard` command shows it or lifts the limit.
- The report-writer writes an outline before any prose, keeps each middle section on what you asked, and draws a table, split bar or pair where numbers compare. A run that can't build a report ends with one line saying what to run.
- The defer-artifact mod keeps the Artifact tool's 38 KB schema out of every session and subagent until you ask for an artifact, when Claude loads it through ToolSearch. Measured here, a subagent's first request drops from 22,565 to 10,093 tokens.
- The new assistant agent runs your tmux sessions from one chat. It reports where each project is, starts an agent in a free pane, answers a waiting session and schedules runs, and a guard hook keeps it away from your own panes.

## Agents 🤖

- When a requirement depends on a fact the planner can't know, it sends the question to up to three `researcher` subagents at once and saves their findings in `plans/research/`.
- There is one planner again. planner-fix10's prompt is now `planner.md`, and the planner-fix10 and planner-fix32 variants are deleted.
- When a command is denied, the worker writes it under `## Denied` in `plans/WORKER_NOTES.md` and tries two other routes before it calls the step blocked. Its last message never ends on a question.
- The worker gets reports from the report-writer through `skills/write-report/SKILL.md` and reruns the writer on what its last line names.
- On the desktop the evaluator opens every item hidden first, asks "Ready for me to move windows and start?", and shows each item when its question comes up. `plans/EVAL.md` quotes a `no-flash:` line saying whether any window showed early.
- The evaluator opens files as pages in Firefox, a `.md` rendered and anything else as numbered text, and no longer opens VS Code.
- A worker's subagents run as `helper` on Sonnet, except the report-writer, which stays on Opus.

## run-agent 🔁

- The run-agent MCP server has five tools (`next`, `schedule`, `handoff`, `jobs`, `cancel`) that auto mode allows by rule. The agents use them and keep the Bash form as the fallback.
- A typed `/run-agent` costs no tokens: a hook runs it in place of a model turn.
- A `/run-agent` line runs without a confirm question. Add `confirm` to be asked first.
- Time phrases like `tomorrow at 1am`, `in 2 hours 10 min` and `two hours before the window` are read without a model, and the scheduled line says how the time was worked out.
- `+` joins runs into one new tmux window, tiled side by side, and `window` or `split` opens one agent in a new window.
- Scheduled runs survive a reboot or WSL restart. A run that came due while the machine was off is skipped and logged.
- `run-agent jobs` shows each runner's state and the runs that failed since you last looked, and `run-agent clean` deletes job files older than 30 days.
- `test.sh` can no longer touch a live tmux pane.

## Install 🧰

- `install.sh` registers the run-agent MCP server for every session, and `--check` has a line for it and one for the assistant. When `claude` isn't on PATH it prints the `claude mcp add` command to run later.
- `install.sh` links `run-agent` and `guard` into `~/.local/bin` and installs the usage-guard and `/run-agent` hooks with the settings merge.
- A settings merge into a `settings.json` that already has its own `hooks` keeps your hooks and adds the repo's, and the install test covers that case.
- The install workflow on Ubuntu, macOS and Windows runs when a release is published.
- On Windows, a second `./install.sh` no longer stops on a settings.json with an em dash or emoji (Python read it as cp1252), and `--check` reads the defer-artifact entry in Claude Code's `;`-separated plugin list. Where systemd won't enable the reboot service (CI runners, containers), `install.sh` adds the restart line to your shell rc. The install workflows of v1.3.0-beta.1 and beta.2 found these.

## Settings ⚙️

- `settings.json` allows six narrow run-agent Bash rules and `mcp__run-agent__*`, so auto mode never sends a run-agent call to the classifier. The installed copy names your clone's own path in those rules.
- `autoMode.allow` keeps Claude Code's defaults and adds one sentence describing run-agent.

## Known issues

- This is a pre-release under test. UPDATING.md's step 3 skips it, so set `TAG=v1.3.0-beta.3` by hand to install it.
- usage-guard needs Claude Code 2.1.296 or newer and defer-artifact needs 2.1.293 or newer. Run `claude update` first.
- A session's first second or two can start before the run-agent MCP server connects. The agents use the Bash form then.
- With `--agent-clash keep`, the repo's assistant is installed as a copy outside the clone and can't find its MCP server. Use `--agent-clash replace` or `skip` for it.
- The Windows Sandbox test needs nested virtualization for WSL inside the Sandbox, which some PCs don't have.

## Agent versions 📄

- planner.md at 751a899 (2026-11-17)
- worker.md at a839db2 (2026-11-18)
- evaluator.md at a839db2 (2026-11-18)
- helper.md at 723ebb1 (2026-11-09)
- report-writer.md at 8c5b81a (2026-11-09)
- report-checker.md at 81cd4b6 (2026-11-06)
- researcher.md at 238bb09 (2026-11-18)
- assistant.md at 238bb09 (2026-11-18)
