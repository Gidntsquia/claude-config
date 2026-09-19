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

## Documentation 📚

How the three agents hand work to each other is in `agents/USAGE.txt`.

## License 📄

[MIT](LICENSE).
