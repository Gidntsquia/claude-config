
A week of new skills and two new agents for writing reports, and every session now uses the one-hour prompt cache. Everything since v1.1.0 (2026-10-15) is here.

## Highlights ✨

- `/write-report` is a new skill for anything that compares or measures two options. It offers the report-writer agent, which turns a folder of study data into a short report that leads with the verdict and traces every figure back to a file, and has the report-checker agent read it a second time.
- `/run-agent` can schedule a run with `at 9pm`, `in 2h` or `after window`, and it understands loose phone typing such as `model=fable` or `fabel`. When the worker hits the usage limit it saves its work with a short note and schedules its own relaunch for when the window resets.
- `/restore-sessions` was rebuilt. It reopens one session per project with the model each one had, shows every tmux window in its own terminal, looks back 60 minutes from the stop and skips sessions you closed with `/exit`.

## Skills 🧰

- write-report is loaded by the planner when a plan compares or benchmarks something.
- run-agent: `until 7am` caps how long a scheduled run waits. If the pane is gone by then, the run starts in a new tmux window. `/run-agent jobs` lists the waiting runs and `cancel` drops one. `dry` shows the command and the start time without running anything. The script reads the arguments itself (`--parse`), fixes near-miss typos and shows the fix, and asks only about words it can't place. `--need-tmux` stops early outside tmux, and `--handoff` does the worker's usage-limit steps in one call.
- restore-sessions opens restored windows with the Ubuntu Windows Terminal profile, and they no longer stay always on top. It leaves out empty sessions, and `keep <id>` brings one back.
- weekly-roundup prices Sonnet 5.5 cache reads at 0.05x input and adds the Oct 11-18 week to the archive with its own project colors.

## Agents 🤖

- report-writer (model Fable) writes the report page and phone cards with the verdict, the deciding number, one chart and a list of what could be wrong. When the data can't decide, it writes `plans/DATA_REQUEST.md` with what to measure, and the worker collects it and reruns.
- report-checker (model Opus) answers the question cold from the data, then checks every claim and figure in the report and writes findings. The writer fixes what was flagged over up to two loops, and anything still open is listed in the report..
- worker writes a three-line note and a WIP commit at the usage limit. `docs/agent-style.md` lists the house rules for agent files, each with the Anthropic guidance it comes from.
- evaluator has a phone path. `claude --agent evaluator "phone"` shows each item as a phone-sized picture and opens no windows. The window-control rules moved into the agent file, and the file is shorter with every rule kept.
- helper knows the git-init fix for the MCP approval dialog that keeps coming back, and says the cache stays warm for about an hour.
- planner has the Skill tool and calls for a report-writer report when a plan compares or measures something.

## Settings ⚙️

- Default model is Opus.
- Main sessions and subagents use the one-hour prompt cache, including report-writer and report-checker. `promptCacheTtl` and `subagentPromptCacheTtl` are both `1h`, and `ENABLE_PROMPT_CACHING_1H` is set as a backup.
- `autoContinueAtUsageLimit` is off, so the worker's scheduled relaunch is the only thing that restarts work when the usage window resets.
- Deny rules hide the planner, worker, evaluator and helper from the Agent tool, since they run as main sessions.
- The `run-agent.sh` Bash call is allowed, so auto mode doesn't block the worker's handoff.
- The status line has a plane theme. Set `CLAUDE_STATUSLINE_THEME=plane` or run `./install.sh --theme plane`, and `bash statusline.sh --preview plane` lists every easter egg.
- `UPDATING.md` has the steps for an AI to update your clone to the latest release.

## Known issues

- None known.

## Agent versions 📄

- planner.md at 19ecb18 (2026-10-23)
- worker.md at 8206204 (2026-10-24)
- evaluator.md at 7a8394b (2026-10-23)
- helper.md at 06a0875 (2026-10-25)
- report-writer.md at 06a0875 (2026-10-25)
- report-checker.md at 06a0875 (2026-10-25)

