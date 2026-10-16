# claude-config ⚙️

<p align="center">
  <img alt="The status line showing the project name, git branch, model, and 5-hour usage" src="https://raw.githubusercontent.com/wiki/Gidntsquia/claude-config/statusline.png">
</p>

My [Claude Code](https://claude.com/claude-code) setup: four agents, six skills, a custom status line, and my global `CLAUDE.md` and `settings.json`. The files live in this repo and `~/.claude` holds symlinks to them, so edits made from either place end up here.

The agents split a project into planning, building and checking. The [wiki](https://github.com/Gidntsquia/claude-config/wiki) is a beginner's guide to that workflow, starting from a fresh Windows or Mac install.

## Quickstart 🚀

Requires Claude Code and bash.

```
git clone https://github.com/Gidntsquia/claude-config
cd claude-config
./install.sh   # Symlinks everything into ~/.claude (existing files are moved to <name>.pre-link)
```

IMPORTANT: never add `.credentials.json`, `history.jsonl`, `projects/`, or any other session data. `~/.claude/skills/synced` is managed by Claude and stays out of the repo.

Run the agents from a project root:

```
claude --agent planner     # Turns what you ask for into plans/PLAN.md
claude --agent worker      # Builds what PLAN.md specifies
claude --agent evaluator   # Launches the result, asks you if it works, writes plans/EVAL.md
claude --agent helper      # Guides a beginner through the planner, worker and evaluator
```

Other commands:

```
./install.sh --theme plane                   # Plane mascot and easter eggs in the status line
bash ~/.claude/statusline.sh --preview plane # Shows every plane easter egg
```

To update, tell Claude: "update my claude-config to the latest release, following https://github.com/Gidntsquia/claude-config/blob/main/UPDATING.md". The steps keep your own edits and relink everything.

## Features 🔬

- The planner asks a few questions and writes a spec with the requirements and acceptance criteria. It doesn't decide how to build anything.
- The worker builds the spec and follows what you tell it over what the plan says.
- The evaluator runs the app and asks you whether it works. Small changes you ask for are added to the spec, and big ones are sent back to the planner. It never edits code.
- The helper asks where you are in the workflow, then helps one step at a time. It answers only from the agent files, the wiki and the Claude Code docs, through a small MCP server in `helper-mcp/`.
- `/run-agent <agent>` swaps a tmux pane's Claude session for the chosen agent, e.g. `/run-agent worker` after the planner finishes. It asks before replacing anything unless you add `force`.
- `/restore-sessions` reopens the Claude Code sessions a Windows Update restart or WSL stop killed, each in its own tmux pane.
- `review-skill` audits a SKILL.md for correctness, edge cases, and token use. `test-speedup` sets up parallel runs and fast/slow tiers for a slow test suite.
- `weekly-roundup` builds an artifact of what I worked on in the past week from git activity. `write-readme` writes a README like this one and moves the detail into the wiki.
- `statusline.sh` draws the status line in the gruvbox colors from my starship prompt, with a different color for each model.
- On WSL, `install.sh` makes new Windows Terminal tabs open tmux with 4 panes in `~/files`, sets up the starship prompt with JetBrainsMono Nerd Font, and keeps Windows Terminal at 18% volume after reboots. On macOS it points iTerm2 at `iterm2/` instead.
- On WSL it also links `wsl/local-tools/`, scripts Claude uses to open, place, screenshot and close Windows windows.

## Documentation 📚

More details in the
[wiki](https://github.com/Gidntsquia/claude-config/wiki):

- [Setting Up WSL](https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-WSL) — Windows first-time setup
- [Setting Up Claude Code](https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-Claude-Code) — install, sign in, this repo
- [Getting Started](https://github.com/Gidntsquia/claude-config/wiki/Getting-Started) — a first project step by step
- [Workflow](https://github.com/Gidntsquia/claude-config/wiki/Workflow) — what each agent does
- [Cheat Sheet](https://github.com/Gidntsquia/claude-config/wiki/Cheat-Sheet) — commands and common pitfalls
- [Glossary and FAQ](https://github.com/Gidntsquia/claude-config/wiki/Glossary-and-FAQ) — terms and beginner questions
- [Context Trimming](https://github.com/Gidntsquia/claude-config/wiki/Context-Trimming) — settings that shrink every session's context

`examples/first-project/` is the finished app from Getting Started, and `agents/USAGE.txt` has the hand-off rules between agents.

## License 📄

[MIT](LICENSE).
