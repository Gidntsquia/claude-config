# Changelog

## Unreleased

### One test command and written records 🧪

- `test/run` is the one test command, here and in CI: quick, machine and docker tiers on bats, ending `PASS <n> tests` or `FAIL <failed> of <n>`. The old `test/*.sh` scripts are gone.
- `test/features.txt` lists every feature; a test belongs to one by its tag, and a run fails when a feature has no test. A failing run names each failed test: `FAILED <feature>: <test name>`.
- `TESTING.md` is the one page: run, read a failure, add a test, what a pass means. Planted faults, repeated runs and the trust report are `bin/release/faults`, `bin/release/repeat <n>` and `bin/release/trust-report`.
- `ARCHITECTURE.md` and `.claude/CLAUDE.md` are new. `test/run` fails when they name a missing path or outgrow their caps.
- The README carries the last full run's result, written by `bin/release/trust-report all`.

### Evaluator on a Mac 🍎

- The evaluator now runs on a Mac as it does on a Windows PC. Its tools are split by OS: `local-tools/common/` installs everywhere, `local-tools/wsl/` on WSL and `local-tools/macos/` on a Mac. `wsl/local-tools/` is gone; `./install.sh` relinks.
- On a Mac each item opens at its question as a page in a separate Firefox: a file as its file page, a web page as itself, a terminal item as a snapshot page of its tmux session with colours kept. The line reads `shown: <id> <title> mode=firefox`.
- That Firefox runs on a fresh profile, so there is no welcome page and none of your tabs. It is closed when the next item is shown and at the end of the run. Your own Firefox is never signalled, and your terminal is never moved, resized or split.
- If Firefox is missing or does not stay up, the show prints `firefox failed: <reason>` and opens the page in your default browser (`mode=browser`), where it is yours to close.
- The tools need bash 3.2, `tmux`, `python3` and Firefox, and no Accessibility, Screen Recording or Automation permission.
- No picture is taken on a Mac: `evshow.sh path shown` prints `no picture (macOS)`.
- `agents/evaluator.md` has one Desktop helpers section for both computers. It says "window id" and quotes each helper's line as printed.
- `claude --agent evaluator "phone"` on a Mac sends the same pictures as on the PC: 780 px wide, a long page cut into 780x1688 parts. `phone-shot.sh` draws them with headless Firefox; Chrome and Playwright are not used there. When no picture comes the evaluator retries once, then sends the error line and goes on; it never makes one another way.

### Install 🧰

- On Windows without symlinks, rerunning `./install.sh` after an update now replaces the copies it made and you did not edit. Before, it kept the old copies as yours. Copies made by an earlier version are still kept: delete them once to get the new ones.
- `./install.sh --check` prints a PASS or FAIL line per evaluator tool, a FAIL for a tool of the other OS, and on a Mac a Firefox line (`WARN Firefox not installed: items open in the default browser, no phone pictures` when it is missing).
- New tests cover the evaluator tools against a stand-in Firefox, `tmux` and `open` (no window opened), real phone pictures from headless Firefox on a Mac, the author's own text, and installs on WSL and a Mac.

### The author's own text is out of what you install 🧹

- `CLAUDE.md` no longer tells Claude to commit and push to the config repo.
- write-readme takes the repo owner from `gh api user -q .login`, and asks you when that fails.
- The weekly-roundup's weeks live in `~/.claude/weekly-roundup/archive_weeks.json`, not in the repo.
- UPDATING.md says which four `autoMode.environment` entries to delete from a merged `settings.json`.

## v1.3.0 — 2026-11-25

1.3 improves the planner, worker and evaluator loop by adding three core features to it: run-agent, phone modes and the usage guard. Everything since v1.2.1 (2026-10-26) is here.

### Highlights ✨

- run-agent is now a main part of the workflow. The planner, worker and evaluator each end with the `/run-agent` line that starts the next agent in the same tmux pane, now or at a set time. Before, the next command was yours to type. 1.2 had an early form.
- Phone modes let you run the loop from your phone. `claude --agent evaluator "phone"` sends each item as a picture in the chat, the assistant sends a picture of the pane after each action, and reports come as phone-width cards. Before, a check needed you at the desktop.
- The usage guard reduces token waste. It's a hook that stops a worker before it starts more than 2 headless `claude` runs at once, 3 subagents at once or 30 launches a day in a project. Before, only the worker's prompt asked it to hold back.
- Planner, worker and evaluator fixes. The planner sends facts it can't know to up to three researcher subagents. The worker tries two other routes when a command is denied and never ends on a question. The evaluator opens every item hidden until its question comes up.
- Stability. Updating an install that has your own edits is now tested, and a Docker rehearsal types README's update sentence into Claude on an install of v1.2.1. The install workflow runs on every push. It still needs work, and Known issues says where.

