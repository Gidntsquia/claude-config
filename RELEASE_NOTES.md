Full release of all four agents, plus new skills and a leaner Claude Code setup. Everything since v1.0.0 (2026-10-09) is here, including the Windows fixes from @dotcomstar.

## Highlights ✨

- **Helper agent added.** `claude --agent helper` guides beginners through the planner, worker and evaluator workflow.
- **`/run-agent` added.** Swap your current tmux session for any agent without leaving the pane.
- **Overall improvements to Worker / Evaluator / Planner.** Workers finish the plan, evaluators show results faster, and the planner now suggests the exact `claude --agent <name> "."` command to start the next session.

## Helper 🧭

- New agent for people starting out. Asks where you are in the workflow, then helps one step at a time in plain English.
- Answers only from the agent files, the wiki and the Claude Code docs, which it reads through the new helper-wiki MCP server.
- Walks first-time users through the setup page one section at a time, with pictures, using `~/my-first-app` as the example folder.

## Worker 🔧

- Keeps building until everything in the plan that isn't blocked is done, including after you give feedback. Anything it's unsure about is left for the evaluator.
- Never ends on "not checked" or "did not view", re-checks earlier criteria, and no longer asks permission for plan work.

## Evaluator ⚡

- Opens every item before the first question and places it next to the terminal the moment you answer. It only moves windows it opened and puts your terminal back exactly as it was.
- Points the planner at `plans/EVAL.md` when a change is too big, and suggests `claude --agent <name> "."` so the next session starts immediately.

## Planner 📝

- Builds the plan from menu questions, where each option is a specific idea and one is the default.
- Suggests `claude --agent <name> "."` for the next step.

## Skills 🧰

- **run-agent:** `/run-agent <agent> ["prompt"]` swaps the tmux pane's session for the chosen agent. `in <dir>` starts it in another folder (created after you say Yes), force words (`force`, `-f`, `now`, `go`, `worker!`) skip the question, sessions are named `<agent>: <repo folder> (<model>)`, and the planner with no prompt starts with an empty input box.
- **restore-sessions:** reopens the Claude sessions a Windows Update restart or WSL stop killed, in a tmux layout you approve.
- **weekly-roundup:** usage-by-day chart, per-person color palettes, pooling usage across machines on one account, double-tap a pie slice to jump to its deep dive, Haiku 5.5 pricing, and Windows fixes by @dotcomstar (PR #2).

## Settings and context trimming ✂️

- Default model is Sonnet. The dangerous-mode permission prompt is skipped.
- Workflow tool denied, `skillOverrides` hide unused skills, and claude.ai MCP servers are off, to save context.
- The tag `pre-trim-2026-10-08` is the way back to the config before the trimming.

## Known issues

- None known: the weekly-roundup tests (18) and run-agent tests all pass at this tag. PR #2 reported `test_shared_project_keeps_other_machine` failing on its own; it passes after the merge.

## Agent versions 📄

- planner.md — 2edf13f (2026-10-08)
- worker.md — 618d56b (2026-10-10)
- evaluator.md — 4063712 (2026-10-11)
- helper.md — 1985699 (2026-10-11)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
