---
name: run-agent
description: Replace the current claude session with a new one running a chosen agent (helper, planner, worker, evaluator or a built-in) in the same tmux pane and directory. User-invoked only.
argument-hint: <agent> ["prompt"] [claude flags...]
---

# /run-agent — swap this session for `claude --agent <agent> "<prompt>"`

Script: `~/.claude/skills/run-agent/scripts/run-agent.sh` (call it `S`). Nothing runs until step 5 says yes.

## 1. Parse `$ARGUMENTS`
- Any token starting with `--` is a claude flag; it takes the next token as its value when that token
  does not start with `--` and is not the agent or the quoted prompt (`--model opus`, `--dangerously-skip-permissions`).
  Flags may appear anywhere: before or after the agent and prompt.
- First non-flag token = agent. A quoted string (`"..."` or `'...'`) = prompt, taken verbatim without the quotes.
- Plain words that describe flags are mapped to them: `using|with|on <model>` -> `--model <model>`
  (opus, sonnet, haiku, fable); `permissions skipped|skip permissions|yolo` -> `--dangerously-skip-permissions`;
  `resume|continue` -> `--continue`. Keep the mapping in the confirmation so the user sees what was understood.
- Any other unquoted non-flag word after the agent (e.g. `/run-agent worker . extra words`) -> reply with
  `usage: /run-agent <agent> ["prompt"] [claude flags...]` and stop. Do nothing else.

## 2. Validate
Run `S --list` (Bash). If the agent is not in that output, reply `unknown agent: X` plus the list and stop.

## 3. No agent given
AskUserQuestion: "Which agent?" with options from `S --list` in that order (custom agents first, then built-ins;
up to 4 options per question, so put helper/planner/worker/evaluator first and name the built-ins in the
question text for "Other"). Then continue with step 4.

## 4. Prompt
- Default `"."` for `worker`, `evaluator`, `helper` when no prompt was given.
- `planner` and every built-in have no default: if no prompt, AskUserQuestion "What should <agent> work on?"
  with one option "Type it under Other" (free text via Other). Empty or no answer -> reply
  `<agent> needs a prompt` and stop; the current session stays alive.

## 5. Confirm (always, every path)
AskUserQuestion, header "Run?", question text exactly:
`Replace this session with: claude --agent <agent> "<prompt>" <flags>  (in <cwd>)?`
Options: "Yes, replace this session" / "No". "No" -> reply `nothing changed` and stop.

## 6. Run
Bash, with the prompt as one single-quoted argument (escape `'` as `'\''`) and flags after `--`:
`S <agent> '<prompt>' -- <flags...>` (omit `--` when there are no flags).
Exit 0 means the pane was respawned; this session is ending. Exit 1 means not inside tmux: relay its
output (`not inside tmux; run: claude --agent ...`) so the user can run it by hand. Exit 2: relay the message.
