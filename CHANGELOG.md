# Changelog

## v1.3.0 — unreleased

1.3 improves the planner, worker and evaluator loop by adding three core features to it: run-agent, phone modes and the usage guard. Everything since v1.2.1 (2026-10-26) is here.

### Highlights ✨

- run-agent is a main part of the workflow. The planner, worker and evaluator each end with the `/run-agent` line that starts the next agent in the same tmux pane, at once or at a time like `in 2h` or `after window`. Before, an agent stopped and the next command was yours to work out and type. An early form shipped in 1.2 (scheduling with `after window` and `until`, and the worker's handoff at the usage limit) and matured in 1.3. New since v1.2.1: the closing next-step lines, an MCP server with five tools so auto mode never blocks a handoff, a worker that schedules its own relaunch when only waiting is left, a typed `/run-agent` that costs no tokens, scheduled runs that survive a reboot, and `after window` runs that fire at the time fixed when they were scheduled.
- Phone modes let you run the loop from your phone. `claude --agent evaluator "phone"` sends each item as a picture in the chat and opens no windows. The assistant's phone mode sends a picture of the tmux pane after each action. The report-writer builds every report as 390 px cards, and `/run-agent` reads loose phone typing. Without them a check needed you at the desktop, where the evaluator opens its windows. An early form shipped in 1.2 (the evaluator's phone path, the report cards and run-agent's phone typing) and matured in 1.3. New since v1.2.1: the assistant's phone mode, and an evaluator phone path that skips the desktop's readiness question.
- The usage guard reduces token waste. It is a hook that stops a worker before it starts more than 2 headless `claude` runs at once, a headless run without `--max-budget-usd` and `--max-turns`, more than 30 launches a day in a project, a 4th subagent at once, or a subagent task it already sent today. The worker sees its count after every launch, and `guard status`, `guard usage` and `guard allow 2h` are your commands. Before, only the worker's prompt asked it to hold back, and one worker spent most of a weekly allowance in two weeks. All of it is new in 1.3, and it is the first of the guardrails to come.
- Planner, worker and evaluator fixes. The planner sends facts it can't know to up to three researcher subagents. The worker writes a denied command under `## Denied`, tries two other routes and never ends on a question. The evaluator opens every item hidden, asks once before it moves windows, and shows files as pages in Firefox.
- Stability. Updating an install that has your own edits is tested: the kept-edits update tests (the `dirty` scenario and `bin/resolve-kept-edits.py`) and a Docker rehearsal that types README's update sentence into Claude on an install of v1.2.1 and of v1.3.0-beta.5. The install workflow runs on every push, on Ubuntu, macOS, Windows and in Docker. It still needs work, and Known issues says where.

### Agents 🤖

- The planner, worker and evaluator end with their next step in three lines: when to run it, the `/run-agent` line, and the plain `claude --agent` line. The line never carries the calling session's model or effort.
- When a requirement depends on a fact the planner can't know, it sends the question to up to three `researcher` subagents at once and saves their findings in `plans/research/`.
- There is one planner again. planner-fix10's prompt is now `planner.md`, and the planner-fix10 and planner-fix32 variants are deleted.
- When a command is denied, the worker writes it under `## Denied` in `plans/WORKER_NOTES.md` and tries two other routes before it calls the step blocked. Its last message never ends on a question.
- When only waiting is left, the worker schedules its own relaunch, appends `## Waiting — <time> ET` to its notes and ends with the `scheduled #N` line.
- The worker gets reports from the report-writer through `skills/write-report/SKILL.md` and reruns the writer on what its last line names.
- A worker's subagents run as `helper` on Sonnet, except the report-writer, which stays on Opus.
- On the desktop the evaluator opens every item hidden first, asks "Ready for me to move windows and start?", and shows each item when its question comes up. `plans/EVAL.md` quotes a `no-flash:` line saying whether any window showed early. The phone path skips the question.
- The evaluator opens files as pages in Firefox, a `.md` rendered and anything else as numbered text, and no longer opens VS Code. A failed open is retried twice, then reported with the item's path.
- The report-writer writes an outline before any prose, keeps each middle section on what you asked, and draws a table, split bar or pair where numbers compare. A run that can't build a report ends with one line saying what to run.
- The new assistant agent runs your tmux sessions from one chat. It reports where each project is, starts an agent in a free pane, answers a waiting session and schedules runs, and a guard hook keeps it away from your own panes. Say "phone mode" and it sends a picture of the pane after each action.
- The assistant's files are in `assistant/` (agent file, server and hook), so it is not installed for every folder. It starts only in a project whose `.claude/agents/assistant.md` is a link to `assistant/assistant.md`, and `install.sh --check` tests that.
- The assistant's guard hook no longer denies Bash commands that name `mcp/`, `scripts/hooks/` or `.claude/agents/`. The tmux, background, pet-pane, own-pane, judgement-menu and force rules stay.

### run-agent 🔁

- The run-agent MCP server has five tools (`next`, `schedule`, `handoff`, `jobs`, `cancel`) that auto mode allows by rule. The agents use them and keep the Bash form as the fallback.
- A typed `/run-agent` costs no tokens: a hook runs it in place of a model turn.
- A `/run-agent` line runs without a confirm question. Add `confirm` to be asked first.
- Time phrases like `tomorrow at 1am`, `in 2 hours 10 min` and `two hours before the window` are read without a model, and the scheduled line says how the time was worked out.
- `+` joins runs into one new tmux window, tiled side by side, and `window` or `split` opens one agent in a new window.
- Scheduled runs survive a reboot or WSL restart. A run that came due while the machine was off is skipped and logged.
- An `after window` run fires at the time fixed when it was scheduled, which is the usage API's reset or, with no answer from the API, five hours after scheduling. `jobs` shows `live` or `assumed (now + 5 h)` beside it. Before, a run could sleep up to an hour past the reset or be skipped.
- Runs scheduled in the same instant each get their own job id. Before, one job could replace the other.
- Scheduling works on macOS, which has no `setsid` command. The runner gets its own session through Python there.
- On macOS the usage API call verifies TLS with `/etc/ssl/cert.pem` and reads the token from the Keychain when the one in `~/.claude/.credentials.json` has expired. Before, the call always failed there and every window time was an estimate.
- `test.sh` passes on macOS with the same count as on Linux. The scripts no longer need GNU `date -d`, `realpath -m`, `readlink -f`, `mapfile` or `/proc`, and `proc.py` reads other processes through `sysctl` and `ps` on macOS.
- On macOS a scheduled run lost its `until` time and its folder, because bash 3.2 kept two arguments as one word. Both are recorded now.
- A scheduled run started from a stripped environment (cron, launchd) finds Homebrew's tmux.
- `run-agent jobs` shows each runner's state and the runs that failed since you last looked, and `run-agent clean` deletes job files older than 30 days.
- `test.sh` can no longer touch a live tmux pane.
- The PermissionDenied hook that logged denied run-agent commands, added earlier in 1.3, is removed from `settings.json`, with `run-agent.sh --denied` and `--install-denied`. The review of the log is finished and no allow rule was added. `~/.claude/run-agent/denied.log` is left on disk.

### Install 🧰

- `install.sh` registers the run-agent MCP server for every session, and `--check` has a line for it and one for the assistant. When `claude` isn't on PATH it prints the `claude mcp add` command to run later.
- `install.sh` links `run-agent` and `guard` into `~/.local/bin` and installs the usage-guard and `/run-agent` hooks with the settings merge.
- A settings merge into a `settings.json` that already has its own `hooks` keeps your hooks and adds the repo's.
- `install.sh` never makes a `.pre-link` copy. Your own agent, skill or command with one of this repo's names stays, and the run prints `kept yours: <path> (repo's not installed)` and exits 0. `--agent-clash replace` and `--settings replace` delete yours with no copy. Exit code 3 is gone.
- After you move the clone, a plain `./install.sh` from the new folder points every link under `~/.claude` at it and prints `relinked <path> (was <old target>, now missing)`. A link to a file the repo no longer has is removed, and the old path leaves `settings.json`. With `~/.claude/claude-config.json` missing as well, the status line and the terminal setup stay installed.
- An install from before v1.3 had `~/.claude/hooks` as one link into the clone, so the installer wrote into the clone. It now makes `hooks` and `skills` real folders first and refuses to link anything that resolves inside the clone. `git status` in the clone is the same before and after a run.
- A link that can't be made prints `install: could not link <dst>: <error>`. Before, the run ended with exit 1 and no message.
- With python3 or tmux missing, `install.sh` names each one with its install command and exits before it changes a file. On a Mac without the Xcode tools it no longer runs the `/usr/bin/python3` stub that opens the install dialog.
- `--check` fails on a personal path only in a tracked file, and an untracked one prints `WARN`. It prints `WARN` for each `.pre-link` copy an older installer left under `~/.claude`, `SKIP` for a file of yours it left alone, and one `SKIP` for the hook checks when your choice is `--settings keep`.
- The iTerm2 default profile from before `--default-profile` is saved in `~/.claude/claude-config.json` as `itermDefault`. The Windows Terminal script no longer writes `settings.json.pre-link`.
- On Windows, a second `./install.sh` no longer stops on a settings.json with an em dash or emoji (Python read it as cp1252), and `--check` reads the defer-artifact entry in Claude Code's `;`-separated plugin list. Where systemd won't enable the reboot service (CI runners, containers), `install.sh` adds the restart line to your shell rc.
- New `bin/resolve-kept-edits.py`: when `git stash pop` or `git merge` stops on a conflict during an update, it keeps your lines and adds the release's. In a JSON file a value you changed keeps your value, the release's new keys and list entries are added, and a list entry both sides changed stays one entry with your value. UPDATING.md steps 6 and 7 run it.
- `UPDATING.md` has three new sections: "Coming from an install before v1.3" (it copies iTerm2's preferences file out of the clone before the pull and puts it back after), "Moving the clone" and "What no test covers". In the 1.2.1 → 1.3 step Claude installs `uv` itself.
- Removed: `demos/`, `RELEASE_NOTES.md` (this file has the same notes), and the report-writer eval's golden rounds 1 to 4. The checkout is about 17 MB smaller.

### Tests 🧪

- The install workflow runs on every push to `main` and every pull request, as well as on a release and by hand, on Ubuntu, macOS and Windows. Its `docker` job runs the scenarios in a fresh ubuntu:24.04 container. It also runs the run-agent tests on Ubuntu and macOS.
- `test/install-scenarios.sh` gained scenarios for the September layout with the iTerm2 preferences setting, a moved clone, a home with its own agents, skills, commands, hooks and settings, a stock Mac PATH under `/bin/bash`, a clone and projects folder with spaces in their names, and `noguard`, `assistant`, `oldtag`, `nokeychain`, `plist` and `nohook`. `SCN_ONLY=<name>` runs one.
- Updating an install that has your own edits is tested. The `dirty` scenario starts from a lived-in install of v1.2.1, and again of v1.3.0-beta.5: two commits of your own, a side branch, uncommitted edits, a `settings.json` line the release also changed, a skill link replaced with your own folder, and session, history and plugin files. It runs UPDATING.md's steps as commands. Every edit is there afterwards, `git stash list` is empty and `--check` passes.
- `test/rehearsal.sh` runs on the maintainer's Mac, in Docker: an older install with edits, then README's update sentence typed into `claude -p`, from v1.2.1 and from v1.3.0-beta.5. No login is stored on GitHub.
- On macOS the tests run the way a stock Mac would: `test/stock-mac.sh` runs `install.sh`, `--check` and every test script under `/bin/bash` 3.2 with the stock PATH. `test/iterm2-live.sh` opens iTerm2 on the runner and checks its preferences file is unchanged by the update. `test/real-usage.sh` calls the real usage API with a fake token over verified TLS.
- `test/redgreen.sh` takes each Mac fix out in turn and shows its test fail. `test/replay-page.sh` builds the release page from the workflow run, those red counts and the rehearsal results.

### Settings ⚙️

- `settings.json` gains the usage-guard hooks. usage-guard acts only in a `claude --agent worker` session and its subagents. Besides the launch limits it blocks a worker's edits to the guard's own state, `settings.json` and `worker.md`. The status line shows `guard 7/30 12.4M FE`. See `hooks/usage-guard/README.md`.
- With the usage-guard script missing or unreadable, the 7 hook commands exit 0 and tools keep running. The first hook call of a session prints `usage-guard: script missing at <path>, guard is off; run ./install.sh`, once.
- The defer-artifact mod keeps the Artifact tool's 38 KB schema out of every session and subagent until you ask for an artifact, when Claude loads it through ToolSearch. Measured here, a subagent's first request drops from 22,565 to 10,093 tokens.
- `settings.json` allows six narrow run-agent Bash rules and `mcp__run-agent__*`, so auto mode never sends a run-agent call to the classifier. The installed copy names your clone's own path in those rules.
- `autoMode.allow` keeps Claude Code's defaults and adds one sentence describing run-agent.

### Known issues

- usage-guard needs Claude Code 2.1.296 or newer and defer-artifact needs 2.1.293 or newer. Run `claude update` first.
- A session's first second or two can start before the run-agent MCP server connects. The agents use the Bash form then.
- The Windows Sandbox test needs nested virtualization for WSL inside the Sandbox, which some PCs don't have.
- Stability still needs work. UPDATING.md's "What no test covers" names four things that are checked only by hand: the live login token and real usage numbers, sleep, wake or a reboot while a run is scheduled, a Keychain dialog in a GUI session, and iTerm2 showing the profile.

### Agent versions 📄

- planner.md at 751a899 (2026-11-17)
- worker.md at a839db2 (2026-11-18)
- evaluator.md at a839db2 (2026-11-18)
- helper.md at 723ebb1 (2026-11-09)
- report-writer.md at 8c5b81a (2026-11-09)
- report-checker.md at 81cd4b6 (2026-11-06)
- researcher.md at 238bb09 (2026-11-18)
- assistant.md at e472f6a (2026-11-18)

### Full log

Each entry is as it was written when its change landed, newest first. Where a later entry changes an earlier one, the later one holds.

- run-agent: an `after window` run fires at the time fixed when it was scheduled. The runner no longer asks the usage API at fire time. Before, at the instant a window ended the API already named the next window's reset, five hours on, so the run slept up to an hour (logged `fired late`), or was skipped when that reset was past its `until`.
- run-agent: the `after window` time is the usage API's reset, rounded up to a whole second; with no answer from the API it is five hours after scheduling. The last cached answer and the estimate from session files no longer set it, because either can be earlier than the real reset and start the run before the window opens. They still stand in for `N h before the window` and for the reset a dry run shows.
- run-agent: `jobs` shows `live` or `assumed (now + 5 h)` beside an `after window` run's time, and `jobs.log` adds `(due 8:16:40 PM ET live, woke 0 s after)` when it fires.
- run-agent on macOS: the usage API call verifies TLS with `/etc/ssl/cert.pem`, and reads the token from the Keychain item "Claude Code-credentials" when the one in `~/.claude/.credentials.json` has expired. Before, the call always failed there and every window time was an estimate.
- run-agent: runs scheduled in the same instant each get their own job id. Before, two callers could take the same id: one job replaced the other, and the second caller ended with `FileNotFoundError` on `<id>.json.tmp` and had no scheduled run. Seen on Nov 21 when three lanes reached the 5-hour limit in the same second.
- With the usage-guard script missing or unreadable, the 7 hook commands in `settings.json` exit 0 and tools keep running. The first hook call of a session prints `usage-guard: script missing at <path>, guard is off; run ./install.sh`, once. Before, every Bash, Agent and Edit call was blocked until the script came back.
- Fixed: the beta.4 known issue "with `--agent-clash keep`, the repo's assistant is installed as a copy outside the clone and can't find its MCP server". The assistant has lived in `assistant/` since beta.5 and is never copied under `~/.claude/agents`; a project links it and its MCP server and guard hook resolve inside the clone. The `assistant` scenario in `test/install-scenarios.sh` checks this, and the line is gone from the release notes.
- `install.sh`, clone moved and `~/.claude/claude-config.json` missing: the status line and the terminal setup stay installed. Before, their broken links were not counted as this installer's, so the rerun dropped the terminal setup and left the status line as "kept yours".
- Tests: the install workflow runs on every push to `main` and every pull request, as well as on a release and by hand. New install scenarios `noguard`, `assistant`, `oldtag` (v1.2.1's own installer, then this one) and `nokeychain`; `moved` and `theirs` each gained a case. On macOS the run-agent tests run under `/bin/bash` 3.2 with the stock PATH, and `test/real-usage.sh` reads a fake Keychain item through the real `security` and calls the real usage API with a fake token (it must answer 401, over verified TLS). `UPDATING.md` lists what no test covers.
- Updating an install that has your own edits is tested. The new scenario `dirty` installs v1.2.1, and again v1.3.0-beta.5, with that release's own installer, adds lines to `CLAUDE.md` and an agent, edits a `settings.json` line the release also changed, replaces a skill link with a folder of its own, and runs UPDATING.md's steps as commands. Every edit is there afterwards, `git stash list` is empty and `--check` passes.
- New `bin/resolve-kept-edits.py`: when `git stash pop` or `git merge` stops on a conflict during an update, it keeps your lines and adds the release's. In a JSON file a value you changed keeps your value and the release's new keys and list entries are added. A list entry both sides changed stays one entry with your value. UPDATING.md now has Claude install `uv` itself during the 1.2.1 → 1.3 step, and the Docker rehearsal checks it is there afterwards. UPDATING.md steps 6 and 7 run it. Before, those steps said "resolve by keeping the user's lines" and left the how to the reader.
- UPDATING.md, "Coming from an install before v1.3": the first step copies `iterm2/com.googlecode.iterm2.plist` out of the clone and puts it back after the pull. The release no longer has that file, so the pull deleted it while iTerm2 was reading it. The new scenario `plist` checks the file is byte-identical afterwards.
- Tests: the new scenario `nohook` runs every hook command of the installed `settings.json` with the file it runs missing and expects exit 0. The install workflow has a `docker` job (the scenarios in a fresh ubuntu:24.04 container, with the clone's history). `test/redgreen.sh` takes each Mac fix out in turn and shows its test fail.
- The `dirty` scenario's start state is now a lived-in install: two commits of your own on `main` and a side branch, session files under `~/.claude/projects/`, `history.jsonl`, a `plugins/` folder, and a `~/.claude/settings.json` that is your own copy (`--settings merge`). The update merges the release into your commits (UPDATING.md step 6). Afterwards the commits, the branch and every edit are there, the session, history and plugin files are byte-identical, and your settings keys remain.
- UPDATING.md: step 6 merges with `--no-edit`, and step 9 says what to check when the release was merged into your own commits. The line about setting `TAG=v1.3.0-beta.5` by hand is gone.
- Tests on macOS run the way a stock Mac would: `test/stock-mac.sh` runs `install.sh`, `--check` and every test script under `/bin/bash` 3.2 with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. `test/iterm2-live.sh` installs iTerm2 on the runner, opens it reading its preferences from a September clone, runs the update, and checks the preferences file is unchanged and the "Claude tmux" profile is installed.
- `test/rehearsal.sh` runs on the maintainer's Mac, in Docker: an older install with edits, then README's update sentence typed into `claude -p`, from v1.2.1 and from v1.3.0-beta.5. The Claude login comes from the Keychain item `claude-config-rehearsal` and goes to the container as an environment variable. The workflow's `rehearsal` job is removed; no login is stored on GitHub.
- `test/replay-page.sh` builds the release page from `gh run view` of a commit, the red counts of `test/redgreen.sh` and the rehearsal results. Its banner reads PASSED only when the four jobs are green, each of the 11 Mac errors has a red run, and both rehearsals passed.
- Removed: `demos/`, `RELEASE_NOTES.md` (this file has the same notes), and the report-writer eval's golden rounds 1 to 4 with their `make_r1.py` to `make_r4.py` (round 5, the one the writer reads, stays). The checkout is about 17 MB smaller.
- run-agent: scheduling works on macOS. `start_runner` started the sleeper with `setsid`, which macOS does not have, so every scheduled run there (and the denied.log review install.sh schedules) was `errored: ... setsid: command not found`. Without `setsid` it starts through `python3 -c 'os.setsid(); os.execvp(...)'`, the same pid and a new session. Found by v1.3.0-beta.3's install workflow on macOS.
- install: on Windows a rerun of `./install.sh` (a settings merge into an existing `settings.json`) stopped with `UnicodeDecodeError: 'charmap' codec can't decode byte 0x9d`: Windows Python reads files as cp1252, and the installed settings.json holds UTF-8 text. `install.sh` exports `PYTHONUTF8=1`. Found by v1.3.0-beta.2's install workflow (`rerun with no flags exits 0 (got 1)`), reproduced and checked in Git Bash on Windows.
- install: `--check` finds the defer-artifact mod on Windows (the `;`-separated `CLAUDE_CODE_PLUGIN_DIRS` holds a `C:/...` path, which the old `:` split cut apart), and the reboot revive falls back to the shell rc line whenever `run-agent-revive.service` is not enabled afterwards (a CI runner's user manager answers but won't enable a unit from a scratch HOME). `test/install-scenarios.sh` expects the native path and separator on Windows. Found by v1.3.0-beta.1's install workflow (Ubuntu and Windows failed).
- v1.3 release tree: one planner and one run-agent. `planner.md` already held planner-fix10's newest text, so `agents/planner-fix10.md` and `agents/planner-fix32.md` are deleted and `researcher.md`'s description names `planner`. `skills/run-agent-dev/` (with `promote.sh` and `apply_agents.py`) and `bin/run-agent-dev` are deleted; the dev files with a later commit than their `skills/run-agent` twins differed only in their `run-agent-dev` paths. `skills/run-agent/mcp/mcp.json` is gone (nothing read it). `install.sh` registers the run-agent MCP server (`claude mcp add --transport stdio --scope user run-agent -- ~/.claude/skills/run-agent/mcp/server.py`, replacing a registration that points elsewhere) and prints that command when `claude` is not on PATH; `--check` has a PASS/FAIL line for the registration, one for the assistant, and a NOTE when `uv` is missing. `test/install-scenarios.sh` scenario b starts from a `settings.json` with its own `hooks` key and checks that the merge keeps it and adds every repo hook entry. The settings allow `mcp__run-agent__*` and `autoMode.allow` is `"$defaults"` plus one sentence describing run-agent; worker and evaluator hand off through the MCP tools with the Bash form as fallback.
- assistant agent (`agents/assistant.md`, `assistant/mcp/server.py`, `assistant/hooks/guard.py`): the operator of your Claude Code sessions in tmux, run as `claude --agent assistant`. Seven MCP tools (`assistant_panes`, `assistant_projects`, `assistant_launch`, `assistant_send`, `assistant_layout`, `assistant_schedule`, `assistant_jobs`) report each pane's state, start an agent in an empty shell, answer a waiting session, close or retile panes and schedule runs through run-agent. A PreToolUse guard hook blocks closing a pet pane or its own pane, answering a judgement menu (an evaluator's verdict, a planner's choice) and a forced layout change on a running pane without a yes. Both start with `uv run --script` from `../assistant/` next to the agent file's real path. Copied in from its own repo, where it was built and tested.
- planner: research runs through the `researcher` subagent. The planner writes a fact list and a tier (`none`, `external`, `repo`, each with a call and time budget), splits it into at most three groups sent in one message, and writes each finding under its own heading in `plans/research/<slug>.md`; the plan's Facts carry one sentence pointing at it. `planner.md` is the planner-fix10 prompt, which passed 5/5 replay checks in 4/4 sessions.
- worker: denial routing, no prose questions, wait-only self-scheduling. A permission or classifier denial is written under `## Denied` with at least two other routes tried; the last message never ends on a question or an offer; when only time is left the worker schedules its own relaunch, appends `## Waiting — <time> ET` and ends with the `scheduled #N` line. Worker eval: c10-denied-kill 3/3 and c11-wait-only 3/3 (baseline 0/3 each), no false claims.
- evaluator: hidden opens. On the desktop every item is opened hidden first (`win-app.sh --hidden`, `term-open.sh`), then one question "Ready for me to move windows and start?", and `evshow.sh` shows each item only after the answer before its question. `plans/EVAL.md` quotes each item's `hidden:`, `elapsed` and question-timing lines and one `no-flash: PASS|FAIL` line. A failed open is retried twice, then reported with the item's path. Files open as pages in Firefox (`file-page.sh`: a `.md` rendered, anything else numbered text); VS Code is retired from the openers.
- CI: the `install` workflow runs on published releases only.
- run-agent (v1.5.0, built and proven in the dev copy; live after you run `skills/run-agent-dev/promote.sh`): run-agent as an MCP server so an agent's handoff is never read by the auto-mode classifier. `skills/run-agent-dev/mcp/server.py` (stdio, server `run-agent`, FastMCP via `uv run --script`) has five tools, `next`, `schedule`, `handoff`, `jobs`, `cancel`, each calling `run-agent.sh` for the calling session's own pane; the allow rule `mcp__run-agent__*` settles a call before the classifier sees it. The six Bash rules stay as the fallback and `autoMode.allow` gains `"$defaults"` plus one sentence describing run-agent. `promote.sh [--dry]` copies the server to `skills/run-agent/mcp/`, runs `claude mcp add --transport stdio --scope user run-agent -- ~/.claude/skills/run-agent/mcp/server.py`, edits both settings files, runs `apply_agents.py` on the five agent files (`tools:` gains `mcp__run-agent__*`; the `--next` and schedule lines name the tools, Bash form kept as fallback) and appends the tool list to `skills/run-agent/SKILL.md`. Proof (scratch config, private tmux server, haiku, auto mode): the 7 handoffs the classifier blocked on 14-15 Nov, each as the literal Bash command and as its MCP twin, 3 runs, 42 rows, none blocked; a planner → worker → evaluator chain handing off with `next`, no denial or prompt; 59 command-shape cells (13 spellings x 5 actions), all pass. One thing seen: a session's first turn can start before the server has connected (about 1-2 s), so a call in the first seconds finds no tool; the Bash form covers that. (folded into `skills/run-agent` and install.sh in this release)
- run-agent v1.5.1: the dev-copy lock is gone, so any worker can replace its own pane. v1.5.0 made every copy under `run-agent-dev` refuse `next`, `handoff`, `schedule`, `cancel` and `--relaunch` outside the `run-agent-dev-test` tmux socket; that was meant to protect one worker during one test run, not to be a rule. `DEV_COPY`, `dev_lock` and the refusal are deleted from `mcp/server.py`, `run-agent.sh`, `launch.py`, `jobs.py` and `runner.sh`, and the 4 `test.sh` cases expect the test-mode refusal again (exit 2). The server that `promote.sh` copies to `skills/run-agent/mcp/` is now this lock-free file. `promote.sh` has a sixth step: it runs `apply_agents.py` on the installed `~/.claude/agents` (regular files, not links into the clone) when its `--check` shows a line to change, so `promote.sh` alone promotes everything; `--dry` prints the step. `apply_agents.py`'s handoff line now says when the Bash form is used: when the tool is not listed yet, as a standalone command (a compound command still reaches the classifier). Not live until you run `cd ~/files/claude-config && ./skills/run-agent-dev/promote.sh`. (folded into `skills/run-agent` and install.sh in this release)

