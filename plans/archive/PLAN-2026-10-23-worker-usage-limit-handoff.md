# Spec: worker hands off at the usage limit — handoff note, commit, and a scheduled relaunch after the window resets

## Ask
"During the Claude wrap up that comes after we've hit the usage limit, I want to see if we can get the model to write a quick handoff note and then activate / run-agent worker for after the window ends. Investigate if this is possible and augment your investigation with online research" (2026-10-23).
Answers, verbatim:
- Where the instruction lives: "Only the worker"
- Note: "Section in plans/WORKER_NOTES.md"
- Relaunch: "Same agent, fresh session, same flags" (`run-agent.sh worker "<same prompt>" --at <reset> --window -- <same --model/--effort>`; `autoContinueAtUsageLimit: false` so the old session does not also wake up)
- Right result: "Paste the limit message as a prompt" (test with `in 2m`)
- Order inside the allowance: "Schedule first, then note, then commit"
- Flags: "Worker types them from memory"
- Fallbacks (no tmux / no reset time): "Note + commit, say it could not schedule"
- Cap on the wait: "No cap"

## What to build
Add an "At the usage limit" section to `agents/worker.md` and turn `autoContinueAtUsageLimit` off in `settings.json`. When the worker sees Claude Code's injected limit message, it stops building and, in this order: schedules its own relaunch through the existing `/run-agent` script (`after window`, same prompt, same `--model`/`--effort`, forced, no `until` cap), appends a "Stopped at usage limit" section to `plans/WORKER_NOTES.md`, commits whatever is on disk, and ends with a short message saying the limit was hit, what is done, what is left, and when the relaunch fires (or why it could not be scheduled). The relaunched worker reads that section before touching the plan. Nothing else in the repo changes; the scheduling mechanics already exist in `skills/run-agent/`.

