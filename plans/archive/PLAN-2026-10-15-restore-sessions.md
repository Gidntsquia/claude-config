# Spec: /restore-sessions — user-only skill that reopens the Claude Code sessions a WSL/Windows stop killed, rebuilds the tmux layout, and puts a terminal pet in every window

## Ask
"Make a user-only skill (the model must never invoke it on its own; only I can run it with a slash command) called /restore-sessions. It brings back my Claude Code sessions and tmux layout after WSL or Windows stops them, for example after a Windows Update restart or a WSL update, and puts a terminal pet in the top-left pane of every tmux window." Steps 1–9, the rules and the acceptance check are the user's and are copied into Requirements verbatim where they apply.
- Layout when not recoverable: "Ask me, prefilled with a guess" (proposed table, user accepts or types corrections like `cbf1bb64 -> 1:2`).
- Packaging: "SKILL.md + find-sessions.sh" with a fixture copy of last night's transcripts under the skill's `evals/`.
- Before opening anything: "Plan table, then yes/no"; the user can drop a session from the list.
- Right result: "Fixture picks exactly the 3, and live panes sit at the right prompt"; distrust: any pane killed, any ended session reopened, any prompt sent.
- Time window: "Within 10 minutes" of the shutdown.
- Pets: "Random, no repeats" across windows.
- Overflow: "New tmux window in the same session".
- Windows Terminal window: "Bring it to front with win.sh"; if that fails, say it's in the taskbar.

## What to build
A skill at `skills/restore-sessions/` (symlinked into `~/.claude/skills/` by the existing install) that the user runs as `/restore-sessions`. It works out the stop time from `journalctl --list-boots`, runs `scripts/find-sessions.sh` to list the Claude transcripts whose mtime falls in the 10 minutes before that stop (those are the sessions the stop killed), reads each one's cwd, agent, model, permission mode and whether it died mid-task, proposes a tmux session/window/pane placement around whatever panes and `claude` processes already exist, shows the whole plan as a table and asks yes/no, then creates missing tmux sessions and Windows Terminal windows, starts a different random pet in the top-left pane of each window, resumes each session in its pane with `claude --resume`, verifies after ~12 s with `tmux capture-pane` and a screenshot, and reports a window x pane table plus skipped, mid-task and changed-agent sessions. It never kills panes, sessions or servers and never sends a prompt to a resumed session.

## Facts
- `journalctl --list-boots` here prints `-1 ... Wed 2026-10-14 23:40:46 EDT Thu 2026-10-15 04:56:11 EDT`; the last column of the previous boot is the stop time, already in local (ET) time (verified 2026-10-15).
- Transcripts: `~/.claude/projects/<-home-jaxon-files-...>/<session-id>.jsonl`. Subagent transcripts live in `~/.claude/projects/<project>/<session-id>/subagents/` (verified), so only top-level `*.jsonl` count. Project folders also hold a `memory/` dir.
- A killed session's last line is `{"type":"cost-state","sessionId":...}` (verified on f720125e). Transcripts carry `"agentSetting":"<agent>"` (type `agent-setting`), `"permissionMode":"<mode>"` (type `permission-mode`), `"cwd":"..."`, and a `model` on assistant messages; they carry no tmux session/window/pane fields (verified: none in f720125e).
- Live acceptance files were already resumed this morning (mtimes 06:18–06:22), so the acceptance check must run on a fixture copy with mtimes set back to 2026-10-15 04:56 ET for the three and to their original earlier times for claude-config and archery_simulator.
- `terminal-pet` is at `~/.cargo/bin/terminal-pet`; `--pet dog`, `--pet cat`, default squid (user). `~/.claude/local-tools/win.sh` and `screen-capture.sh` exist (CLAUDE.local.md).
- `settings.json` already uses `skillOverrides: {"<skill>": "user-invocable-only"}` for the user's own skills.

