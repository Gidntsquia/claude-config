# Eval — 2026-10-14 — weekly-roundup usage-by-day chart (round 2: column placement)
Verdict: rerun worker

## Fix next
1. Day chart lumps both Sundays into one column; user wants the opening Sunday (10pm–12am) first and the closing Sunday (12am–10pm) last (see Amendments in PLAN.md).
2. Column-placement amendment not yet judged: user's answer was about the Sundays, not placement. Ask again next round.

## Criteria
- [x] R1–R16 — PASS last round (plans/archive/EVAL-2026-10-14-daychart-round1.md); R13 rerun: `uv run pytest skills/weekly-roundup/tests` → 18 passed, rc=0 (plans/eval_r14_pytest.log).
- [ ] Amendment: chart in the column that balances heights, left on Oct 4–11 — not yet judged — user: "There should be two Sundays-- The sunday from 10:00pm-12:00am at the beginning, then the Sunday from 12:00am-10:00pm at the end". Shown (local copy of the v8 published HTML, worker's scratchpad week.html): elapsed 4.43 s (answer -> shown); question emitted 19:19:25.456 ET (shown -> question 3.19 s).
- [ ] Amendment "Republished in place (same URL)" — not checked by command (needs Artifact read of https://claude.ai/artifact/9syKSHEvUk6m9gVMoHhFhz); worker claims v8.

## Amended
- Day chart gets 8 columns: opening Sunday (22:00–24:00) first, closing Sunday (00:00–22:00) last, week page and archive.

## User said
- "There should be two Sundays-- The sunday from 10:00pm-12:00am at the beginning, then the Sunday from 12:00am-10:00pm at the end"
