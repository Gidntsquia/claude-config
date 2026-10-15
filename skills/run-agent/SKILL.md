---
name: run-agent
description: Replace the current claude session with a new one running a chosen agent (helper, planner, worker, evaluator or a built-in) in the same tmux pane and directory. User-invoked only.
argument-hint: <agent> ["prompt"] [claude flags...] [force]
---

# /run-agent — swap this session for `claude --agent <agent> "<prompt>"`

Script: `~/.claude/skills/run-agent/scripts/run-agent.sh` (call it `S`). Nothing runs until step 5 says yes,
unless a force word (step 1) was given: then step 5 is skipped and step 6 runs at once.

## 1. Parse `$ARGUMENTS`
- Any token starting with `--` is a claude flag; it takes the next token as its value when that token
  does not start with `--` and is not the agent or the quoted prompt (`--model opus`, `--dangerously-skip-permissions`).
  Flags may appear anywhere: before or after the agent and prompt.
- First non-flag token = agent. A quoted string (`"..."` or `'...'`) = prompt, taken verbatim without the quotes.
- Plain words that describe flags are mapped to them: `using|with|on <model>` -> `--model <model>`
  (opus, sonnet, haiku, fable); `permissions skipped|skip permissions|yolo` -> `--dangerously-skip-permissions`;
  `resume|continue` -> `--continue`. Keep the mapping in the confirmation so the user sees what was understood.
- Force words (case-insensitive, anywhere outside the quoted prompt): `--force`, `-f`, `force`, `now`, `go`,
  `just do it`, `no confirm`, `yolo-run`, and a trailing `!` stuck to the agent name (`worker!`) or standing
  alone at the end (`worker "." !`) -> force = skip the Run? confirmation (step 5). `yolo` alone still means
  `--dangerously-skip-permissions`; `yolo-run` means force only. Remove force words from the arguments: they are
  never the agent, the prompt or a claude flag, and never appear in the command that runs. A force word inside
  the quoted prompt is part of the prompt (`/run-agent worker "go now"` still confirms).
- Any other unquoted non-flag word after the agent (e.g. `/run-agent worker . extra words`) -> reply with
  `usage: /run-agent <agent> ["prompt"] [claude flags...]` and stop. Do nothing else.

## 2. Validate
Run `S --list` (Bash). If the agent is not in that output, reply `unknown agent: X` plus the list and stop.

## 3. No agent given
With force: reply `usage: /run-agent <agent> ["prompt"] [claude flags...]` and stop; ask nothing.
Otherwise AskUserQuestion: "Which agent?" with options from `S --list` in that order (custom agents first, then built-ins;
up to 4 options per question, so put helper/planner/worker/evaluator first and name the built-ins in the
question text for "Other"). Then continue with step 4.

## 4. Prompt
- Default `"."` for `worker`, `evaluator`, `helper` when no prompt was given.
- `planner` and every built-in have no default: if no prompt, with force reply `<agent> needs a prompt` and stop
  (nothing runs, this session stays alive); otherwise AskUserQuestion "What should <agent> work on?"
  with one option "Type it under Other" (free text via Other). Empty or no answer -> reply
  `<agent> needs a prompt` and stop; the current session stays alive.

## 5. Confirm (every path without a force word)
With a force word: skip this step entirely, print nothing, go to step 6 (the script's `running:` line is the
only output before the swap). Otherwise AskUserQuestion, header "Run?", question text exactly:
`Replace this session with: claude --agent <agent> "<prompt>" <flags> --name "<agent>: <folder>[ (<model>)]"  (in <cwd>)?`
where `<folder>` is the basename of `git rev-parse --show-toplevel` (or of the cwd outside a git repo) and the
`(<model>)` part appears only when a `--model` flag is present; leave the `--name` part out when the user passed
`--name`/`-n` themselves. Options: "Yes, replace this session" / "No". "No" -> reply `nothing changed` and stop.

## 6. Run
Bash, with the prompt as one single-quoted argument (escape `'` as `'\''`) and flags after `--`:
`S <agent> '<prompt>' -- <flags...>` (omit `--` when there are no flags). Force words are never passed.
The script itself appends `--name "<agent>: <folder>"` (with ` (<model>)` when `--model` is given) as one
argument unless the flags already contain `--name`/`-n`; the `running:` line shows it.
Exit 0 means the pane was respawned; this session is ending. Exit 1 means not inside tmux: relay its
output (`not inside tmux; run: claude --agent ...`) so the user can run it by hand. Exit 2: relay the message.