## Requirements
1. (user) The skill lives at `skills/restore-sessions/SKILL.md` with frontmatter `name: restore-sessions`, `disable-model-invocation: true`, and `settings.json` gets `"restore-sessions": "user-invocable-only"` under `skillOverrides`. It never runs unless the user types `/restore-sessions`.
2. (user) Stop time: the end time of boot `-1` in `journalctl --list-boots`. If that line is missing, has no end time, or the user passes a time as `$ARGUMENTS`, the skill asks for / uses the given time. Every time the skill prints is US Eastern with the `ET`/`EDT` suffix.
3. (user) `scripts/find-sessions.sh <stop-time> [projects-dir]` (projects-dir defaults to `~/.claude/projects`) prints one line per candidate session: `session-id<TAB>cwd<TAB>agent<TAB>model<TAB>permission-mode<TAB>mid-task(yes/no)<TAB>mtime-ET<TAB>transcript-path`, sorted by mtime. A candidate is a top-level `*.jsonl` whose mtime is within [stop − 10 min, stop + 5 s] (user: "Within 10 minutes"). Files in `<session-id>/subagents/` and `memory/` are ignored. Paths are passed as `./-home-...` or absolute so no tool reads them as options. Agent is `agentSetting` from the last `agent-setting` line (blank if none: a `/clear`-ed session), model from the last assistant message, mode from the last `permission-mode` line, cwd from the last line that has one.
4. (user) mid-task = the last non-`cost-state` entry is a `tool_result` (or an assistant message with a `tool_use`) rather than a `turn_duration`/end-of-turn entry.
5. (user) Sessions already running: before placing anything, the skill runs `tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_pid}'` and `pgrep -af 'claude'`; a candidate whose id appears in a running `claude --resume <id>` command line, or whose transcript mtime is after the current boot started, is listed as "already running" and not reopened. Existing panes are never moved out of their window or killed; only new panes are split in.
6. (user) Layout proposal: target tmux sessions `0` and `1` (base-index 1, pane-base-index 1), one window each, tiled 2x2 (`select-layout tiled`), pane 1 = pet, panes 2–4 = Claude sessions, filled in mtime order starting with session 0. (user) Extras go to a new window in the same tmux session, laid out the same way. (default) A session already present keeps its windows; the pet pane is swapped into position 1 with `tmux swap-pane` if a pet is already running elsewhere in that window, else a new pane is split and swapped to top-left.
7. (user) Before anything opens, one AskUserQuestion shows: the stop time, a table `tmux session:window.pane | session id | cwd | agent | model | mode | mid-task`, the skipped sessions with reasons, and asks yes/no; the user can type corrections like `cbf1bb64 -> 1:2` or `drop c7a00432`, which the skill applies and shows again before running.
8. (user) Pets: one `terminal-pet` per tmux window, in the top-left pane, chosen at random from `squid` (default, no flag), `dog`, `cat` with no repeat until all three are used. Started with the pane's cwd at `$HOME`.
9. (user) Each session resumes with `tmux send-keys -t <target> "cd '<cwd>' && claude --resume <full-id>" Enter`. Nothing else is ever sent to that pane. Sessions with no `agentSetting` come back without an agent; the report says so.
10. (user) For each target tmux session that does not exist, `tmux new-session -d -s <name>` then `wt.exe -w new wsl.exe -d Ubuntu -- tmux attach -t <name>`; the skill then tries `~/.claude/local-tools/win.sh find`/`front` on the new window and, if that fails, the report says the window is in the taskbar.
11. (user) About 12 s after the last resume, `tmux capture-pane -p -t <target>` on every resumed pane; a pane passes when it shows the Claude prompt and the status line names the expected agent and mode. Then `~/.claude/local-tools/screen-capture.sh restore-sessions` and the skill reads the PNG to confirm a pet is visible in each window's top-left pane. Failures are named per pane in the report; nothing is retried automatically.
12. (user) Final report: a table window x pane (what each pane holds), then: sessions not reopened and why (ended earlier, already running, dropped by user), sessions stopped mid-task ("say `continue`"), and any agent or model that differs from the transcript's.
13. (user) Rules: never `tmux kill-server`, `kill-session`, `kill-pane` or `kill-window`; any test tmux server uses `tmux -L <name>`. Only reopen; never send prompts.
14. (user) Fixture: `skills/restore-sessions/evals/shutdown-2026-10-15/` holds copies (first and last 50 lines are enough) of the five transcripts in their `-home-jaxon-files-*` dirs, a `setup.sh` that sets mtimes (04:56 ET for the three killed, their original times for the two ended), and `expected.txt` with the three ids. `find-sessions.sh '2026-10-15 04:56:11' <fixture>` prints exactly f720125e…, cbf1bb64…, c7a00432… and nothing for claude-config or archery_simulator.
15. (default) Edge cases: no candidates → say so and stop; `tmux` server not running → start sessions per R10; `terminal-pet` missing → warn, skip pets, continue; `journalctl` unavailable → ask for the time; a cwd that no longer exists → list as skipped.
16. (default) README gains a `/restore-sessions` line in the skills list.

## Constraints
- Bash scripts and a SKILL.md, matching `skills/run-agent/` (SKILL.md + `scripts/*.sh`). No new runtimes.
- Runs on this WSL2 Ubuntu box with tmux, Windows Terminal (`wt.exe`), `terminal-pet`, `~/.claude/local-tools/win.sh` and `screen-capture.sh`.
- Do not commit `~/.claude/projects` data except the trimmed fixture copies under `evals/` (`.gitignore` has `*.jsonl`; add `!skills/restore-sessions/evals/**/*.jsonl`).

## Acceptance criteria
- [ ] R1: `grep` shows `disable-model-invocation: true` in SKILL.md and `"restore-sessions": "user-invocable-only"` in settings.json; `/restore-sessions` appears in the slash menu.
- [ ] R2: with `journalctl --list-boots` as today, the skill prints "stop at Thu 2026-10-15 04:56:11 EDT".
- [ ] R3, R14: `bash setup.sh && bash find-sessions.sh '2026-10-15 04:56:11' evals/shutdown-2026-10-15` prints exactly the three ids in `expected.txt`.
- [ ] R4: the fixture line for a session whose last entry is a tool_result shows `yes` in the mid-task column.
- [ ] R5: with a `claude --resume <id>` already running in a pane, that id appears under "already running" and no second resume is sent; `tmux list-panes -a` before and after shows every pre-existing pane still present.
- [ ] R6, R8: after a run, `tmux list-panes -t 0 -F '#{pane_index} #{pane_current_command}'` shows pane 1 running terminal-pet and panes 2–4 running claude; two windows show two different pets.
- [ ] R7: the AskUserQuestion table appears before any `send-keys`; answering `drop <id>` removes that row.
- [ ] R9: `tmux capture-pane` of a resumed pane shows the `cd '<cwd>' && claude --resume <id>` line and no other input.
- [ ] R10: a missing tmux session results in a new Windows Terminal window attached to it; it is frontmost or the report says "in the taskbar".
- [ ] R11: the report cites capture-pane output per pane and the screenshot path.
- [ ] R12: the report contains the window x pane table and the three lists.
- [ ] R13: `grep -n kill` in the skill dir finds no `kill-server|kill-session|kill-pane|kill-window`; test runs use `tmux -L`.