- run-agent v1.5.2: v1.5.0/v1.5.1 are live (promoted 16 Nov: server registered, `mcp__run-agent__*` allowed, the five agent files converted, `skills/run-agent/mcp/` now tracked). `bin/run-agent` passes the script's own flags through: `run-agent --jobs` and `run-agent --next evaluator "."` used to go to `--cli`, which read `--jobs` as words and opened a "which agent?" tmux popup that waited forever; a first word starting with `--` now goes to `run-agent.sh` as it is (same in `bin/run-agent-dev`; one test case in each `test.sh`). Proven in production on 17 Nov: a `claude --agent worker` session in a spare tmux window called `mcp__run-agent__next` with `run: true` and its pane restarted as a new worker with no denial or prompt; `--jobs` and `--next` as standalone commands in all six allow-rule spellings, 3 runs each, were never blocked (36/36); the 7 compound commands the classifier had denied on 14–15 Nov were not blocked either (0/7). (folded into `skills/run-agent` and install.sh in this release)

- run-agent v1.5.3: an agent's closing next step never carries the calling session's model or effort. `--next` (and the MCP `next` tool, which calls it) used to drop them only for worker and evaluator, so an evaluator on opus that ended in a replan printed `/run-agent planner "Replan based on plans/EVAL.md" opus …` and the planner started on opus instead of its own default (fable, low). `next_line()` in `launch.py` no longer reads `--model`, `--effort` or the `(model)` suffix of `--name`; every agent's line is the agent and its prompt only. `test.sh`: the planner case now expects no model/effort, one new case for `helper` (315 cases). Merged from the dev copy: test mode also accepts the bare socket name `run-agent-test` (`run-agent.sh`, `launch.py`, `runner.sh`); `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` stays out.

