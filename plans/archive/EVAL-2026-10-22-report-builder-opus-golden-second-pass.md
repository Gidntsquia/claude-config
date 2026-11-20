# Eval — 2026-10-22 — Report builder rewritten on Opus around the golden storyteller report (second pass)
Verdict: replan

## Fix next
1. Checker report (G) counts only the planted errors. It does not say how often errors come up on their own in normal builds, so it can't show whether the ~25% extra cost is worth it (user).
2. New behavior: when some or all of the data is inconclusive, the report writer should send the work back to the worker to collect more data before writing the full report (user, on MCP).
3. worker-on fails `numbers_match_sources` (`report_eval.py --check worker`: 43 failing), although WORKER_NOTES says R8 passes on every build. Report G itself says so on card 6.
4. GPU on is "much better than before" but "still not quite as good as the golden report" (user).

## Criteria
- [x] R1 — PASS — 0 paragraphs shared with the archive; checker names report.md/numbers.json.
- [x] R2 — PASS — verify_shown shows seven outputs and the four NOTES sections on all 9 builds.
- [x] R3, R5 — PASS — greps clean; card 1 leads with the answer on all seven sets (seen on phone cards).
- [x] R4, R6 — PASS — prose checks pass, ai_tells named; worker-on's only failure is numbers (R8).
- [x] R7 — PASS — gpu and checker short with no chart; worker, token and mcp long with a chart.
- [ ] R8 — FAIL — worker-on `numbers_match_sources` FAIL; gpu, token, mcp, checker and worker-off pass.
- [x] R9 — PASS — checker line on on-builds, "checker: off" on off-builds (seen on the last cards).
- [x] R10 — PASS — fixtures/ lists checker gpu mcp planner token worker, each with the needed files.
- [x] R11 — PASS — 8 builds + 4 planted logs, caught/missed per error (11/12).
- [x] R12 — PASS — fixtures/checker/data/{findings,planted,diffs,cost}.json; checker-on built from them.
- [ ] R13 — FAIL — 7 sets shown on the phone; A: "It's much better than before. It's still not quite as good as the golden report, but I want to see the other reports before passing my judgement"; B: "hard to tell by eye. The report looks good" (corrected from a mis-tap); C: "The report is excellent"; D: "I can't tell by eye. I don't know where the mistake was planted"; E: "Excellent. Works"; F: "The report is good…" (see User said); G: see User said.
- [x] R14 — PASS — git log -1 = 53630c1; nothing staged.
- [x] R15, R19 — PASS — runs.jsonl rows have every field; --dry-run lists the job; REPORT.md written.
- [x] R16 — PASS — run.sh golden: r4 A FAILs ai_tells; r5 B PASS (23 checks).
- [x] R17 — PASS — REPORT.md has writer FE, checker FE, wall, CI, gap and cost flag columns.
- [x] R18 — PASS — cases/gpu/expected.json; `--promote worker` refused without --accepted; cases/ = gpu.
- [ ] Amend: card 1 leads with the answer; gpu reads as well as golden r5 B — FAIL — user: "still not quite as good as the golden report".
- [x] Amend: paragraphs follow one thread — PASS — user on C/E: "excellent"; A: "much better".
- [x] Amend: INVESTIGATION.md — PASS — exists, 155 lines, side-by-side quotes and a detectable/not table.
- [x] Amend: new checks — PASS — ask_quote/lead_answer/headings_ask/microcosm_thread fail prev-round gpu-on/off and pass the current builds; golden r5 B passes.
- Shown as labeled phone PNGs in chat (EVAL_NOTES); no desktop windows, so no evshow timing lines.

## User said
- On B: "I picked the wrong answer. I meant to say that it's hard to tell by eye. The report looks good"
- On F (mcp): "The report is good. In this case, when the some or all of the data is inconclusive, I would like the report writer to send back to the worker and tell it to collect more data until it's conclusive before writing the full report"
- On G (checker): "The checker was successful at finding planted errors, but the report fails to account for the fact that we planted those errors; it's not clear how often the errors naturally come up and whether the 25% extra cost is worth it in normal usage cases"
