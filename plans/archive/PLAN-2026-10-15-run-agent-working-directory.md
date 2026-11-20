# Spec: /run-agent takes a working directory (`in <dir>`, `--cwd`, bare path), creating it on Yes, and starts the new agent there

## Ask
"I want the run-agent skill to also have an option where I can change the working directory for the project, i.e. let's say I want to run a planner in the ai-sandbox folder, or perhaps in a new folder called ~/files/curling_simulator"

Round 1: syntax = "`in <dir>` plain word", "`--cwd <dir>` / `-C <dir>` flag", "Bare path token"; missing dir = "Create it, say so in Run?"; path forms = "`~`, absolute, relative to current cwd", "Bare name = sibling of current repo", "Spaces via quotes"; right result = "Session name uses the new folder", "Pane prompt and claude cwd are the new dir", "Not-in-tmux fallback includes cd", "Distrust: anything created on No".
Round 2: name folder when a dir is given = "Always the target dir basename"; bare name not found = "Refuse bare names that don't exist"; resume + dir = "Warn in Run?"; docs/tests = "SKILL.md + script --help + README clause", "Script self-test file", "Wiki page update".

## What to build
Extend `skills/run-agent/` (SKILL.md and scripts/run-agent.sh) so a run can name a directory: `in <dir>` as a plain word, `--cwd <dir>` / `-C <dir>` as a flag, or a bare path token (contains `/` or starts with `~`). The skill resolves the path (tilde, absolute, relative to the pane's cwd, bare name as a sibling of the current git root), shows the resolved absolute path in the Run? text with "will be created" when it does not exist, creates it only after Yes (or at once with a force word), and the script respawns the pane in that directory with the session named after the target folder. Outside tmux the printed fallback command starts with `cd '<dir>' &&`. Behaviour without a directory stays exactly as today.

## Facts
- Verified (run-agent.sh today): the respawn uses `tmux respawn-pane -k -t "$TMUX_PANE" -c "$PWD" ...`; the name folder is `basename "$(git rev-parse --show-toplevel || echo "$PWD")"`; exit codes 0 swapped / 1 not in tmux / 2 bad input; `--list` prints custom agents then built-ins.
- Verified: SKILL.md step 1 already maps plain words (`using|with|on <model>`, `yolo`, `resume|continue`) and force words; the existing "any other unquoted non-flag word -> usage" rule must now exempt `in <dir>` and bare path tokens.
- Verified: no page under `wiki/` mentions run-agent; `README.md` lines 29–31 describe `/run-agent`.
- `claude --continue` picks the most recent conversation of the directory it starts in (claude --help: "Continue the most recent conversation in the current directory"); unverified this session, taken from the previous plan's help check.

## Requirements
1. (user) Directory syntax, parsed in SKILL.md step 1 anywhere outside the quoted prompt: `in <dir>` (the next token is the path), `--cwd <dir>`, `-C <dir>`, or a bare non-flag token that contains `/` or starts with `~` (`/run-agent planner ~/files/curling_simulator "..."`). All three mean the same thing; `--cwd`/`-C` are stripped and never forwarded to claude. A second quoted string right after `in`, `--cwd` or `-C` is a path with spaces, not the prompt (`in "~/files/my project"`). Two directory tokens -> reply `usage: /run-agent <agent> ["prompt"] [in <dir>] [claude flags...]` and stop.
2. (user) Resolution, in order: `~`/`~/x` -> `$HOME`; absolute path as is; a token containing `/` -> relative to the pane's current directory; a bare name (no `/`, no `~`) -> `<cwd>/<name>` if that directory exists, else `<current git root's parent>/<name>` if that exists (sibling of the current repo; outside a repo, the cwd's parent). The result is shown and used as an absolute path with `..` and symlinks left as given but `.`/`..` segments collapsed.
3. (user) A bare name that exists in neither place -> reply `no such directory: <name> (looked in <cwd>, <sibling dir>)` and stop; nothing runs, nothing is created. Creating needs a `~`, `/` or absolute path.
4. (user) A path with `~`, `/` or absolute that does not exist is allowed: the Run? text shows `(in /home/jaxon/files/curling_simulator, will be created)`. `mkdir -p` runs only after "Yes, replace this session"; with a force word it runs at once with no question. If the path exists but is a file, reply `not a directory: <path>` and stop.
5. (user) Answering No leaves no new folder behind and the current session untouched; reply `nothing changed`.
6. (user) Run? text (step 5) becomes `Replace this session with: claude --agent <agent> "<prompt>" <flags> --name "<agent>: <folder>[ (<model>)]"  (in <resolved dir>[, will be created])?`. With `--continue`/`resume` plus a directory different from the cwd, the text adds ` (note: --continue resumes the latest session in <dir>, not this one)`.
7. (user) Session name when a directory is given: `<agent>: <basename of the target dir>` (plus ` (<model>)` as today), e.g. `planner: curling_simulator`, `worker: experiments` for `in ~/files/ai-sandbox/experiments`. (default) Without a directory the name keeps today's rule (git root basename, else `$PWD` basename). `--name`/`-n` from the user still wins.
8. (user) The script takes the directory (`run-agent.sh <agent> [prompt] [--cwd <dir>] [-- flags...]`, or an equivalent single option) and runs `tmux respawn-pane ... -c "<dir>"` so the pane's shell and claude both start there: after the swap `tmux display -p '#{pane_current_path}'` is the target dir, claude's statusline shows it, and the shell left after claude exits is in it. The script does not itself `cd` the calling session.
9. (user) Outside tmux (exit 1) the printed command is `cd '<dir>' && claude --agent ...` when a directory was given; unchanged otherwise. The `running:` line shows the same `cd '<dir>' && ` prefix.
10. (default) The script exits 2 with `no such directory: <dir>` if the directory still does not exist when it runs (the skill creates it before calling; the script never creates directories).
11. (user) Everything with no directory given behaves exactly as today: same questions, texts, force handling, exit codes, `--list`.
12. (user) Docs: SKILL.md step 1 documents the three syntaxes and resolution rules, step 5 the new Run? text, step 6 the directory argument; `argument-hint` becomes `<agent> ["prompt"] [in <dir>] [claude flags...] [force]`. The script header and `--help` mention the directory option. README's `/run-agent` paragraph gains one clause (e.g. "`in <dir>` starts it in another folder, created if missing"). Wiki: no page mentions run-agent today; if `wiki/Cheat-Sheet.md` or `Workflow.md` lists skills, add the one-line example there, else skip and say so.
13. (user) `skills/run-agent/scripts/test.sh`: runs the script with `TMUX` unset from a temp git repo against (a) an existing dir, (b) a sibling-name dir, (c) a missing dir -> exit 2, (d) no dir, (e) `--name` given, and checks the printed command (`cd '<dir>' && ...`, `--name "<agent>: <basename>"`) and exit codes; prints `N passed, M failed`, exit 1 on any failure.

## Constraints
- Stack as in the repo: bash (`set -euo pipefail`), SKILL.md prose; no new dependencies. Files that change: `skills/run-agent/SKILL.md`, `skills/run-agent/scripts/run-agent.sh`, new `skills/run-agent/scripts/test.sh`, the `/run-agent` lines of `README.md`, optionally one wiki page.
- Keep the respawn mechanism, `--list`, exit codes, force words and fuzzy mappings; never rename tmux objects; never `git init`.
- The skill stays `user-invocable-only` in settings.json.

## Acceptance criteria
- [ ] R1, R2, R7, R9: `TMUX= run-agent.sh planner "x" --cwd ~/files/ai-sandbox` (option name per the worker) prints `cd '/home/jaxon/files/ai-sandbox' && claude --agent planner "x" --name "planner: ai-sandbox"`, exit 1.
- [ ] R2: from `~/files/claude-config/skills`, `/run-agent worker in ai-sandbox` resolves to `/home/jaxon/files/ai-sandbox` in the Run? text.
- [ ] R3: `/run-agent worker in no-such-folder-xyz` replies `no such directory: ...` and `ls ~/files` shows no new folder.
- [ ] R4, R5: `/run-agent planner "curling sim" in ~/files/curling_simulator_test` -> Run? shows `will be created`; answer No -> folder absent; answer Yes -> folder exists and the new session's title is `planner: curling_simulator_test`.
- [ ] R6: `/run-agent worker resume in ~/files/ai-sandbox` -> Run? text contains the `--continue` note.
- [ ] R8: after a Yes swap, `tmux display -p '#{pane_current_path}'` on that pane prints the target dir.
- [ ] R10: `TMUX= run-agent.sh worker --cwd /nonexistent` exits 2 with `no such directory`.
- [ ] R11: `/run-agent worker` and `/run-agent planner "x" force` behave as before (Run? text unchanged apart from nothing; force asks nothing).
- [ ] R12: `grep -n "in <dir>" skills/run-agent/SKILL.md README.md` finds the hint and the README clause; `run-agent.sh --help` mentions the directory option.
- [ ] R13: `bash skills/run-agent/scripts/test.sh` prints `N passed, 0 failed`, exit 0.

## Amendments
- 2026-10-15 "Also, using run-agent on the planner without a prompt should simply start the planner with no starting prompt"
  - [ ] `/run-agent planner` (no prompt) asks Run? with `claude --agent planner --name "planner: <folder>"` (no prompt argument) and on Yes starts the planner with an empty input box; `TMUX= run-agent.sh planner` prints that command, exit 1. (user)
    Replaces: script exit 2 `planner needs a prompt` (test.sh case "d: planner without a prompt").