- usage-guard round 2: blocks that steer to a cheaper run, and a count the worker can see. A block now ends with a smaller command that fits (`Run: bash tests/agent-replay/run.sh -j 2`; at the daily cap the same script at `-j 1` with as many scenes as launches are left; `use checks that start no claude` at 0) and no block or `worker.md` line names `guard allow`; `worker.md` tells the worker to redesign the check for fewer launches and note what the cap stopped. The worker is told its count at session start (new SessionStart hook), on every allowed launch (`usage-guard: 12/30 used today, 18 left`) and with a planning line at 20 and 25; a command of 3+ launches taking over half of what is left is turned back once and runs when sent again within 10 minutes. Scanner: string literals in interpreter heredocs, arguments of `git commit`/`echo`/`printf`/`grep`/`cat` and heredocs written to files that are not run count 0 and pass at 30/30; a heredoc written and run in one command, `$(…)` that runs a launch script and `env $vars "$REAL" -p` are counted. A new PostToolUse hook raises the count to the headless sessions a command really started. The eight 15 Nov log lines that looked like commits counted as launches each ended in a real `run.sh` call hidden by the 120-character cut; the log line now shows the part that launches. `guard usage` of a past day is cached (199 s, then 0.2 s); new user command `guard recount [n]`. Both settings files gain the PostToolUse and SessionStart entries install.sh installs it. 286 test cases.

