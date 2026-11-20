# RELEASE_NOTES trace: v1.3.0-beta.4 (the install workflows of beta.1 to beta.3 failed; R18)

One row per change bullet in RELEASE_NOTES.md (Highlights, Agents, run-agent, Install, Settings). CHANGELOG entry = the first words of the `### Full log` entry under `## v1.3.0-beta.4`. Every sha is in `v1.2.1..v1.3.0-beta.4`; all but a030e88, 2ce6341 and b616b19 are also in `v1.2.1..v1.3.0-beta.1`.

| Notes bullet (first words) | CHANGELOG entry | sha |
|---|---|---|
| Highlights: The worker can build while you're away | worker: denial routing, no prose questions, wait-only self-scheduling; The planner, worker and evaluator end with their next step | c64e605, b61d8f5 |
| Highlights: `/run-agent worker` swaps the Claude session | run-agent (v1.5.0, built and proven in the dev copy; run-agent: scheduled runs survive a reboot | 53a457e, 0ec389a |
| Highlights: usage-guard stops a worker | usage-guard (`hooks/usage-guard/`, needs Claude Code 2.1.296+); usage-guard round 2 | ff8b14d, 92a7ff5 |
| Highlights: The report-writer writes an outline | report-writer: the middle stays on the ask; report-writer: denser middle sections; report loop closed | 81cd4b6, 97eacf7, 8c5b81a |
| Highlights: The defer-artifact mod keeps the Artifact tool's | defer-artifact mod (`mods/defer-artifact/` | b452ae4 |
| Highlights: The new assistant agent runs your tmux sessions | assistant agent (`agents/assistant.md` | 238bb09 |
| Agents: When a requirement depends on a fact | planner: research runs through the `researcher` subagent | 1a9652d |
| Agents: There is one planner again | v1.3 release tree: one planner and one run-agent | 880d276, 238bb09 |
| Agents: When a command is denied | worker: denial routing, no prose questions | c64e605 |
| Agents: The worker gets reports from the report-writer | report loop closed (v1.3 R12–R15) | 8c5b81a |
| Agents: On the desktop the evaluator opens every item hidden | evaluator: hidden opens | 2c265b1, 2c7974a |
| Agents: The evaluator opens files as pages in Firefox | evaluator: hidden opens (its last sentence: Files open as pages in Firefox) | 9b63f64 |
| Agents: A worker's subagents run as `helper` on Sonnet | usage-guard (`hooks/usage-guard/` (helper on Sonnet, report-writer stays report-writer) | 723ebb1, 49c58af |
| run-agent: The run-agent MCP server has five tools | run-agent (v1.5.0, built and proven in the dev copy | 53a457e |
| run-agent: A typed `/run-agent` costs no tokens | run-agent: `/run-agent` costs no tokens | 499dabc |
| run-agent: A `/run-agent` line runs without a confirm question | run-agent (v1.4.0): runs without asking by default | 90b9cbb |
| run-agent: Time phrases like `tomorrow at 1am` | run-agent: time phrases resolve in `parse.py` without a model | 499dabc |
| run-agent: `+` joins runs into one new tmux window | run-agent: several runs joined by `+` start together | e961c5a |
| run-agent: Scheduled runs survive a reboot | run-agent: scheduled runs survive a reboot or WSL restart | 0ec389a, f14a2c7 |
| run-agent: Scheduling works on macOS | run-agent: scheduling works on macOS | b616b19 |
| run-agent: `run-agent jobs` shows each runner's state | run-agent (v1.3.1): failed and skipped runs are not silent | 0c73b72 |
| run-agent: `test.sh` can no longer touch a live tmux pane | run-agent test.sh can no longer touch a live pane | b09d5b5 |
| Install: `install.sh` registers the run-agent MCP server | v1.3 release tree: one planner and one run-agent | 238bb09 |
| Install: `install.sh` links `run-agent` and `guard` | `bin/run-agent` is the same thing as a shell command; usage-guard (`hooks/usage-guard/` | b61d8f5, 723ebb1, 3dd7538 |
| Install: A settings merge into a `settings.json` that already has | v1.3 release tree: one planner and one run-agent (test/install-scenarios.sh scenario b) | 238bb09 |
| Install: The install workflow on Ubuntu, macOS and Windows | CI: the `install` workflow runs on published releases only | 702a78c |
| Install: On Windows, a second `./install.sh` no longer stops | install: on Windows a rerun of `./install.sh`; install: `--check` finds the defer-artifact mod on Windows | 2ce6341, a030e88 |
| Settings: `settings.json` allows six narrow run-agent Bash rules | run-agent (v1.3.1): run-agent calls are never classifier-blocked; v1.3 release tree (`mcp__run-agent__*`) | 0c73b72, a839db2 |
| Settings: `autoMode.allow` keeps Claude Code's defaults | v1.3 release tree: one planner and one run-agent (`autoMode.allow` is `"$defaults"` plus one sentence) | a839db2 |

Known issues and Agent versions are not change bullets; the Agent versions shas (751a899, a839db2, 723ebb1, 8c5b81a, 81cd4b6, 238bb09) are each the last commit touching that agent file.
