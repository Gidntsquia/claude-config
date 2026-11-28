# claude-config ⚙️

<p align="center">
  <img alt="The status line showing the project name, git branch, model, and 5-hour usage" src="https://raw.githubusercontent.com/wiki/Gidntsquia/claude-config/statusline.png">
</p>

[Last full run: 2026-11-27, macOS 27.0.1: all 796 tests passed (35 skipped); Ubuntu 24.04: all 796 tests passed (60 skipped); Windows: not run](TESTING.md)

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

`./install.sh --help` lists every flag. Your choices are saved in `~/.claude/claude-config.json`, so a later `./install.sh` with no flags applies them again.

IMPORTANT: never add `.credentials.json`, `history.jsonl`, `projects/`, or any other session data to the repo.

Other commands, run from a project root:

```
claude --agent planner            # Turns what you ask for into plans/PLAN.md
claude --agent worker             # Builds what PLAN.md specifies
claude --agent evaluator "."      # Launches the result, asks you if it works, writes plans/EVAL.md
claude --agent evaluator "phone"  # The same check from your phone, as pictures in the chat
claude --agent helper             # Guides a beginner through the planner, worker and evaluator
```

To update, tell Claude: "update my claude-config to the latest release, following https://github.com/Gidntsquia/claude-config/blob/main/UPDATING.md". The steps keep your own edits and relink everything.

## Features 🔬

- The planner asks a few questions and writes a spec with the requirements and acceptance criteria. When a requirement rests on a fact it can't know, researcher subagents look it up.
- The worker builds the spec and follows what you tell it over what the plan says. At the usage limit it writes down what's done and hands off to a fresh worker.
- The evaluator runs the app and asks you whether it works. Small changes you ask for are added to the spec, and big ones are sent back to the planner.
- Every agent ends with the `/run-agent` line that starts the next one in the same tmux pane. Add a time like `in 2h` or `after window` to schedule the run.
- With `evaluator "phone"` each item arrives as a picture in the chat, so you can check the work away from the desktop.
- usage-guard stops a worker before it starts more than 2 headless `claude` runs at once, 3 subagents at once or 30 launches a day in a project.
- The helper asks where you are in the workflow, then helps one step at a time. It answers only from the agent files, the wiki and the Claude Code docs.
- The assistant runs your tmux sessions from one chat. It reports where each project is, starts agents in free panes and schedules runs.
- `/restore-sessions` reopens the Claude Code sessions a restart killed, and `write-readme` writes a README like this one.
- With `--terminal`, new terminal tabs open tmux with 4 panes in your projects folder. `statusline.sh` draws the status line with a different color for each model.

## Documentation 📚

More details in the
[wiki](https://github.com/Gidntsquia/claude-config/wiki):

- [Wiki home](https://github.com/Gidntsquia/claude-config/wiki) — where to start
- [Setting Up WSL](https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-WSL) — Windows first-time setup
- [Setting Up Claude Code](https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-Claude-Code) — install, sign in, first run
- [Install This Config Repo](https://github.com/Gidntsquia/claude-config/wiki/Install-This-Config-Repo) — the install, step by step
- [Getting Started](https://github.com/Gidntsquia/claude-config/wiki/Getting-Started) — a first project step by step
- [Workflow](https://github.com/Gidntsquia/claude-config/wiki/Workflow) — what each agent does
- [When the Worker Is Blocked or Waiting](https://github.com/Gidntsquia/claude-config/wiki/When-The-Worker-Is-Blocked-Or-Waiting) — refused commands, long waits, the usage limit
- [How the Evaluator Opens Items](https://github.com/Gidntsquia/claude-config/wiki/How-The-Evaluator-Opens-Items) — hidden windows and file pages
- [Cheat Sheet](https://github.com/Gidntsquia/claude-config/wiki/Cheat-Sheet) — commands and common pitfalls
- [Glossary and FAQ](https://github.com/Gidntsquia/claude-config/wiki/Glossary-and-FAQ) — terms and beginner questions
- [The Golden Context Window](https://github.com/Gidntsquia/claude-config/wiki/The-Golden-Context-Window) — `/compact`, `/clear` and the cache
- [Features](https://github.com/Gidntsquia/claude-config/wiki/Features) — every agent, skill and option
- [Updating](https://github.com/Gidntsquia/claude-config/wiki/Updating) — what an update does with your edits
- [Context Trimming](https://github.com/Gidntsquia/claude-config/wiki/Context-Trimming) — settings that shrink every session's context
- [Release 1.3 Details](https://github.com/Gidntsquia/claude-config/wiki/Release-1.3-Details) — the full 1.3 change list
- [AI Tells](docs/ai-tells.md) — writing habits that read as AI
- [Agent style](docs/agent-style.md) — how the agent files are written

`examples/first-project/` is the finished app from Getting Started, and `agents/USAGE.txt` has the hand-off rules between agents.

## License 📄

[MIT](LICENSE).