- usage-guard (`hooks/usage-guard/`, needs Claude Code 2.1.296+): a hook that stops a worker's expensive launches before they run. In a `claude --agent worker` session it blocks more than 2 headless `claude` runs at once (scripts are followed three levels down), a headless launch without `--max-budget-usd` and `--max-turns`, more than 30 launches a day per project, a 4th concurrent subagent, a subagent task already dispatched today, and any edit of the guard's own state, `settings.json` or `worker.md`. Every worker subagent becomes `helper` (now Sonnet, low effort, 40 turns) with the model set by the hook on the call, except `report-writer`, which stays `report-writer` on Opus and counts toward the 30; `run-agent` starts workers with `CLAUDE_CODE_SUBAGENT_MODEL=sonnet`, `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=3`, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` (not `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`: under it the report-writer ran on Sonnet). New `guard` command for the user: `guard allow 2h`, `status`, `revoke`, `log`, `usage [today|week]`. The status line shows `guard 7/30 12.4M FE`. `Agent(helper)` leaves `permissions.deny` so a worker can start a helper. See `hooks/usage-guard/README.md`.

- run-agent test.sh can no longer touch a live pane. On 9 Nov a worker ran `test.sh` from its own tmux pane and the hook cases, finding that session's pane through the parent `claude` process, ran `tmux respawn-pane -k` on it and killed the session mid-run. Guard: `test.sh` exports `RUN_AGENT_TEST=1` and unsets `TMUX`/`TMUX_PANE`; with the flag the scripts ignore a parent `claude` the test did not make, and refuse (exit 2) any tmux server or job store that is not the test's own. Two canary cases prove it both ways.

- report loop closed (v1.3 R12–R15). `worker.md` no longer names `plans/DATA_REQUEST.md` (a file the writer never wrote): its `## Reports` section points at `skills/write-report/SKILL.md`, the one place the loop is written. The writer fails loud and early: `agents/report-writer/preflight.py` is its first command, before any data is read, and prints nothing or one line `blocked: <what to run>` (missing `build.py`/`check.py`, no node, no playwright, or a playwright whose Chromium build is not downloaded: `node "<playwright>/cli.js" install chromium`); it asks `cards.mjs --find`, so it uses the same lookup the build does. Every other failed run ends in one line starting `blocked:` or the `check.py: FAIL (…)` line (the old `open: focus_findings` ending is gone). `NOTES.md ## Checker` rows end in a `status` cell, `fixed` or `rejected: <reason>`, and check.py's new `checker_rows` fails when a `high` finding has no row or no such cell. Worker eval case `c17-report-loop` (in agent-eval-experiment) plays a writer that answers blocked, send-back, FAIL, then PASS, and fails a run that reruns without doing what the last line named, types data rows by hand or changes the built files.

