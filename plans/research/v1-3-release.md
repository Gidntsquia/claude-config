# Research for the v1.3.0-beta.1 release (researcher replies, 2026-11-18 11:40 AM ET)

## Tree state
- `agents/` holds: assistant.md (untracked), evaluator.md (modified), helper.md, planner.md, planner-fix10.md (modified), planner-fix32.md (modified), report-checker.md, report-writer.md, researcher.md, worker.md (modified), README.md, USAGE.txt, evals/, report-writer/. `~/.claude/agents` is a link to this folder.
- `install.sh` (line 150) links every `agents/*.md` with a `name:` line, so both planner variants are installed for every user today.
- planner.md: 89 lines, 16297 bytes, last commit 751a899 (2026-11-17). planner-fix10.md: 89 lines, 16309 bytes, last commit 2026-11-15, uncommitted edits. planner-fix32.md: 77 lines, 6509 bytes, last commit 2026-10-30, uncommitted edits. planner.md differs from both.
- Only `skills/run-agent-dev/apply_agents.py` (and its untracked `__pycache__`) names the variants. `agents/researcher.md`'s description says "Called by planner-fix10".
- Uncommitted diffs (6 files, +25 −18): evaluator.md, worker.md, planner-fix10.md, planner-fix32.md gain `mcp__run-agent__*` in `tools:` and hand off through `mcp__run-agent__next` (Bash form kept); worker.md self-relaunch uses `mcp__run-agent__schedule`; settings.json gains the allow rule `mcp__run-agent__*`, literal em dashes, and an `allow` block (`$defaults` plus a prose rule about run-agent); `agents/evals/report-writer/ledger.jsonl` gains two entries (11-09, 11-15).
- `skills/run-agent-dev/` is tracked (19 files incl. `promote.sh`, `apply_agents.py`, `mcp/server.py`); its `__pycache__` is untracked and not ignored. `bin/run-agent-dev` exists.
- Local main is 3 commits ahead of origin/main. 69 commits in `v1.2.1..HEAD`.

## Assistant
- `agents/assistant.md` is a symlink to `/home/jaxon/files/assistant-agent/.claude/agents/assistant.md` (161 lines).
- Frontmatter: `name: assistant`, model `claude-opus-5-5`, effort medium, tools Read/Glob/Grep/Bash/AskUserQuestion/Skill plus seven `mcp__assistant__assistant_*` tools, permissionMode acceptEdits, `mcpServers: assistant` run with `uv run` from `../../mcp/server.py`, PreToolUse hook `../../scripts/hooks/guard.py`. Both paths resolve inside `~/files/assistant-agent` (git branch master), not this repo.
- It also calls `~/.claude/local-tools/phone-shot.sh`.
- In its own words: "You are the operator of the user's Claude Code sessions in tmux. You carry out one order at a time with the assistant tools, as it was given, and report what the tool results showed."

## Update path 1.2.1 to 1.3
- install.sh already does: `~/.local/bin/run-agent` link; `run-agent-revive.service` (systemd user unit; shell rc on macOS); usage-guard (links `~/.claude/hooks/usage-guard` and `~/.local/bin/guard`; the repo settings.json carries 7 `usage_guard.py` hook entries and `--check` fails without them); the UserPromptExpansion and PermissionDenied hooks through the settings merge, with `--check` lines; `run-agent.sh --install-denied`; the six run-agent allow rules rewritten to the clone's path under merge and replace; `CLAUDE_CODE_PLUGIN_DIRS` for defer-artifact under merge and replace.
- install.sh does not do: the run-agent MCP registration. Today only `skills/run-agent-dev/promote.sh` runs `claude mcp add --transport stdio --scope user run-agent -- ~/.claude/skills/run-agent/mcp/server.py`. Without it the agents' handoff uses the Bash form.
- install.sh does not check the Claude Code version. usage-guard needs 2.1.296+, defer-artifact 2.1.293+. This machine has 2.1.327.
- With `--settings keep`, defer-artifact is manual: add `<clone>/mods/defer-artifact` to `env.CLAUDE_CODE_PLUGIN_DIRS`.
- helper and the run-agent MCP server run through `uv`.
- CHANGELOG's usage-guard round 2 entry ends "(install.sh users: add them from `hooks/usage-guard/README.md`)", which install.sh makes untrue.
- Not checked: whether `--settings merge` adds the repo's hook entries when the user's settings.json already has a `hooks` key.

