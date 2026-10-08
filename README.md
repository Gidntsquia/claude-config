# claude-config ⚙️

<p align="center">
  <img alt="The status line showing the project name, git branch, model, and 5-hour usage" src="docs/statusline.png">
</p>

My [Claude Code](https://claude.com/claude-code) setup: three agents, a few skills, a hook, a custom statusline, and my global `CLAUDE.md` and `settings.json`. The files live in this repo and `~/.claude` holds symlinks to them, so edits made from either place end up here.

## Quickstart 🚀

Requires Claude Code and bash.

```
git clone https://github.com/Gidntsquia/claude-config
cd claude-config
./install.sh   # Symlinks everything into ~/.claude (existing files are moved to <name>.pre-link)
```

IMPORTANT: never add `.credentials.json`, `history.jsonl`, `projects/`, or any other session data. `~/.claude/skills/synced` is managed by Claude and stays out of the repo.

Running the three agents, from a project root:

```
claude --agent planner     # Turns what you ask for into plans/PLAN.md
claude --agent worker      # Builds what PLAN.md specifies
claude --agent evaluator   # Launches the result, asks you if it works, writes plans/EVAL.md
```

## Features 🔬

- The planner asks a few questions and writes a spec with the requirements and acceptance criteria. It doesn't decide how to build anything.
- The worker builds the spec and follows what you tell it over what the plan says.
- The evaluator runs the app and asks you whether it works. Small changes you ask for are added to the spec, and big ones are sent back to the planner. It never edits code.
- `review-skill` audits a SKILL.md for correctness, edge cases, and token use.
- `test-speedup` measures a slow test suite and sets up parallel runs, fast and slow tiers, and a guard against whole-suite runs.
- `weekly-roundup` builds an artifact of what I worked on in the past week from git activity.
- `write-readme` writes a README like this one and moves the detail into the wiki.
- `hooks/full-suite-guard.sh` blocks Bash calls that run a project's whole test suite.
- `statusline.sh` draws the status line in the gruvbox colors from my starship prompt, with a different color for each model.
- `commands/summarize_commits.md` writes a short summary for each commit on a branch.
- On WSL, `install.sh` makes new Windows Terminal tabs open tmux with 4 equal panes in `~/files` (`wsl/tmux-quad`). On macOS it points iTerm2 at `iterm2/` instead.
- On WSL, `install.sh` also sets Windows Terminal to 18% in the Windows volume mixer each time WSL boots, since Windows resets it to 100% after a reboot (`wsl/terminal-volume.ps1`, run by `wsl/terminal-volume.service`).

## Context trimming ✂️

On 2026-10-08 I turned off the Workflow tool to save context. `settings.json` has `"permissions": {"deny": ["Workflow"]}` and `"enableWorkflows": false`, so the tool's definition never loads. To bring it back, remove both.

The same night I also:

- Set `"env": {"ENABLE_CLAUDEAI_MCP_SERVERS": "false"}` so claude.ai connectors (Claude Docs) don't load into Claude Code. Remove it to get them back.
- Added `SendFeedback`, `ScheduleWakeup`, and `ReportFindings` to `permissions.deny` (about 2k tokens). ScheduleWakeup only works with `/loop` and ReportFindings only with `code-review`, both of which are off. Remove them from the list to get them back.
- Set `"workflowKeywordTriggerEnabled": false`.
- Added `skillOverrides`, which also works on built-in skills. Each skill takes one of four values:
  - `"on"` (the default): listed with its description.
  - `"name-only"`: listed by name only, a few tokens each. Claude or I (`/name`) can still invoke it. I use this for `pdf`, `pptx`, `xlsx`, and `docx`: I rarely need them, and their names say what they do.
  - `"user-invocable-only"`: hidden from Claude, but `/name` still works. I use this for my own skills and for `schedule`, `init`, `simplify`, and `security-review`.
  - `"off"`: hidden from both. I use this for everything else I don't use, such as `loop`, `code-review`, the browser and computer-use skills, and `deep-research`.

  This cut the skill listing from 17 full entries to 6 (about 2.6k tokens down to 1.2k). Change a skill in `/skills` or in `settings.json`. The overrides used to live in ai-sandbox's `.claude/settings.local.json`. I moved them here so they apply everywhere.
- Removed the `CLAUDE.md` rule "Re-read a file immediately before Edit if a previous Edit failed on string match." The Edit tool already reports a mismatch, so the rule cost tokens without changing behavior.
- Shortened the descriptions in my auto-memory index (`~/.claude/projects/*/memory/MEMORY.md`, not in this repo) to about 8 words each, since the full detail is in each memory file. `CLAUDE.local.md` stays a separate file because it holds per-machine notes and is gitignored.
- Emptied the ai-sandbox auto-memory, which loaded in every session there. I deleted two stale memories (orchestration reports, the second-device week). I moved the agent memories into agent-eval-experiment's project memory and the config memories into this repo's project memory. `CLAUDE.md` now has a one-line pointer to this repo instead.

**Restore point:** the git tag `pre-trim-2026-10-08` marks the config before any of this trimming. If something breaks, run `git checkout pre-trim-2026-10-08 -- settings.json` (or the whole tree) and restart Claude Code.

I also wanted Agent and Artifact to load only when needed, but Claude Code has no setting for that. On-demand loading (ToolSearch) only covers MCP tools and the built-ins Claude Code picks itself, so both still load in every session. Revisit if a setting appears.

## Documentation 📚

How the three agents hand work to each other is in `agents/USAGE.txt`.

## License 📄

[MIT](LICENSE).
