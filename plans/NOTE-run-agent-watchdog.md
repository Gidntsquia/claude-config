# Note: run-agent.sh --watchdog (not built; left here on 2026-10-31 for whoever edits run-agent next)

## Why
terminal-pet round-9 session 693d7b3e (Oct 30): the worker's last tool result at 9:39 PM ET was `Exit code 137` on a
chained `cargo test && cargo clippy` call (likely OOM: 11 GB RAM, `capy_walk.py --splice` running). No assistant message
followed and no job was scheduled. The worker.md relaunch rule ("wait-only work schedules its own relaunch") only runs
when the worker chooses to end its turn; a killed process runs nothing. No agent text can act after a kill, so this is a
launcher-side fix.

The worker eval case `c14-killed` (`~/files/agent-eval-experiment/worker/cases/c14-killed`, the c11 fixture with the
`claude` process SIGKILLed 120 s after start) reproduces it: its hidden test looks for a pending `worker` job under
`RUN_AGENT_HOME/jobs` within 10 min of the kill. Every arm fails it today (`needs-watchdog` rows); it is excluded from the
install rule for worker-finish5.

## Proposed flag
`run-agent.sh worker "<prompt>" --watchdog <minutes> -- --model ... --effort ...`

1. Before starting the session, the launcher schedules a relaunch job of the same prompt, model and effort at
   now + <minutes> (the same job file `run-agent.sh --at` writes), and records the job id in an env var the session can
   read (e.g. `RUN_AGENT_WATCHDOG_JOB`).
2. While the session is alive, the launcher (or the job runner) pushes the job's fire time forward on each check
   (a heartbeat: the session's transcript mtime, or a `touch` of a file by a PreToolUse hook), so a healthy long run
   never fires it.
3. The worker's final message ends normally; the launcher cancels the job with `run-agent.sh --cancel <job id>` when
   the `claude` process exits 0 with a final message. A process that dies (exit 137, no final message) leaves the job
   in place, and it fires: the relaunched worker reads `plans/WORKER_NOTES.md` (its `## Criteria` table and
   `## Progress` line) and `git log -20` and goes on from the first `not` row, which is what worker-finish5's
   compaction paragraph already tells it to do.

## How c14 then passes
The harness launches the arm through `run-agent.sh ... --watchdog 5`; the kill at 120 s leaves the pre-scheduled job
under `RUN_AGENT_HOME/jobs`; the hidden test finds a pending `worker` job within 10 min of the kill. No change to the
agent text is needed for it.

## Not touched
Nothing under `skills/run-agent/` was edited for this note (the user is editing run-agent.sh); `plans/` here is
gitignored, so this note is not committed.
