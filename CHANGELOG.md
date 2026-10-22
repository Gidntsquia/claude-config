# Changelog

## Unreleased

- **run-agent: scheduled runs and forgiving parsing.** `/run-agent worker fable low effort at 9pm` (or `in 2h`, `after window` = when the 5-hour usage window resets, with `until 7am` to cap the wait) writes a job under `~/.claude/run-agent/jobs/` and starts a detached runner that respawns the pane into `claude --agent ...` at that time (a new tmux window if the pane is gone, a new session if the server is gone), so overnight runs start after the usage cap resets. `/run-agent jobs` lists pending runs, `/run-agent cancel [id]` drops one, `dry` shows the command and times without doing anything. The script now parses the arguments (`run-agent.sh --parse`): `model=fable`, `effort = low`, `—model` (em dash), `-model`, `opus+medium`, bare `fable`/`low effort`, curly quotes and newlines in the prompt all work, near-miss typos are auto-corrected (`fabel -> fable`) and shown, and only words it cannot place are asked about. `test.sh` has 129 checks including every `/run-agent` argument string found in the session transcripts (the five Haiku misreads first); mixed straight/curly quotes (`"I’m on my phone”`) now close properly.
- **report-writer agent** (model: Fable). `claude --agent report-writer "<data dir> — <question>"` turns collected study data into a short report: verdict, next action, the deciding number with n and spread, a "Wrong or missing" box, one chart and a decision table on the first screen; every figure traces to a file in the data dir through `numbers.json`. One run writes one `report.json`; `render.py` renders the desktop page and the 390 px phone cards from it, so both modes always agree. The decision chart is plain bars whose axis start the writer chooses per chart (`axis_min` + `axis_reason`; "(axis does not start at 0)" label and break marks when above zero). When a candidate is measured in more than one file the decision table uses the source with the most runs per arm. Every chart carries a written reading under it (who is ahead, by how much, clears the spread or not). The report opens with the problem being solved and why it is worth solving, before the verdict; the Wrong-or-missing box comes after the evidence as at most six one-line plain sentences, and card 1 says each figure once (check.py `first_once`). The prose follows the user's house style (the write-readme voice rules): plain spoken sentences; check.py `voice` fails contrasts, emphasis words, em-dashes, colon taglines, semicolon chains and a verdict made of fragments. Writes `plans/DATA_REQUEST.md` instead of a report when the data cannot decide (the worker collects and reruns, three loops at most). Eval fixture from the pogo GPU rounds 8–9 with planted traps, `check.py` and a rubric in `agents/evals/report-writer/`.
- **report-checker agent** (model: Opus). A second set of eyes the writer spawns through the Agent tool: answers the question cold from the data (`checker/cold.md`), then scans every claim and figure in the report for anything that looks off and recomputes only those (`checker/findings.json`). The writer revises only what was flagged, up to 2 loops; what stays open lands in the Wrong-or-missing box as "checker: …", and the report's last line says how many findings were raised, fixed and open. `bash agents/evals/report-writer/run.sh planted` proves it catches a shifted figure, a flipped verdict and a dropped trap.
- **Plane theme for the status line.** Set `CLAUDE_STATUSLINE_THEME=plane` and the squid becomes ✈️, with aviation easter eggs (runway race, delay board, baggage claim, Wright Brothers, Apollo launch, in-flight meal and more) at the same odds and story lengths as the squid ones. Unset, the squid status line is unchanged.
- `bash statusline.sh --preview [squid|plane]` lists every easter egg of a theme with its roll band and every step.
- `./install.sh --theme plane` adds `export CLAUDE_STATUSLINE_THEME=plane` to `~/.bashrc` (`~/.zshrc` on macOS) once.

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
