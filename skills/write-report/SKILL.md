---
name: write-report
description: Load before planning or building anything that compares, measures or benchmarks (which is cheaper, faster, better; whether; how much), or when the user says report, write-up, findings or compare. How to offer and run the report-writer agent.
---

# write-report

The report-writer (`claude --agent report-writer`) writes the essay a study's data supports: the user's ask quoted
first, one typical unit followed through the numbers, every figure a sourced `{key}`, a page plus 390 px phone cards,
and a report-checker reading it cold. This skill says how a plan calls for one and how a worker runs it.

## Planning

Whenever the work involves data, the planner's round-1 deliverable question offers "report-writer report" as one of
its options (beside a page, a table, a script), and a plan that chooses it carries this requirement text, filled in:

- The data directory: where the runs, measurements or logs land, with a `README.md` that says how each quantity is
  defined (field names, scorer, units) and nothing written by hand into it afterwards.
- `ASK.md` in that directory: the user's ask verbatim (their own words, with when and where they said it), never the
  study's question.
- The decision question in one sentence: what the report must settle, which arms it compares and by which quantity.
- `--out <dir>`: where the report goes (`<data dir>/report/` when unsaid).
- Checker on: `--no-checker` only when the user says so.
- The acceptance criterion: `check.py --prose` PASS on the output, and the user reads `report.html` at phone width.

## Running

Run it once the data directory is complete, from the project root:

    claude --agent report-writer "<data dir> — <question> --out <dir>"

Read the reply's last line.

- Ends with the output directory, the check.py line and the checker line: the report is written. Open it for the user
  at phone width: `"/mnt/c/Program Files/Mozilla Firefox/firefox.exe" -new-window "$(wslpath -w "<dir>/report.html")" &`
  (one window), and record the check.py and checker lines in `plans/WORKER_NOTES.md`.
- Ends with `send-back: needs data`: the data cannot settle the ask. `<dir>/NEEDS-DATA.md` names the comparison,
  the rule that fired (`ci_includes_zero`, `n_below_two`, `arm_not_run`) and a `## Collect` section with the arms,
  how many more runs each and the exact command. Run that command (the study's own, not a stand-in), put the results
  in the data directory, and rerun the same prompt. Two send-backs on one study are the most the writer makes; on the
  third run it writes the report and tells the unsettled comparison as unproven. Record each send-back (rule, what was
  collected, run ids) in WORKER_NOTES.

The writer never asks the user anything and never edits the data directory beyond its output directory. A report that
fails `check.py` is not done; rerun the writer rather than editing `report.md` by hand.
