# claude-config ⚙️

<p align="center">
  <img alt="The status line showing the project name, git branch, model, and 5-hour usage" src="https://raw.githubusercontent.com/wiki/Gidntsquia/claude-config/statusline.png">
</p>

My [Claude Code](https://claude.com/claude-code) setup: eight agents, seven skills, a custom status line, and my global `CLAUDE.md` and `settings.json`. The files live in this repo and `~/.claude` holds symlinks to them, so edits made from either place end up here.

The agents split a project into planning, building and checking. The [wiki](https://github.com/Gidntsquia/claude-config/wiki) is a beginner's guide to that workflow, starting from a fresh Windows or Mac install.

## Quickstart 🚀

Requires Claude Code. Paste this sentence into it:

```
Install https://github.com/Gidntsquia/claude-config following its INSTALL.md
```

Claude asks four questions (projects folder, terminal setup, status line, settings) and keeps your existing settings, agents and CLAUDE.md unless you say otherwise. When it's done it gives a short tour.

To install without Claude, you need git, bash and python3:

```
git clone https://github.com/Gidntsquia/claude-config ~/.claude-config
cd ~/.claude-config
./install.sh --projects ~/files --terminal --statusline squid --settings merge   # Installs the choices you pass
./install.sh --check   # Prints one PASS/FAIL line per item
```

`./install.sh --help` lists every flag. Your choices are saved in `~/.claude/claude-config.json`, so a later `./install.sh` with no flags applies them again. It makes no backup copies. If you already have an agent or skill with one of this repo's names, yours stays and the repo's is not installed; `--agent-clash keep|replace|skip` changes that.

IMPORTANT: never add `.credentials.json`, `history.jsonl`, `projects/`, or any other session data. `~/.claude/skills/synced` is managed by Claude and stays out of the repo.

Run the agents from a project root:

```
claude --agent planner     # Turns what you ask for into plans/PLAN.md
claude --agent worker      # Builds what PLAN.md specifies
claude --agent evaluator "."      # Launches the result, asks you if it works, writes plans/EVAL.md
claude --agent evaluator "phone"  # Same when you follow on your phone: pictures in the chat, no windows
claude --agent helper      # Guides a beginner through the planner, worker and evaluator
claude --agent assistant   # Runs your tmux sessions from one chat: status, launch, send, close, retile, schedule. Starts only in a project that links it (see assistant/ below)
claude --agent report-writer   # The essay a study's data supports, in a storyteller's voice: your ask quoted first, one moment of the study as a scene, the "But", then the answer, every figure a sourced {key}; a report-checker subagent reads it once in the background. Opus medium. When and how to call it: skills/write-report/SKILL.md
claude --agent report-checker  # Second set of eyes on a report (the writer runs it itself); Opus medium
```

To update, tell Claude: "update my claude-config to the latest release, following https://github.com/Gidntsquia/claude-config/blob/main/UPDATING.md". The steps keep your own edits and relink everything.

## Features 🔬

- The planner asks a few questions and writes a spec with the requirements and acceptance criteria. It doesn't decide how to build anything. When a requirement rests on a fact it can't know, up to three `researcher` subagents look it up and their findings go in `plans/research/`.
- The worker builds the spec and follows what you tell it over what the plan says. It never ends a session on a question. When only time is left (a long run, a scrape) it schedules its own relaunch, and at the usage limit it writes what's done and what's next and hands off to a fresh worker.
- The evaluator runs the app and asks you whether it works. Small changes you ask for are added to the spec, and big ones are sent back to the planner. It never edits code. On the desktop it opens every item hidden first and shows each one only when it asks about it, so no window flashes up while you work.
- Every agent ends with its next step in three lines: when to run it, the `/run-agent` line, and the plain `claude --agent` line for a terminal without run-agent.
- The helper asks where you are in the workflow, then helps one step at a time. It answers only from the agent files, the wiki and the Claude Code docs, through a small MCP server in `helper-mcp/`.
- `/run-agent <agent>` swaps a tmux pane's Claude session for the chosen agent, e.g. `/run-agent worker` after the planner finishes. It replaces the pane (or schedules, or opens the window) at once; add `confirm` to be asked first. Loose phone typing works (`worker fable low effort`, `model=opus`, typos get corrected), and a time schedules the run instead: `at 9pm`, `in 2h`, or `after window` to start when the 5-hour usage window resets (`until 7am` caps the wait). Add `window` (or `split`) to open the agent in a new tmux window instead, or join runs with `+` to start several side by side in one new window (four planners = a 2x2 grid). `/run-agent jobs` lists what is scheduled, `/run-agent cancel` drops it, and `run-agent clean` deletes old job files. If a reboot or WSL restart stops a scheduled run, it is picked up again when WSL starts; a run that came due while it was down is skipped.
- The assistant runs your tmux sessions from one chat: it reports where each project is, starts an agent in a free pane, answers a waiting session, closes or retiles panes, and schedules runs. Its agent file, MCP server (seven tools) and guard hook all live in `assistant/` (`assistant.md`, `mcp/server.py`, `hooks/guard.py`), not in `agents/`, so it is not installed for every folder. It starts only in a project whose `.claude/agents/assistant.md` is a link to `assistant/assistant.md`: `ln -s <clone>/assistant/assistant.md <project>/.claude/agents/assistant.md`. The guard hook stops it from closing your own panes or answering an evaluator's questions for you.
- usage-guard (`hooks/usage-guard/`, Claude Code 2.1.296+) stops a worker's expensive launches before they run: at most 2 headless `claude` runs at once, 3 subagents at once and 30 launches a day per project. The worker sees its count, and `guard status`, `guard allow 2h` and `guard usage` let you check or lift it.
- `/restore-sessions` reopens the Claude Code sessions a Windows Update restart or WSL stop killed, each in its own tmux pane.
- `review-skill` audits a SKILL.md for correctness, edge cases, and token use. `test-speedup` sets up parallel runs and fast/slow tiers for a slow test suite.
- `weekly-roundup` builds an artifact of what I worked on in the past week from git activity. `write-readme` writes a README like this one and moves the detail into the wiki.
- The `defer-artifact` mod (`mods/defer-artifact/`, Claude Code 2.1.293+) keeps the Artifact tool's schema out of every session (about 9.6k tokens per request); Claude loads it through ToolSearch when you ask for an artifact. install.sh turns it on through `CLAUDE_CODE_PLUGIN_DIRS`; disable it in `/plugin` or remove that entry to turn it off.
- `statusline.sh` draws the status line in the gruvbox colors from my starship prompt, with a different color for each model. `./install.sh --statusline plane` swaps in a plane mascot with easter eggs, and `bash ~/.claude/statusline.sh --preview plane` shows every one.
- With `--terminal`, new terminal tabs open tmux with 4 panes in your projects folder and the starship prompt. On WSL that is the Windows Terminal profile for your distro (in JetBrainsMono Nerd Font, with Windows Terminal kept at 18% volume after reboots); on macOS it is an iTerm2 "Claude tmux" profile. `--default-profile` also makes it the profile new windows open with.
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
- [AI Tells](docs/ai-tells.md) — writing habits that read as AI, with fixes
- [Agent style](docs/agent-style.md) — how the agent files are written, traced to Anthropic's guidance

`examples/first-project/` is the finished app from Getting Started, and `agents/USAGE.txt` has the hand-off rules between agents.

## License 📄

[MIT](LICENSE).