## Releases, CI, wiki
- `gh release list`: v1.2.1 Latest (published 2026-10-28 6:55 PM ET); v1.2.0, v1.1.0, v1.0.0 normal; `v1.1.0-beta.1` is a Pre-release whose title equals its tag. No drafts.
- The v1.2.1 release body equals RELEASE_NOTES.md byte for byte (3673 chars). CHANGELOG's `## v1.2.1` section repeats it one heading level down, Known issues and Agent versions included.
- `.github/workflows/install.yml` (name `install`) triggers on `release: types: [published]` only; Ubuntu, macOS, Windows. Newest run 2026-11-08 11:40 AM ET, success.
- `wiki/` is its own clone of `https://github.com/Gidntsquia/claude-config.wiki.git`, gitignored by the parent (`.gitignore:12 /wiki/`), 2 commits ahead of its origin; published by `git -C wiki push`. `helper-mcp/stamp-wiki` writes the sync stamp.
- Part verdicts, `plans/EVAL.md` line 1 and `Verdict:`: worker-building 2026-11-18 ship; planner-building 2026-11-18 ship ("planner-fix10 is the base"); evaluator-building 2026-11-18 ship; report-writer-agent-improver 2026-11-06 ship.
- Agent last commits: planner 751a899 (11-17), worker 92a7ff5 (11-15), evaluator 9b63f64 (11-18), helper 723ebb1 (11-09), report-writer 8c5b81a (11-09), report-checker 81cd4b6 (11-06), researcher 1a9652d (11-15).

## Notes style
`skills/write-readme/SKILL.md` defers to `skills/write-readme/references/style.md`. Voice: plain and direct, first person where natural, contractions fine, one emoji per heading, bullets of one or two plain sentences about things a user notices, numbers only as results, at most one "IMPORTANT:" line, em dashes only in a Documentation link list. Banned: "not X, but Y" and "X, not Y" contrasts; "actually/really/exactly/at all/simply/just" for emphasis; three-part parallel bullets and "A → B → C" arrows; bold colon taglines opening a bullet; personality asides; closing reassurance clauses; filler ("spits out", "nitty gritty", "that's it").

## Workflow page gaps (wiki/Workflow.md, 166 lines)
- L1 sync stamp is 2026-10-29.
- L4, L14: say you run each agent yourself and type `/exit` before the next command.
- L38-42 (planner "How it ends"), L74-79 (worker), L128-131 (evaluator): quote endings with a plain `claude --agent …` command. All three agents now end with the three next-step lines: a sentence, a `/run-agent <agent> "<prompt>"` line, a labelled `claude --agent` line (planner.md:65, worker.md:119, evaluator.md:49-50).
- L6-12, L151-155: command block lacks `evaluator "phone"` and `/run-agent`.
- Planner section: nothing on research through `researcher` subagents (at most three side by side) or `plans/research/<slug>.md` (planner.md:47-56).
- Worker section: nothing on `## Waiting — <time> ET` self-scheduling ending in `scheduled #N` (worker.md:131-137), the usage-limit handoff `## Stopped at usage limit` (138-155), usage-guard (91-101), or "a blocker is a command plus its error".
- Evaluator section: nothing on opening every item hidden first, the question "Ready for me to move windows and start?", one item per question, or the `hidden:`/`elapsed`/`no-flash` lines in EVAL.md (evaluator.md:26-50).

## Cheat Sheet gaps (wiki/Cheat-Sheet.md, 19 lines, no headings)
- L4-8 run each agent by `claude --agent …` only; L6 has no `"phone"` form; L10 "`/exit` leaves an agent" implies a manual handoff.
- Missing: every `/run-agent` form, `confirm`, `+` groups, `window`/`split`, time phrases (`at 9pm`, `in 2h`, `after window`, `until 7am`), `run-agent jobs|cancel|clean`, `guard allow|status|revoke|log|usage|recount`, `claude --agent assistant`.

## Other stale lines
- README.md:7 "five agents, six skills". After the cleanup the tree has 8 agent files (planner, worker, evaluator, helper, report-writer, assistant; subagents researcher, report-checker) and 7 skills (restore-sessions, review-skill, run-agent, test-speedup, weekly-roundup, write-readme, write-report).
- README Features: planner bullet (L57) has no researcher; worker bullet (L58) has no self-scheduling, usage-limit handoff or never-blocks; `/run-agent` bullet (L61) lacks `clean`. No bullet for: assistant, usage-guard / `guard`, the three-line next step and run-agent MCP tools, the evaluator's hidden opens.
- wiki/Glossary-and-FAQ.md:52 says the worker "schedules its own relaunch via `/run-agent`"; worker.md uses the `mcp__run-agent__schedule` tool and `run-agent.sh --handoff`.
- agents/USAGE.txt:3 "Three main-session agents", L13 "Two side agents"; assistant and researcher unlisted; L6-11 have no `/run-agent` lines.
