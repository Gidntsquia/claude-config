---
name: restore-sessions
description: After WSL or Windows stopped (Windows Update restart, WSL update), reopen the Claude Code sessions the stop killed in tmux sessions 0 and 1 (2x2 tiled, pet in the top-left pane of every window), after showing the plan and asking yes/no. User-invoked only.
argument-hint: [stop time, e.g. "2026-10-15 04:56:11"]
disable-model-invocation: true
---

# /restore-sessions — reopen the sessions a WSL/Windows stop killed

Scripts live in `~/.claude/skills/restore-sessions/scripts/` (call that `S`). Work dir:
`D=~/.cache/restore-sessions/$(date +%Y%m%d-%H%M%S)` (make it with `mkdir -p`). Run each script with Bash and
show the user what it prints. Every clock time you write is US Eastern with its `EDT`/`EST` suffix.

Test hooks (only when the user's environment already has them set; never set them yourself):
`RS_TMUX_L=<name>` makes every script use the private tmux server `tmux -L <name>`;
`RS_PROJECTS=<dir>` replaces `~/.claude/projects` (and turns off the `~/.claude/sessions` check unless
`RS_SESSIONS=<dir>` is also set). The scripts read these themselves; pass nothing extra.

## Rules (all steps)
- Never end a tmux server, session, window or pane (no tmux kill command of any kind), never move an existing pane
  out of its window. Only new panes are split in.
- Never type into a resumed pane. The only keys sent to a Claude pane are `apply.sh`'s one line
  `cd '<cwd>' && claude --resume <id> --model <model>` + Enter (the transcript's model: without it a resumed
  session takes the saved default model, and one with an agent loses the agent's model). No `continue`, no `/model`, no answer to a trust dialog, no retries:
  problems are reported, the user fixes them.
- Nothing in tmux changes before the user says yes in step 4.

## 1. Stop time
- If `$ARGUMENTS` holds a time, run `"$S/stop-time.sh" "$ARGUMENTS"`: it prints `stop<TAB><time in ET>` (STOP).
  Also run `"$S/stop-time.sh"` with no argument and, if it works, keep its `boot` value as BOOT (not `prev`:
  that boot may not be the one the user means; leave `--prev` out).
- Else run `"$S/stop-time.sh"`. It prints `stop<TAB>…`, `boot<TAB>…`, `prev<TAB>…`. STOP = the `stop` value,
  BOOT = `boot`, PREV = `prev`.
- If it exits 1 (`no stop time: …`: journalctl missing, or boot -1 has no end time), ask the user with
  AskUserQuestion for the stop time (say why; let the user type a time such as `2026-10-15 04:56`), then
  check it with `"$S/stop-time.sh" "<their time>"` as above.
- Print exactly `stop at <STOP>` (e.g. `stop at Thu 2026-10-15 04:56:11 EDT`) as its own line of your reply, before running step 2.

## 2. Candidates
`"$S/find-sessions.sh" "<STOP>" [--since "<PREV>"] > "$D/candidates.tsv"` (`--since` only when PREV is known).
One line per session the stop killed: `id cwd agent model mode mid-task mtime-ET transcript why name entrypoint
first-command replies` (the last four are what plan.sh filters on). A session counts
when its transcript was written in the 60 minutes before the stop (`recent`), or when Claude's process file
`~/.claude/sessions/<pid>.json` for it is still there from the stopped boot (`open at stop`: Claude deletes that file
on a clean exit, so a leftover one means the session was open, even if idle for hours). cwd is where the session was
started, so the resume continues the same conversation. A session whose last prompt was `/exit` (or `/quit`) was
closed on purpose and is never listed; every other one that matches is. If the file is empty, say "No Claude sessions were open at
<STOP>; nothing to restore." and stop.

## 3. Plan
`"$S/plan.sh" --candidates "$D/candidates.tsv" --out "$D" --stop "<STOP>" [--boot "<BOOT>" --prev "<PREV>"]` (one `--fix "<correction>"` per correction collected in step 4, in order).
It reads the live tmux panes and `pgrep -af claude` but changes nothing, and prints the table
`tmux session:window.pane | session id | cwd | agent | model | mode | mid-task`, the skipped sessions with reasons
(ended earlier / already running / cwd missing / dropped by user, and the ones it leaves out on its own: older session
in the same project (only the newest per git top-level is reopened), test/temporary folder (a path part named `plans`,
`experiments`, `evals` or `eval_*`), headless `claude -p` run, a `/restore-sessions` run, empty), idle panes it will reuse and the tmux sessions it
will create. Exit 3 = a correction could not be applied (it says why): tell the user and ask again.
If the table has no Claude rows, show the skipped list, say there is nothing to reopen, and stop.

## 4. Ask (one AskUserQuestion, before anything opens)
Before calling AskUserQuestion, write a reply whose text contains `stop at <STOP>` and plan.sh's markdown output
copied verbatim (the seven-column table with full ids and cwds, the skipped list, the notes). Do not shorten,
re-column or summarize it. No option gets a `preview` (the box is clipped to a few lines in a tmux pane).
- question: `Stop at <STOP>. Reopen these <N> sessions as shown in the table above?`
- header `Restore`; options, in this order:
  1. `Yes, reopen them` — description: `Reopen the sessions in the panes shown in the table above`.
  2. `Change something` — description: `Press n and type corrections, e.g. "drop 6883cb51" or "9da9d4aa -> 1:2"`.
  3. `No, cancel`.
- Corrections come from the notes on any option, an Other/typed answer, or a chat reply (any number, comma or
  newline separated; an id prefix of 8 chars is enough): `drop <id>`, `keep <id>` (brings back one plan.sh left out
  on its own), `<id> -> S` (also brings one back), `<id> -> S:W`,
  `<id> -> S:W.P`. If `Change something` was picked with no notes, ask in one line what to change. Add each
  correction as a `--fix`, rerun step 3 with all fixes so far, print the new output and ask again. Repeat until
  Yes (with no notes) or No.
- No → say nothing was changed, and stop.

## 5. Apply
`"$S/apply.sh" "$D"`. It creates missing tmux sessions (`new-session -d`) and windows, splits new panes
(tiled 2x2), puts a pet in the top-left pane of each target window (`cd ~ && terminal-pet[ --pet dog|cat]`, no flag = squid, a
different pet per window until all three are used), sends each resume line, and opens an Ubuntu-profile Windows Terminal window for
each new tmux session, plus one for every other window holding a reopened session that no client shows (S itself
if nothing is attached to it, else a new tmux session `<S>-<W>` grouped with S, showing window W, titled `tmux <S>:<W> (restored)`; nothing is moved), each
brought to front with win.sh (else it says "in the taskbar"). Show its output, including
any `WARNING:` line (for example terminal-pet missing: pets skipped, everything else goes on).

## 6. Verify (once, no retries)
`"$S/verify.sh" "$D"` waits ~12 s, runs `tmux capture-pane` on every resumed pane (the Claude screen, plus the
shell screen with `-a` where the resume line is), checks the prompt, the prompt-box label (the session's `--name` if it has one, else its agent), the mode and the model, takes the screenshot with
`~/.claude/local-tools/screen-capture.sh restore-sessions`, and writes the report to `$D/report.md`.
Then Read the screenshot PNG it names. Only these windows count as restored windows:
- a Windows Terminal window titled `tmux <S> (restored)` or `tmux <S>:<W> (restored)` (the ones in `$D/wt.tsv`), and
- when `RS_TMUX_L` is unset, a window whose tmux status bar (bottom line) names session 0 or 1 (or a `0-<W>`/`1-<W>` view).
For each one, say whether a pet is drawn in its top-left pane ("tmux 1 (restored): cat visible top-left").
For each target tmux window with no window on screen, say "tmux <S>:<W>: not on screen; per tmux the pane runs
terminal-pet". Do not guess from other windows.

## 7. Report
Your final reply is, in this order:
1. The full contents of `$D/report.md`, copied verbatim. Do not summarize, shorten or reorder it. It holds the
   window x pane table, per-pane PASS/FAIL with the captured lines, the capture files, the screenshot path,
   each new Windows Terminal window (frontmost or "in the taskbar"), Not reopened, Stopped mid-task (say
   `continue` in that pane) and Agent or model differs.
2. `Screenshot:` your step 6 finding per window.
3. For each FAIL, what the user should do (e.g. "answer the trust question in pane 0:1.3").
4. `Work dir: $D`.
