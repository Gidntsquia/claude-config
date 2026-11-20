# Spec: /run-agent skill — replace the current claude session with a new one running a chosen agent

## Ask
"I want to create a new user-only skill called "/run-agent" that will run a script that exits out of the current terminal and in it's place starts a new claude session with the given agent (currently, that's only helper, planner, worker, evaluator, and all the built-in claude agents). Further, it will start the agent with the given prompt, or "." by default for the worker, evluator, and helper. For the planner, there should be no default since "." doesn't really make sense for that particular agent."

Answers:
- Mechanism: "tmux respawn-pane" — the script finds the pane it runs in and runs `tmux respawn-pane -k` with the new `claude --agent ...` command; outside tmux it prints the command and tells you to run it.
- Arguments: "Agent + prompt as quoted second arg" — `/run-agent planner "I want a todo app"`; unquoted extra words are an error.
- Agent list: "Scan agent dirs + hardcoded built-ins" — every *.md in ~/.claude/agents and ./.claude/agents plus a fixed list of built-in subagent names; unknown name -> error listing valid names, nothing killed.
- Right result: "Same pane shows the new agent's first turn", "Planner refusal is the key test", "Also preserves the model/flags".
- Flags: "Option 2 by default, but leave the door open for option 3 if the user gives that command or describes it in plain words. Also it should be order agnostic" (option 2 = plain `claude --agent X "prompt"` in the same directory, flags from settings; option 3 = extra flags passed through the skill, e.g. `/run-agent worker "." --model opus`, appended as-is).
- No agent given: "Menu of agents, then prompt".
- Confirm: "Always confirm" — one yes/no question showing the full command every time.
- Location: "skills/run-agent/ in this repo" — SKILL.md + scripts/run-agent.sh; install.sh already symlinks skills/*; settings.json gets `"run-agent": "user-invocable-only"`.

## What to build
A user-invocable skill `/run-agent` in this repo (`skills/run-agent/SKILL.md`) and a bash script (`skills/run-agent/scripts/run-agent.sh`). The skill resolves the agent name, the prompt and any extra claude flags from `$ARGUMENTS` (or from menu questions when the agent is missing), validates the agent, asks one yes/no confirmation showing the exact command, then runs the script. The script, when run inside tmux, respawns the current pane with a fresh `claude --agent <agent> "<prompt>" [flags]` in the same working directory, which ends the current session; outside tmux it prints the command and exits.

## Facts
- `claude --help` (verified 2026-10-14): `--agent <agent>` sets the agent for the session. `claude agents --json` lists *running sessions*, not agent definitions, so it cannot be used for validation.
- `man tmux` (verified): `respawn-pane [-k] [-c start-directory] [-t target-pane] [shell-command [argument ...]]`; `-k` kills the pane's current command first. `$TMUX_PANE` identifies the pane the script runs in. A command given directly runs without a shell, so the pane closes when it exits unless wrapped in a shell.
- Custom agents here: `~/.claude/agents/{helper,planner,worker,evaluator}.md` (symlinked from `agents/` in this repo). `install.sh` symlinks `skills/*` into `~/.claude/skills`.
- Built-in subagent names (unverified against `--agent`): `general-purpose`, `Explore`, `Plan`, `Bash`, `statusline-setup`, `claude-code-guide`. The worker should check which ones `claude --agent <name>` accepts and keep only those in the hardcoded list, noting the result in WORKER_NOTES.md.
- settings.json `skillOverrides` already uses `"user-invocable-only"` for `review-skill`.

## Requirements
1. (user) Skill `/run-agent` exists at `skills/run-agent/SKILL.md` with frontmatter `name: run-agent`, an `argument-hint` like `<agent> ["prompt"] [claude flags...]`, and `settings.json` has `"run-agent": "user-invocable-only"` under `skillOverrides` so it never auto-triggers.
2. (user) Argument form: `/run-agent <agent> "<prompt>"`. The prompt is the quoted second argument. Extra claude flags (e.g. `--model opus`, `--dangerously-skip-permissions`) may appear anywhere in `$ARGUMENTS` before or after the agent/prompt (order agnostic): any token beginning with `--` (with its value if the flag takes one) is a flag, the first non-flag token is the agent, the quoted non-flag string is the prompt. Unquoted extra non-flag words after the prompt are an error: the skill replies with usage and does nothing.
3. (user) Flags may also be described in plain words in the arguments (e.g. `/run-agent worker "." using opus with permissions skipped`); the skill maps that to the matching claude flags and shows them in the confirmation so the user sees exactly what it understood.
4. (user) Default prompt: `worker`, `evaluator`, `helper` get `"."` when no prompt is given. `planner` has no default: `/run-agent planner` with no prompt asks for the prompt via AskUserQuestion (free text through "Other"); if still empty, the skill stops with "planner needs a prompt" and the current session stays alive. Built-in agents have no default and are handled like planner.
5. (user) No agent given: the skill asks which agent via an AskUserQuestion menu built from the valid list (custom agents first, then built-ins), then asks for the prompt only when that agent has no default.
6. (user) Valid agents = basenames of `*.md` in `~/.claude/agents/` and `./.claude/agents/` (project, relative to cwd) plus the hardcoded built-in list from Facts. The script validates with the same rule (`run-agent.sh --list` prints the valid names one per line). An unknown name exits 2 with `unknown agent: X` and the valid list; nothing is killed.
7. (user) Always confirm: before running the script the skill asks one yes/no AskUserQuestion whose text contains the full command, e.g. `claude --agent worker "." --model opus` and the directory it will run in. "No" ends the skill with nothing changed.
8. (user) Mechanism: inside tmux (`$TMUX` and `$TMUX_PANE` set) the script runs `tmux respawn-pane -k -t "$TMUX_PANE" -c "$PWD" <shell wrapper>` so the current claude session ends and the new one starts in the same pane and the same directory. The wrapper keeps an interactive shell in the pane after the new claude exits (the pane does not close).
9. (default) Outside tmux the script prints `not inside tmux; run:` followed by the exact command and exits 1. Nothing is killed.
10. (default) The script prints the exact command once (`running: claude --agent ...`) just before respawning, so it appears in the pane scrollback.
11. (user, default form) The new command is plain `claude --agent <agent> "<prompt>"` plus only the flags from requirement 2/3; nothing is copied from the current session's command line. Model and permission mode otherwise come from settings.json and the agent file.
12. (default) Prompt text is passed as one argument verbatim (quotes, spaces, `$` preserved; no shell re-evaluation).
13. (default) Script usage: `run-agent.sh <agent> [prompt] [-- claude flags...]`, exit 2 on bad usage with a one-line usage message; `--help` prints it; `--list` per requirement 6.
14. (default) `SKILL.md` stays under 60 lines, tells Claude the exact steps (parse, validate via `--list`, ask, confirm, run), and never runs the script without the confirmation in requirement 7.
15. (default) README.md gets a two-line mention of `/run-agent` next to the agent commands in the workflow section.

## Constraints
- Bash script (bash 5, tmux, no other dependencies); SKILL.md markdown; settings.json edit. No Python, no new tooling.
- Files only under `skills/run-agent/`, plus `settings.json`, `README.md`. Script is executable (`chmod +x`).
- Must not touch other panes or sessions; only `$TMUX_PANE`.

## Acceptance criteria
- [ ] R1: `ls skills/run-agent/SKILL.md skills/run-agent/scripts/run-agent.sh`; `grep '"run-agent": "user-invocable-only"' settings.json`; after `./install.sh`, `~/.claude/skills/run-agent` resolves.
- [ ] R6, R13: `skills/run-agent/scripts/run-agent.sh --list` prints helper, planner, worker, evaluator and the built-ins; `run-agent.sh nosuch` exits 2 with `unknown agent: nosuch` and the list; `run-agent.sh` with no args exits 2 with usage.
- [ ] R9: with `TMUX` and `TMUX_PANE` unset, `run-agent.sh worker` exits 1 and prints `not inside tmux; run:` and `claude --agent worker "."`.
- [ ] R8, R10, R11: in a tmux pane running claude, `/run-agent worker` -> confirm yes -> the same pane shows `running: claude --agent worker "."` then a fresh claude session as the worker in the same cwd; `claude agents --json` shows one session for that cwd. Quitting that claude leaves a shell prompt in the pane.
- [ ] R4: `/run-agent planner` asks for a prompt; answering nothing ends with "planner needs a prompt" and the original session is still alive. `/run-agent planner "I want a todo app"` -> confirmation shows that prompt.
- [ ] R2, R3: `/run-agent --model opus worker "."` and `/run-agent worker "." --model opus` both show `claude --agent worker "." --model opus` in the confirmation; `/run-agent worker "." using opus` shows the same. `/run-agent worker . extra words` gets the usage reply.
- [ ] R5: `/run-agent` alone shows the agent menu; picking worker goes straight to the confirmation; picking planner asks for the prompt first.
- [ ] R7: every path shows the yes/no confirmation with the full command and directory; answering No changes nothing (`claude agents --json` unchanged, pane unchanged).
- [ ] R12: `/run-agent worker "fix the $HOME bug"` -> the new session's first user message is literally `fix the $HOME bug`.
- [ ] R14, R15: `wc -l skills/run-agent/SKILL.md` < 60; `grep run-agent README.md` matches.