## Facts
- Verified in a local transcript (`~/.claude/projects/-home-jaxon-files-terminal-pet/0f802e8d-...jsonl`, 2026-10-11 10:08 PM ET, Claude Code 2.1.296): at the limit Claude Code injects a user-role message (`isMeta: true`) the model sees, verbatim: "[Usage limit reached; a short grace allowance remains, then this turn is cut off without warning. Judge what's left: if it's genuinely only a few steps, finish it properly, then stop and say so without extra polishing. Otherwise don't attempt it all: finish the piece in hand and at most two more like it, then stop. The allowance also pays for any subagents you have running: they don't get this message and will keep going, so it's up to you how to handle them. Either way, end by telling the user their usage limit was reached, what's done and what's left.]". After it the worker ran Bash (sed, cargo fmt, git commit, appended WORKER_NOTES.md) and wrote a final message; the turn then ended normally (`turn_duration` system entry). So tool calls work during the allowance and the model does not need a new mechanism, only an instruction.
- Hooks reference (code.claude.com/docs/en/hooks, fetched 2026-10-23): no hook fires for the limit itself. `Notification` has `quota_auto_resume_fired|stale|disabled`; `StopFailure` has `rate_limit` (API errors, not the plan limit); `SessionEnd` reasons are `clear, resume, logout, prompt_input_exit, other`. A GitHub report (anthropics/claude-code#13354) says a hard limit ends the session without a Stop hook. Hooks are therefore not the path.
- Wrap-up allowance (wmedia.es guide, Anthropic announcement 2026-09-25, unverified against official docs): Claude Code ≥ 2.1.277 shows "Usage limit reached · wrapping up"; Pro gets it once per week, Max every time; it draws a small fixed amount from the weekly limit and "may not be enough to finish the task"; it covers only the response in progress. Installed version: 2.1.310.
- Auto-continue (third-party reports, unverified): on by default since ~2.1.234 for claude.ai logins, setting `autoContinueAtUsageLimit`; resumes the same session at reset unless the machine slept; not started if the reset is >24 h away. `settings.json` here does not set it. If left on, the old session and the scheduled fresh one would both run at reset.
- `skills/run-agent/scripts/run-agent.sh` already supports `--at <epoch> --window [--until <epoch>] -- <claude flags>`; `S --parse 'worker "." after window --model fable --effort low'` returns `run` (the exact `S ...` call), `at`, `reset_shown`, `at_error`. The runner (`runner.sh`) is detached, writes `~/.claude/run-agent/jobs/<id>.json`, and at fire time respawns the original tmux pane (pane gone -> new window; server gone -> new session). The reset time comes from `GET https://api.anthropic.com/api/oauth/usage` with the OAuth token in `~/.claude/.credentials.json`; a stale token yields `at_error`. `S --jobs` / `S --cancel` list and drop runs. `test.sh` has 129 passing cases with a fake `claude` and `RUN_AGENT_USAGE_FILE`.
- The worker's current final-message rules (`agents/worker.md` ~lines 95-110) treat "out of time" as not a final message and require building the next thing; the new section must be an explicit exception.

## Requirements
1. (user) `agents/worker.md` gets a section "At the usage limit" that applies when a user-role message beginning `[Usage limit reached;` arrives (match on that prefix; the wording after it may change). From that message on, the worker builds nothing new and runs the steps in R2-R5 in that order; this is the one case where "stopped partway" is a valid final message and the evaluator handoff line is not required.
2. (user) Step 1, schedule: one Bash call to `~/.claude/skills/run-agent/scripts/run-agent.sh` that schedules `claude --agent worker "<the prompt this worker was launched with, default ".">"` in the current directory for when the 5-hour window resets (`after window` / `--window` path; no `until`), passing the same `--model` and `--effort` the worker was launched with as it remembers them (unknown -> omitted), forced (no confirmation question). It never asks the user anything in this flow. (default) The worker does this through `S --parse '<args>'` then the returned `run` command, or an equivalent direct `S worker "<prompt>" --at <epoch> --window -- <flags>` call; either way one or two Bash calls, no reading of the parse table beyond `run`, `at_shown`, `at_error`.
3. (user) Step 2, note: append to `plans/WORKER_NOTES.md` a section `## Stopped at usage limit — <date> <h:mm AM/PM> ET` with four labelled lines or short lists: Done (criteria met this session), In progress (file(s) and what is half-finished), Next (the first thing the relaunched worker should do), Uncommitted/dirty (files `git status` shows, or "none"); plus `Relaunch: <at_shown>` or `Relaunch: not scheduled — <reason>`. Times in ET.
4. (default) Step 3, commit: `git add -A` of the project files the worker changed (never `plans/`, which is gitignored anyway) and one commit `WIP: stopped at usage limit — <one line of what is in progress>` with the usual attribution lines; skipped with a note if there is nothing to commit or the repo has no git.
5. (user) Step 4, final message (≤ 6 lines): the limit was reached; what is done; what is left; `Relaunch at <time> ET (job #<id>)`, or the fallback line in R6. No further building, no "finish the piece in hand" unless R2-R4 are already done and the step is one command.
6. (user) Fallbacks: if `S` reports `at_error` (no reset time / stale token), or `$TMUX` is unset, or the script exits non-zero, the worker still does R3-R5 and its note and final message say `not scheduled — <the script's line or "not in tmux">` and `run /run-agent worker after window to schedule it by hand`. It does not retry, sleep, or invent a time.
7. (user) `settings.json` sets `"autoContinueAtUsageLimit": false` so the ended session does not also resume at reset. The CHANGELOG/README line for this change names that trade-off in one sentence.
8. (default) Relaunch pickup: a new "Start" line in worker.md: if `plans/WORKER_NOTES.md` ends with a `## Stopped at usage limit` section, read it first and begin with its Next line; the section stays in the file (history), it is not deleted.
9. (default) Subagents: the section tells the worker not to start subagents after the message and to let running ones finish unattended (they do not see the message); their output is noted under In progress if relevant.
10. (default) Nothing in planner.md, evaluator.md, helper.md or report-writer.md changes. The `run-agent` script and SKILL.md change only if R2's path needs a flag it lacks (for example `--force` on the direct path); `test.sh` keeps passing.
11. (default) Documentation: one entry in `CHANGELOG.md`, one line in `agents/README.md` under the worker, one sentence in `wiki`/`docs` where the worker is described, each stating: at the usage limit the worker schedules its own relaunch via `/run-agent`, writes a handoff section, commits, and stops.

## Constraints
- Stack is what the repo uses: Markdown agent files, bash + Python 3 scripts under `skills/run-agent/scripts/`, `settings.json`. No new dependencies, no new agents, no hooks (none fire for this event).
- `plans/` stays gitignored; the note lives there and is never committed.
- Section in worker.md ≤ 25 lines; the rest of worker.md's rules stay as they are.
- All times shown to the user in ET.

## Acceptance criteria
- [ ] R1: `grep -n "At the usage limit" agents/worker.md` finds the section; it names the `[Usage limit reached;` prefix and the order schedule → note → commit → message.
- [ ] R2, R5: in a tmux pane, `claude --agent worker "." --model haiku --effort low` on a scratch repo with a small PLAN.md; mid-task paste the verbatim limit message from Facts as a prompt. Transcript shows one or two `run-agent.sh` Bash calls and `S --jobs` then lists `#<id> claude --agent worker "." --model haiku --effort low at <time> ET (after window ...)`. Final message ≤ 6 lines with the four items in R5.
- [ ] R2 (timing test): same, but with `RUN_AGENT_USAGE_FILE` pointing at a JSON whose `five_hour.resets_at` is 2 minutes ahead; the pane respawns into a new worker session within 2-3 minutes, and `S --jobs` is then empty.
- [ ] R3: `tail -20 plans/WORKER_NOTES.md` in the scratch repo shows the `## Stopped at usage limit — ... ET` section with Done / In progress / Next / Uncommitted and a `Relaunch:` line.
- [ ] R4: `git log -1 --format=%s` in the scratch repo starts with `WIP: stopped at usage limit`; `git status --porcelain` shows no project files pending.
- [ ] R6: repeat the paste outside tmux (`TMUX= claude --agent worker ...`) and once with `RUN_AGENT_USAGE_FILE` pointing at `{}`; both runs still write the note and commit, and the note and final message say `not scheduled — ...` with the `/run-agent worker after window` hint; `S --jobs` is empty.
- [ ] R7: `jq .autoContinueAtUsageLimit settings.json` prints `false`; CHANGELOG mentions why.
- [ ] R8: start `claude --agent worker "."` in the scratch repo after the R3 run; its first tool call reads WORKER_NOTES.md and its first build step matches the Next line.
- [ ] R9: the worker.md section contains the subagent rule.
- [ ] R10: `git diff --stat` shows no changes to planner.md, evaluator.md, helper.md, report-writer.md; `bash skills/run-agent/scripts/test.sh` ends `... passed, 0 failed`.
- [ ] R11: `grep -n -i "usage limit" CHANGELOG.md agents/README.md wiki/*.md docs/*.md` finds the new lines.

## Amendments
- 2026-10-23 "Yes, but it's too long-winded. It could be tighter and achieve the same result"
  - [ ] (user) The "At the usage limit" section in `agents/worker.md` is clearly shorter and tighter than the 24-line version, with the same steps (schedule → note → commit → message), fallbacks, subagent rule and relaunch pickup still in it; the live R2/R3/R4/R6 checks still pass with it.
    Replaces: R1/Constraints "Section in worker.md ≤ 25 lines" as the only length limit
