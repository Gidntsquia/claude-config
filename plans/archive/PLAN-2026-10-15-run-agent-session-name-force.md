# Spec: /run-agent names the new claude session and takes a fuzzy "force" word that skips the Run? confirmation

## Ask
"I want to improve the / run-agent skill now. When we start a new agent, the resulting claude terminal should be named appropriately. For example, this session could be called "claude-config planner". Further, I want to add a "force" option to the run agent that skips the confirmation of "is this correct" and just does it immediately. The option should also be fuzzy like everything else"

Answers (round 1): name target = "Not related to tmux; it should be the project folder name then the agent name (i.e. "claude-config planner")"; name format = "Option 2, but with the (...) for the model if its given as in option 3"; force words = "`--force` / `-f` / `force`", "`now` / `go`", "`just do it` / `no confirm` / `yolo-run`", "Trailing `!` (`/run-agent worker!`)"; how to tell it's right = "Status bar shows the new name after swap", "Force path asks nothing", "Non-force path unchanged".
Answers (round 2): name via = "Yes, pass `--name`"; name order = "`planner: claude-config (opus)`"; folder = "Git repo root folder name"; force with missing agent/prompt = "Stop with a message".

## What to build
Extend `skills/run-agent/` (SKILL.md and scripts/run-agent.sh): the script adds `--name "<agent>: <repo folder> (<model>)"` to the claude command it respawns the pane with, unless the caller already passed `--name`/`-n`; the skill gains a fuzzy force option (flags, plain words, phrases, trailing `!`) that is parsed like the existing fuzzy words, removed from the arguments, never forwarded to claude, and skips step 5's Run? confirmation. With force, any missing agent or prompt stops with a message instead of asking. Everything else about the skill stays as it is today.

## Facts
- Verified (`claude --help`, 2026-10-14): `-n, --name <name>` "Set a display name for this session (shown in the prompt box, /resume picker, and terminal title)".
- Verified: this session's tmux pane title is `✳ worker` (set by claude's own title updates); tmux `set-titles` is off; the window is named `claude` by the `.tmux.conf` `C` binding. The user does not want tmux renamed.
- Verified: run-agent.sh currently builds `cmd=(claude --agent "$agent" "$prompt" "${flags[@]}")` and respawns the pane; `git rev-parse --show-toplevel` gives the repo root; `$PWD` is used for the respawn directory.
- Existing fuzzy words in SKILL.md step 1: `using|with|on <model>`, `permissions skipped|skip permissions|yolo`, `resume|continue`.

## Requirements
1. (user) Session name: run-agent.sh appends `--name "<name>"` to the claude command, where `<name>` is `<agent>: <folder>` and, when a `--model <m>` flag is present among the forwarded flags, `<agent>: <folder> (<m>)`. Example for this session: `planner: claude-config`; with `--model opus`: `planner: claude-config (opus)`.
2. (user) `<folder>` is the basename of `git rev-parse --show-toplevel` run in the pane's directory; when that fails (not a git repo), the basename of `$PWD`.
3. (default) If the forwarded flags already contain `--name` or `-n`, the script adds nothing and the user's name is used unchanged.
4. (user) The `running:` line, the "not inside tmux; run:" output and the Run? confirmation text all show the full command including the `--name "..."` part, so the user sees the name before it runs.
5. (user) Force words, parsed in SKILL.md step 1 anywhere in `$ARGUMENTS`, case-insensitive: `--force`, `-f`, `force`, `now`, `go`, `just do it`, `no confirm`, `yolo-run`, and a trailing `!` stuck to the agent name (`worker!`) or standing at the end of the arguments (`worker "." !`). `yolo` alone still means `--dangerously-skip-permissions`; `yolo-run` means force only. A force word is removed from the arguments, is never treated as the agent, prompt or a claude flag, and never appears in the command that runs.
6. (user) A force word inside the quoted prompt is part of the prompt, not a force word (`/run-agent worker "go now"` still confirms).
7. (user) With a force word present and the agent valid and the prompt known (given, or the `.` default for worker/evaluator/helper), the skill skips step 5 entirely and runs step 6 at once. The only output before the swap is the script's `running:` line. No AskUserQuestion is shown on this path.
8. (user) With a force word present and the agent missing, the skill replies `usage: /run-agent <agent> ["prompt"] [claude flags...]` and stops; with the agent present but no prompt for planner or a built-in, it replies `<agent> needs a prompt` and stops. Nothing runs, the current session stays alive. Unknown agent keeps today's `unknown agent: X` + list reply.
9. (user) Without a force word, every path behaves exactly as today: the same Run? confirmation (now also showing `--name`), the same "Which agent?" and "What should <agent> work on?" questions, the same stops.
10. (default) The confirmation and the `running:` line keep showing the mapping of fuzzy words to flags; a force word is reported in the confirmation only when there is one to show, i.e. never (force has no confirmation).
11. (user) SKILL.md documents the force words in step 1 (same style as the existing fuzzy word mapping), the force behavior in steps 3–5, and the `--name` rule in step 6; the `argument-hint` gains `[force]`. The script's header comment and `--help` usage mention `--name`. README lines that describe `/run-agent` mention the force option in one clause.
12. (default) The name is passed as one argument (no shell re-evaluation of spaces or parentheses), consistent with how the prompt is passed today.

