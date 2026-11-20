# Eval — 2026-10-21 — Two reports on the fixture study, written in a storyteller's voice, with an AI-tells list
Verdict: replan

## Fix next
Nothing failed. The user accepts both reports and wants a new step: write what this golden report taught into a document, then start building the report builder again (see User said).

## Criteria
- [x] R1 — PASS — sha256 of report-writer.md 2839da8e…5f5d, report-checker.md 8db0f085…d388, worker.md 59f009bf…6b43 match the worker's recorded hashes; no agent run in this session.
- [x] R2, R3 — PASS — docs/ai-tells.md has 25 numbered tells including the user's four, rule of three and em dashes, ending with "## How to add one"; `cmp` with wiki/AI-Tells.md shows they are identical; README line 69 links both; `git check-ignore` shows `.gitignore:12:/wiki/`; wiki has nothing unpushed beyond the untracked file.
- [x] R4 — PASS — WORKER_NOTES has the persona bio naming McPhee, Lewis and Roach.
- [x] R5 — PASS — WORKER_NOTES lists ten openings for each report with the reasons for each strike; the pick is the first sentence after the label on card 1 of both (seen in the PNGs).
- [x] R6, R7 — PASS — card 1 of both shows the quote, the who line, a 6-word label, the generation 7 microcosm and "But" with 12.60 s → 13.63 s, n = 3; generation 7 comes back mid-report and at the end.
- [x] R8 — PASS — `grep -nE "(^|[.!?] )r9" golden/r5/*/report.md` exit 1 (no match).
- [x] R9 — PASS — `check.py --prose` passes on r5 A (11 checks, 86 figures) and B (11 checks, 57 figures); r4 A and B fail `ai_tells` (fragment, x_then, run_id_subject, here_is, call_it named).
- [x] R10 — PASS — the self-review change log table is in WORKER_NOTES.
- [x] R11 — PASS — 8 and 6 PNGs shown on the phone with A/B banners; user: "Both are excellent, and both would be correct output in my eyes. Long vs short should simply depend on the task at hand. In this case, B’s shorter report is more appropriate."
- [x] R12 — PASS — HEAD is 8299d8a, nothing committed.

## User said
- (first showing, with no banners on the cards) "The various reports got mixed together. It’s impossible to tell which is which"
- "Both are excellent, and both would be correct output in my eyes. Long vs short should simply depend on the task at hand. In this case, B’s shorter report is more appropriate. I want to collect the data learnings from this golden report into a document and start building the report builder again"
