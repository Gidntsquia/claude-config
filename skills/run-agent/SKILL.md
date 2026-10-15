---
name: run-agent
description: Replace the current claude session with a new one running a chosen agent (helper, planner, worker, evaluator or a built-in) in the same tmux pane, in this directory or another one (`in <dir>`, created if missing). User-invoked only.
argument-hint: <agent> ["prompt"] [in <dir>] [claude flags...] [force]
---

# /run-agent — swap this session for `claude --agent <agent> ["<prompt>"]`

Script: `~/.claude/skills/run-agent/scripts/run-agent.sh` (call it `S`). Nothing runs until step 5 says yes,
unless a force word (step 1) was given: then step 5 is skipped and step 6 runs at once.

## 1. Parse `$ARGUMENTS`
- Any token starting with `--` (except `--cwd`, see Directory below) is a claude flag; it takes the next token as its value when that token
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
- Directory (optional), anywhere outside the quoted prompt, three forms that mean the same thing:
  `in <dir>`, `--cwd <dir>` / `-C <dir>` (stripped, never passed to claude as flags), or a bare non-flag token
  that contains `/` or starts with `~` (`/run-agent planner ~/files/curling_simulator "..."`). The token right
  after `in`, `--cwd` or `-C` is always the path, even when quoted (`in "~/files/my project"` is a path with a
  space, not the prompt). A token taken as a claude flag's value (`--settings ./x.json`) is not a directory.
  Two directory tokens -> reply `usage: /run-agent <agent> ["prompt"] [in <dir>] [claude flags...]` and stop.
- Resolve the directory with Bash: `S --resolve '<dir>'` (single-quoted so `~` reaches the script; escape `'`
  as `'\''`). It prints `<absolute dir><TAB>exists|missing` and creates nothing. Its rules: `~`/`~/x` -> `$HOME`;
  absolute as is; a token with `/` -> relative to the current directory; a bare name (no `/`, no `~`) ->
  `<cwd>/<name>` if that exists, else `<parent of the current git root>/<name>` (outside a repo, the cwd's
  parent); `.`/`..` segments collapsed, symlinks left as given. Exit 2 -> relay its one line and stop, nothing
  runs and nothing is created: `no such directory: <name> (looked in <cwd>, <sibling dir>)` for a bare name
  found nowhere (creating a folder needs a `~`, `/` or absolute path), `not a directory: <path>` for a file.
  `missing` is allowed: the folder will be created in step 6, never earlier.
- Any other unquoted non-flag word after the agent (e.g. `/run-agent worker . extra words`) -> reply with
  `usage: /run-agent <agent> ["prompt"] [in <dir>] [claude flags...]` and stop. Do nothing else.

## 2. Validate
Run `S --list` (Bash). If the agent is not in that output, reply `unknown agent: X` plus the list and stop
(With a directory, an agent file in `<dir>/.claude/agents/` also counts.)

## 3. No agent given
With force: reply `usage: /run-agent <agent> ["prompt"] [in <dir>] [claude flags...]` and stop; ask nothing.
Otherwise AskUserQuestion: "Which agent?" with options from `S --list` in that order (custom agents first, then built-ins;
up to 4 options per question, so put helper/planner/worker/evaluator first and name the built-ins in the
question text for "Other"). Then continue with step 4.

## 4. Prompt
- Default `"."` for `worker`, `evaluator`, `helper` when no prompt was given.
- `planner` and every built-in have no default: with no prompt they start with no prompt argument (an empty
  input box). Do not ask for one; the command is `claude --agent <agent> <flags> --name ...` with no `"<prompt>"`.

## 5. Confirm (every path without a force word)
With a force word: skip this step entirely, print nothing, go to step 6 (the script's `running:` line is the
only output before the swap). Otherwise AskUserQuestion, header "Run?", question text exactly:
`Replace this session with: claude --agent <agent> "<prompt>" <flags> --name "<agent>: <folder>[ (<model>)]"  (in <dir>[, will be created])?`
- No prompt (planner, built-ins): leave the `"<prompt>"` part out: `claude --agent planner <flags> --name "planner: <folder>"`.
- No directory given: `<dir>` is the cwd, and `<folder>` is the basename of `git rev-parse --show-toplevel`
  (or of the cwd outside a git repo).
- Directory given: `<dir>` is the resolved absolute path from step 1, followed by `, will be created` when
  `--resolve` said `missing`; `<folder>` is that directory's basename (`planner: curling_simulator`).
- With `--continue` (or `resume`) and a directory different from the cwd, append
  ` (note: --continue resumes the latest session in <dir>, not this one)` after the closing `)`, before `?`,
  on the same line (one space before it, no line break): `...  (in <dir>) (note: ...)?`.
- The `(<model>)` part appears only when a `--model` flag is present; leave the `--name` part out when the user
  passed `--name`/`-n` themselves.
Options: "Yes, replace this session" / "No". "No" -> reply exactly `nothing changed` and stop; nothing was created.

## 6. Run
Bash, with the prompt as one single-quoted argument (escape `'` as `'\''`) and flags after `--`:
`S <agent> '<prompt>' -- <flags...>` (omit `--` when there are no flags; omit `'<prompt>'` when there is no prompt).
Force words are never passed.
With a directory: first, if `--resolve` said `missing`, run `mkdir -p '<dir>'` (only now, after Yes, or at once
with a force word); then call `S <agent> '<prompt>' --cwd '<absolute dir>' -- <flags...>`. The script respawns the
pane in that directory (shell and claude both start there) and exits 2 with `no such directory: <dir>` if it
does not exist; it never creates directories.
The script itself appends `--name "<agent>: <folder>"` (folder = the `--cwd` dir's basename when given) (with ` (<model>)` when `--model` is given) as one
argument unless the flags already contain `--name`/`-n`; the `running:` line shows it.
Exit 0 means the pane was respawned; this session is ending. Exit 1 means not inside tmux: relay its
output (`not inside tmux; run: claude --agent ...`, or `cd '<dir>' && claude --agent ...` with a directory) so the user can run it by hand. Exit 2: relay the message.
