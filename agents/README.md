# agents/

One markdown file per agent (`claude --agent <name>`); `USAGE.txt` has the hand-off rules between them.

- `planner.md`, `worker.md`, `evaluator.md`, `helper.md`: the plan loop (see `USAGE.txt`).
  - worker: at the usage limit it schedules its own relaunch via `/run-agent` (after the window resets), writes a `## Stopped at usage limit` handoff section in `plans/WORKER_NOTES.md`, commits, and stops; the relaunch reads that section first.
- `report-writer.md`: the essay a study's data supports, in a storyteller's voice (Opus medium; one checker loop by
  default, a second read only when a high finding moves the ending). When to call for a report and how to run it,
  with the send-back loop: `../skills/write-report/SKILL.md`.
- `report-checker.md`: the writer's second set of eyes, a cold verdict then a read of every figure (Opus medium).
- `report-writer/`: `build.py`, `cards.mjs`, `checker_usage.py`, the writer's tools.
- `evals/report-writer/`: `check.py` (the mechanical gate, `--prose` for the essay form, `style` for the golden's shape
  and voice), `run.sh`, and the golden reports.
