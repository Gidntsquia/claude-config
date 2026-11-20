# Eval — 2026-10-21 — Report builder rewritten on Opus around the golden storyteller report
Verdict: rerun worker

## Fix next
1. The GPU reports (checker on and off) fall well short of golden r5: card 1 opens with the question box, not the answer, and paragraph 1 does not lead to paragraph 2 (user, both GPU sets).
2. Every mechanical check passes on reports the user rejects: check.py does not detect what the user saw.
3. gpu-on chose the long form with a chart; the plan says the GPU report is short.
4. `fixtures/gpu` (→ `cases/gpu`) has no `ASK.md`.
5. Not yet judged by the user: worker on, worker off, token, mcp, checker card sets (stopped after GPU on the user's word).

## Criteria
- [x] R1 — PASS — 0 shared paragraphs with the archive; archive exists; checker names report.md/numbers.json, opus/high; writer opus/medium.
- [x] R2 — PASS — verify_shown: seven outputs True on all 9 builds.
- [ ] R3, R5 — FAIL — greps clean, but user: "The first box in the report is the question, not my answer… The logic doesn't follow from paragraph 1 to paragraph 2."
- [x] R4, R6 — PASS — check.py --prose PASS on every build, ai_tells named.
- [ ] R7 — FAIL — gpu-on NOTES "Long, with one bar chart"; plan says GPU short. Checker short, worker long: as asked.
- [x] R8 — PASS — figures, numbers_match_sources, traps, most_runs PASS on all builds.
- [x] R9 — PASS — on builds end `::checker loops=… raised=… fixed=… open=… tokens=… seconds=…`; off builds `::checker off`.
- [ ] R10 — FAIL — ls fixtures/ shows all six, but gpu has no ASK.md.
- [x] R11 — PASS — 8 builds + 4 planted logs; caught/missed per error (11/12, mcp "dropped" missed).
- [x] R12 — PASS — fixtures/checker/data/{findings,planted,diffs,cost}.json; checker-on build passes.
- [ ] R13 — FAIL — GPU on: "we've missed the mark"; GPU off: "Same issues as before… nowhere close to where we should have it." Other five not judged.
- [x] R14 — PASS — git log -1 = 53630c1; nothing staged.
- [x] R15, R19 — PASS — runs.jsonl 3 rows, status ok, all fields; --dry-run lists jobs; REPORT.md written.
- [x] R16 — PASS — run.sh golden: r4 A fails ai_tells, r5 B passes; shifted-figure line cut from the captured tail (worker claims FAIL expected).
- [x] R17 — PASS — REPORT.md has writer FE, checker FE, wall, CI, gap and `cost flag` columns.
- [x] R18 — PASS — cases/gpu/expected.json exists; `--promote worker` refused without --accepted; cases/ = gpu.
- Timing: item 1 `elapsed 5.76 s (answer -> shown)` (first try not shown: not topmost; reopened, visible per capture); question emitted time not logged for it. Item 2 `elapsed 2.14 s (answer -> shown)`, `question emitted 18:17:14.121 ET (shown -> question 6.93 s)`.

## Amended
- Card 1 leads with the answer; paragraphs follow one thread; INVESTIGATION.md of differences vs golden r5 B; detectable differences coded in check.py so current GPU builds fail.

## User said
- GPU on: "The first box in the report is the question, not my answer. The report in general is not as good as the golden one, so we've missed the mark. The logic doesn't follow from paragraph 1 to paragraph 2. In general, we've missed the mark"
- GPU off: "Same issues as before. We need to send this back to the worker, this is nowhere close to where we should have it. I want an investigation into why its so different and also an investigation into how we can detect that it's off and what we can do to fix"
- On verdict: "I don't want to send this back to the planner. Send it to the worker"