- defer-artifact mod (`mods/defer-artifact/`, needs Claude Code 2.1.293+): a `tool.describe` hook marks the built-in `Artifact` tool deferred, so sessions and subagents carry a one-line deferred entry instead of its 38 KB schema (plain-project `/context` System tools 19.7k → 7.3k; a subagent's first request 22,565 → 10,093 tokens). Claude loads it with `ToolSearch select:Artifact` when asked for an artifact. install.sh adds the mod's absolute path to `env.CLAUDE_CODE_PLUGIN_DIRS` (kept alongside any existing entries, merge and replace modes) and `--check` reports it. Turn it off in `/plugin` or by removing that entry. `weekly-roundup/SKILL.md` gains one line telling Claude to load Artifact first; `artifact-design` and `artifact-capabilities` are `name-only` in `skillOverrides`.

- report-writer: same data, same report. Launch from the data dir: `cd "<data dir>" && claude -p --agent report-writer ". — <question> --out <dir>"` (`write-report/SKILL.md`, the agent's description, `USAGE.txt`, `README.md`); run from a project root, the project's AGENTS.md entered the writer's context and the 2026-11-06 19:53 ET base-context report built its opening from it. The writer treats any AGENTS.md, CLAUDE.md or memory text as not data, writes no fact that is in no data file, and lets no method detail (borrowed session, machine, how it counts) in unless its figure settles the section.
- report-writer: Length is counted. `NOTES.md ## Length` lists the quantities `question.txt` names (one line each with its `{key}`), `outline.md` has one middle row per quantity in that order, and the report is long at four or more, short otherwise. `check.py --prose` gains `length_from_ask`.
- report-writer: opening fit over novelty. `## Openings` scores all five forms (`fit: <form> — fit|no-fit — detail`), the best fit wins and the ledger's last two forms only break ties. `opening_ledger` fails a repeat of the last form only when the `pick:` line does not say why it beat the runner-up (or calls it a tie); title shapes still differ from the last two.
- check.py `--prose` gains four slip checks: `doubled_unit` (a `{key}` followed by its own unit word, or a unit abbreviation followed by its expansion), `split_sliver` (a `::split` segment under 3% that its section never names with small/little/sliver or its figure), `machinery_aside` (a middle sentence whose subject is the study's method and that carries none of its section's settling keys), `opening_subject` (the scene names the ask's noun and no session, run or machine outside its own keys). New fixture `agents/report-writer/cases/slips` (the 19:53 ET report) fails all four; golden r5/B still passes.

- report-writer: the middle stays on the ask. Before any prose the writer writes `outline.md` in the output directory: a three-sentence `## Recap` (what you asked, the deciding `{key}`, what the ending says), a `## Sections` table with one row per section (`| # | heading | ask clause | settles with | words |`, the clause a verbatim fragment of the quoted ask, one or two keys, middle budgets 60-180 summing to at most 600 words short or 1100 long) and a `## Left out` list of arms, mechanisms and figures that get one sentence at most. A section with no row is not written; rows are only removed or merged between cycles. Every middle section's first sentence names the ask's subject in the user's noun. The "Outline" section of `report-writer.md` says why (STORM, GPT-Researcher, Open Deep Research keep long reports on topic by structure). `build.py` writes each section's prose word count into `cards/measure.json` as `words`.
- report-checker: the `read` pass reads `outline.md` first and writes a `focus` entry per middle section (`advances`, `restates`, `tours`, `mechanism`, `data-shape`) plus a high `"claim": "recap"` entry when the thread contradicts the recap. The writer cuts or folds every section not marked `advances` in its next cycle and records it in `NOTES.md ## Focus`, which ends with the recap verbatim.
- check.py `--prose` gains the `focus` group: `outline_present`, `outline_match` (report headings equal the outline rows, in order), `outline_budget` (each middle section within its budget x 1.15), `unasked_once` (each `## Left out` item in at most one sentence) and `focus_findings` (no non-advancing section left; no "Overall/In summary/In short/To recap" paragraph in the middle). Golden r5/B gains an `outline.md`; new fixture `agents/report-writer/cases/focus` fails `outline_match`.

- report-writer: denser middle sections. `build.py` draws three new blocks beside `::bars`: `::table` (header words, body cells `{key}`/`[[id]]`/words, a column's shared unit printed once in the header, a typed digit is a build error, a table taller than one card splits with its header repeated), `::split` (one total as a stacked bar with a labelled legend; parts must sum within 1% or the build stops) and `::pair` (the same unit under two arms as two cards side by side). `report-writer.md` puts a block in every middle section that compares three or more keys or splits a total, and the writer records each section's choice in `NOTES.md ## Visuals`. `check.py --prose` gains `visuals`. `cards/measure.json` lists every block's height and width and each card's `scroll_width_px`.
- report-writer: the opening varies. Five forms (`moment`, `log-line`, `break`, `expected-vs-got`, `person`) replace the single clock-time scene; the writer picks the one the data supports, with two runners-up, in `NOTES.md ## Openings` (`pick: <form> — why`). `build.py` writes each built report's form and title shape (`The _ that cost a _`) to `agents/evals/report-writer/ledger.jsonl` (a rebuild replaces its own line; `$REPORT_LEDGER` overrides the path), and `check.py`'s `opening_ledger` fails a form or title shape that matches either of the two entries before it. Seeded with the Nov 1 spire and Nov 5 base-context reports.
- report-writer: `cards.mjs` picks the first playwright whose headless Chromium build is downloaded, so a project's older playwright no longer stops the cards with "Executable doesn't exist".

- run-agent (v1.4.0): runs without asking by default. A typed `/run-agent <agent> …` (and `run-agent …`, `--relaunch`, `--cli`, a `+` group, a scheduled run) that parses cleanly replaces the pane, prints `scheduled #N …` or opens its window at once, with no question. The single word `confirm` (or `--confirm`) restores the question (haiku confirm session from the hook, `[y/N]` from the shell; No prints `nothing changed`); inside quotes it is prompt text. `--parse` reports `"confirm": 1|0` in place of `"force"`. Still asked without `confirm`: which agent when none is named (the usage/exit-2 path is gone), an unplaceable word, which job to cancel with 2+ pending, and an `in <dir>` folder that does not exist (created only after a yes). The old force words are gone: `force`, `go`, `yolo-run`, `!`/`agent!`, `just do it`, `no confirm` are ordinary unplaced words (asked about), `now` is a time word meaning at once, `-f`/`--force` pass through like any unknown claude flag. Outside tmux with no terminal to ask in the message is `no terminal to confirm in; drop \`confirm\` to run without asking`. `--next` and `--handoff` output, the hook and `settings.json` are unchanged; pending jobs keep firing.
- run-agent (v1.3.1): run-agent calls are never classifier-blocked. `settings.json` allows six narrow Bash forms, each a literal program prefix with no `*` before it: `~/.claude/skills/run-agent/scripts/run-agent.sh *`, the same under the clone's path, `bash <either scripts dir>/*`, `~/.local/bin/run-agent *` and `run-agent *`. A `~` in a rule never matches an absolute command, so `install.sh --settings replace` now writes `~/.claude/settings.json` as a copy generated from the repo's with the clone's absolute path in those rules (rerun install.sh after editing the repo's); `--check` lists the six rules, FAILs naming a missing one, and FAILs when `settings.json` is still a symlink.
- run-agent (v1.3.1): a `PermissionDenied` hook (`run-agent.sh --denied`) appends every denial whose command names run-agent to `~/.claude/run-agent/denied.log` (`<ET time>  <tool>  <command>  <reason>`), ignores the rest and prints nothing. It lives one week: install writes `~/.claude/run-agent/denied-until` and schedules (once, `run-agent.sh --install-denied`) a helper run a week out, in its own new tmux window, that reviews the log and removes the hook; `install.sh --check` FAILs if the hook is still installed after that date.
- run-agent (v1.3.1): the default model is said out loud. With no model word the confirm question shows `model: sonnet (default; type fable/opus to change)`, the `scheduled #N` line and `/run-agent jobs` show `(sonnet, default)`, and the run's `--name` is `<agent>: <folder> (sonnet)` (the agent file's `model:` frontmatter, else settings.json `model`, else sonnet). A typed model shows as typed.
- run-agent (v1.3.1): scheduled runs really start. A job records at creation the absolute `claude` binary (`command -v claude`, else `~/.local/bin/claude`) plus `PATH`, `HOME` and `SHELL`, and `runner.sh` runs that binary with that environment, so a job created from a stripped environment (no `PATH`, no `TMUX_PANE`) still starts claude. After tmux accepts the launch the runner waits up to 30 s for a `claude` process in the target pane: success logs `fired` (`in new window` / `in new session` as before); failure logs `failed: claude did not start (<first stderr line>)`, leaves the error on screen and marks the job `failed`. A typed `/run-agent` records the typing pane and replaces it at fire time; `split`/`window` still open a new window.
- run-agent (v1.3.1): failed and skipped runs are not silent. `/run-agent jobs`, `run-agent jobs`, `install.sh --check` and the next `/run-agent` print each run that failed or was skipped since a human last looked, one line with time and reason, then mark them seen. `jobs` prints `state dir N MB, trim with run-agent clean` past 50 MB; `run-agent clean` (`run-agent.sh --clean`) deletes `done/*.json` and `logs/*` older than 30 days. `runner.log` is gone and nothing writes it. Job files from before this version keep working unchanged.
- run-agent (v1.3.1): `test.sh` replays the four incidents (the pogo and slay-the-spire command strings against the shipped rules with a local split-and-prefix matcher, a job from a stripped environment, `(sonnet, default)` in the confirm text, a claude that exits 127) and fires a pre-1.3.1 job file; its default models come from a fixture agents folder (`RUN_AGENT_AGENTS_DIR`).
- run-agent (v1.3.1): the hook costs nothing idle. Measured in a private tmux server (2026-11-03): the same plain haiku prompt with and without the `UserPromptExpansion` hook used the same tokens (about 13.5k in, 4 out) and the same wall time (2.6–3.3 s); a typed `/run-agent worker "." dry` answered in 0.8 s with zero parent API requests; one haiku confirm (asked, answered No) cost about 43k tokens, mostly cache reads. `test.sh` runs in about 135 s (`RA_TEST_TIMES=1` stamps each line); the suite fixtures got a `helper` agent and the pre-1.3.1 job case respawns its pane so the 127 fake claude from the case before never leaks onto its PATH.

- run-agent: a failed usage-API lookup never stops a run or a schedule and never shows as an error. A 429 is retried (1 s, 3 s); then the last live reset (cached in the state dir as `usage-reset.json` on every live answer) stands in while it is still ahead; then an estimate from session transcripts (first timestamp and last write of each recent session, 5-hour windows); then now + 5 h (no window open). `two hours before the window` schedules under all four, and the shown time names the source (`cached`, `estimated from session activity`, `assumed: …`). `dry` prints `usage reset: <time> (<source>)`, never `HTTPError`/`429` text.
- run-agent: `/run-agent` costs no tokens. A `UserPromptExpansion` hook in `settings.json` (matcher `run-agent`, 90 s timeout) runs `run-agent.sh --relaunch` on the typed words and shows its output in place of a model turn; the skill stays as the fallback when the hook is off. install.sh installs the hook with the settings merge and `--check` has a PASS/FAIL line for it, plus one for the health of pending scheduled runs.
- run-agent: time phrases resolve in `parse.py` without a model: `tomorrow at 1am` (the next calendar day), `1am tomorrow`, `tonight` / `this evening` (7 PM), `today at 5pm`, `noon`, `midnight`, weekday names, `in 2 hours 10 min`, `two hours before the window`, `1 hr before the current window`, `30 min after the window ends`, `2 h before 9pm`. The shown time names the derivation: `6:20 PM ET (two hours before window 8:20 PM, in 20m)`. A time already past is an error, not a question.
- run-agent: the haiku confirm step owns no logic. It gets the current ET time and the window reset in its prompt, has only AskUserQuestion and one Bash form (`run-agent.sh --step '<words>'`), appends every answer verbatim after ` | `, and the script decides: ask once about a word it cannot place (`Part of the prompt` / `Drop it`), resolve an unparsed time phrase itself (`| time: at 5:30 AM`), schedule, or after three answers without a run reply `nothing changed` and the words to type by hand. It never asks when the window ends and never reads a word next to a time word as a flag. The confirm session is named `run-agent: <agent> <folder> [at <time>]`, runs with `--session-id`, and its transcript is deleted when it exits, so `claude --resume` stays clean.
- run-agent: a scheduled run is a fixed five-line sleeper that `exec`s the repo's `runner.sh` as it is at fire time, so editing or committing under `skills/run-agent` while runs sleep changes nothing until they fire; it never sleeps a negative time, and one that wakes less than an hour late fires at once (`jobs.log`: `fired late`). `/run-agent jobs` shows each runner's state: `sleeping (pid N)`, `dead`, `errored: <last runner.log line>`, `waiting: no pane`; `run-agent.sh --health` exits 1 (and `install.sh --check` prints FAIL) when a pending runner is dead or errored.
- run-agent: only a human may open tmux windows. From an agent session (`--agent` on the parent claude, or `RUN_AGENT_FROM`), `split`, `window` and `+` are answered `ignored: agents replace their own pane`; immediate and scheduled runs replace the agent's own pane, and when that pane is gone at fire time the run waits (`waiting: no pane`) until the next human `/run-agent` or `run-agent` call on that tmux server starts it in a new window.

- run-agent: `/run-agent` is one Bash call now. `SKILL.md` shrank to `run-agent.sh --relaunch '<args>'`, which answers `jobs`, `cancel`, `dry` and errors itself and hands every confirmation to a short `claude --model haiku --effort low` session in the same pane. A launch either replaces the calling pane or opens a brand-new tmux window: `split` and `window` both open a new window holding only the agent, and nothing is ever added to an existing window (scheduled runs too).
- run-agent: several runs joined by `+` start together after one confirm, in one new tmux window tiled (four = 2x2), each in its own folder: `/run-agent planner "Plan part A" in ~/a + planner "Plan part B" in ~/b + …`. Works the same from the `run-agent` shell command.
- `bin/run-agent` is the same thing as a shell command (confirms with `read`, or a tmux popup); install.sh links it into `~/.local/bin` and `--check` has a line for it.
- The planner, worker and evaluator end with their next step (`run-agent.sh --next`): a sentence saying what to run and when, the `/run-agent <agent> "<prompt>" <model> <effort>` line on its own, then the plain `claude --agent …` form on its own labelled line.
- `bin/run-agent` confirms in the terminal again on Python 3.14 (opening `/dev/tty` read-write failed, so it fell back to a popup and changed nothing).
- run-agent: scheduled runs survive a reboot or WSL restart. `run-agent-revive.service` (a systemd user service install.sh enables; the shell rc on macOS) runs `run-agent.sh --revive` at boot, silently: a run still ahead gets a new runner, and one that came due while the machine was down is skipped and logged as `skipped` in `jobs.log`. After a tmux restart the run opens a new window instead of reusing an old pane id. `/run-agent jobs` marks runs whose runner is gone.

## v1.3.0-beta.5 — 2026-11-21

Pre-release that fixed updating a September install on a Mac and tested `install.sh` against four kinds of Mac. Its changes are under v1.3.0 above.

## v1.3.0-beta.4 — 2026-11-18

Pre-release with the first full set of 1.3 notes. Its changes are under v1.3.0 above.

## v1.3.0-beta.3 — 2026-11-18

Pre-release. Its install workflow passed on Ubuntu and Windows and failed on macOS (the `setsid` entry in v1.3.0's Full log). Its changes are under v1.3.0 above.

## v1.3.0-beta.2 — 2026-11-18

Pre-release. Its install workflow passed on Ubuntu and failed on Windows (the `UnicodeDecodeError` entry in v1.3.0's Full log), and macOS got no runner. Its changes are under v1.3.0 above.

## v1.3.0-beta.1 — 2026-11-18

Pre-release. Its install workflow failed on Ubuntu and Windows (the `UnicodeDecodeError` and `--check` entries in v1.3.0's Full log). Its changes are under v1.3.0 above.

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