### Agents 🤖

- The planner, worker and evaluator end with their next step in three lines: when to run it, the `/run-agent` line and the plain `claude --agent` line.
- There is one planner again. planner-fix10's prompt is now `planner.md`, and the two variants are deleted.
- The new assistant agent runs your tmux sessions from one chat and starts only in a project that links it.

### run-agent 🔁

- The run-agent MCP server has five tools (`next`, `schedule`, `handoff`, `jobs`, `cancel`) that auto mode allows by rule. The Bash form stays as the fallback.
- A typed `/run-agent` costs no tokens, because a hook runs it in place of a model turn.
- Scheduled runs survive a reboot or a WSL restart, and scheduling now works on macOS too.

### Install 🧰

- `install.sh` registers the run-agent MCP server, links `run-agent` and `guard` into `~/.local/bin`, and installs the usage-guard and `/run-agent` hooks with the settings merge.
- `install.sh` never makes a `.pre-link` copy. Your own agent, skill or command with one of this repo's names stays, and the run prints `kept yours: <path>`.
- New `bin/resolve-kept-edits.py` keeps your lines and adds the release's when an update stops on a conflict. UPDATING.md steps 6 and 7 run it.
- `UPDATING.md` has three new sections: "Coming from an install before v1.3", "Moving the clone" and "What no test covers".
- The run-agent and assistant MCP servers need `uv`, and Claude installs it during the update from 1.2.1.

### Settings ⚙️

- `settings.json` gains the usage-guard hooks, six narrow run-agent Bash rules and an allow rule for `mcp__run-agent__*`.
- The defer-artifact mod keeps the Artifact tool's schema out of every session until you ask for an artifact.

### Known issues

- usage-guard needs Claude Code 2.1.296 or newer and defer-artifact needs 2.1.293, so run `claude update` first.
- A session's first second or two can start before the run-agent MCP server connects.
- The Windows Sandbox test needs nested virtualization, which some PCs don't have.
- Stability still needs work. UPDATING.md's "What no test covers" names four things checked only by hand.

### Agent versions 📄

- planner.md at 751a899 (2026-11-17)
- worker.md at a839db2 (2026-11-18)
- evaluator.md at a839db2 (2026-11-18)
- helper.md at 723ebb1 (2026-11-09)
- report-writer.md at 8c5b81a (2026-11-09)
- report-checker.md at 81cd4b6 (2026-11-06)
- researcher.md at 238bb09 (2026-11-18)
- assistant.md at e472f6a (2026-11-18)

Every other change is on the wiki's [Release 1.3 Details](https://github.com/Gidntsquia/claude-config/wiki/Release-1.3-Details) page.

## v1.3.0-beta.5 — 2026-11-21

Pre-release that fixed updating a September install on a Mac and tested `install.sh` against four kinds of Mac. Its changes are under v1.3.0 above.

## v1.3.0-beta.4 — 2026-11-18

Pre-release with the first full set of 1.3 notes. Its changes are under v1.3.0 above.

## v1.3.0-beta.3 — 2026-11-18

Pre-release. Its install workflow passed on Ubuntu and Windows and failed on macOS (the `setsid` entry in the Full log on the wiki's Release 1.3 Details page). Its changes are under v1.3.0 above.

## v1.3.0-beta.2 — 2026-11-18

Pre-release. Its install workflow passed on Ubuntu and failed on Windows (the `UnicodeDecodeError` entry in the Full log on the wiki's Release 1.3 Details page), and macOS got no runner. Its changes are under v1.3.0 above.

## v1.3.0-beta.1 — 2026-11-18

Pre-release. Its install workflow failed on Ubuntu and Windows (the `UnicodeDecodeError` and `--check` entries in the Full log on the wiki's Release 1.3 Details page). Its changes are under v1.3.0 above.

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