## Constraints
- Stack as in the repo: bash script (`set -euo pipefail`), SKILL.md prose; no new dependencies. Only `skills/run-agent/SKILL.md`, `skills/run-agent/scripts/run-agent.sh` and the `/run-agent` lines of `README.md` change.
- Do not rename tmux windows, sessions or panes; do not change the respawn mechanism, the `--list` output, the exit codes (0 swapped, 1 not in tmux, 2 bad input) or the existing fuzzy mappings.
- The skill stays `user-invocable-only` in settings.json (already set).

## Acceptance criteria
- [ ] R1–R2, R4: with `TMUX` unset in `~/files/claude-config/skills`, `run-agent.sh planner "x" -- --model opus` exits 1 and prints `claude --agent planner "x" --model opus --name "planner: claude-config (opus)"`; in a non-git temp dir `run-agent.sh worker` prints `... --name "worker: <tmpdirname>"`.
- [ ] R3: `run-agent.sh worker -- --name mine` prints exactly one `--name`, value `mine`.
- [ ] R1, R12: inside tmux, `/run-agent planner "x"` → Yes → the new claude's prompt box / terminal title shows `planner: claude-config`; the pane title read with `tmux display -p '#{pane_title}'` contains it.
- [ ] R5, R7: `/run-agent worker force`, `/run-agent -f worker "."`, `/run-agent worker now`, `/run-agent worker!`, `/run-agent worker "." no confirm` each swap the pane with no AskUserQuestion; the running command contains no force word.
- [ ] R5: `/run-agent worker yolo force` runs with `--dangerously-skip-permissions`; `/run-agent worker yolo-run` runs without it and without confirmation.
- [ ] R6: `/run-agent worker "go now"` shows the Run? confirmation with prompt `go now`.
- [ ] R8: `/run-agent force` replies the usage line only; `/run-agent planner force` replies `planner needs a prompt`; nothing runs.
- [ ] R9: `/run-agent worker "."` still shows the Run? confirmation, now ending in `--name "worker: claude-config"`; "No" → `nothing changed`.
- [ ] R11: SKILL.md diff shows force words, force behavior, `--name` rule, updated `argument-hint`; README `/run-agent` lines mention force; `run-agent.sh --help` mentions `--name`.

## Amendments
- 2026-10-15 "Worked, but the bypass permissions thing came up with a warning prompt, which made the worker not immediately start"
  - [x] (user) `/run-agent worker yolo force` swaps the pane and the new worker starts working at once: no bypass-permissions warning prompt (or any other prompt) waits for input first.
