# agents/

One markdown file per agent (`claude --agent <name>`); `USAGE.txt` has the hand-off rules between them.

- `planner.md`, `worker.md`, `evaluator.md`, `helper.md`: the plan loop (see `USAGE.txt`).
  - worker: at the usage limit it schedules its own relaunch via `/run-agent` (after the window resets), writes a `## Stopped at usage limit` handoff section in `plans/WORKER_NOTES.md`, commits, and stops; the relaunch reads that section first.
- `report-writer.md`: the essay a study's data supports, in a storyteller's voice (Opus medium; one checker loop by
  default, a second read only when a high finding moves the ending). When to call for a report and how to run it,
  with the send-back loop: `../skills/write-report/SKILL.md`.
- `report-checker.md`: the writer's second set of eyes, a cold verdict then a read of every figure (Opus medium).
- `report-writer/`: `build.py` (Markdown + `numbers.json` → page and phone cards; blocks `::bars`, `::table`, `::split`,
  `::pair`; appends each built report's opening form and title shape to the ledger), `cards.mjs`, `checker_usage.py`.
- `evals/report-writer/`: `check.py` (the mechanical gate, `--prose` for the essay form, `style` for the golden's shape
  and voice, `visuals` for blocks in middle sections, `opening_ledger` against repeated openings), `run.sh`, the golden
  reports, and `ledger.jsonl` (one line per built report: form, title shape, out).
