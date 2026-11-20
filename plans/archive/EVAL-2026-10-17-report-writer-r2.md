# Eval — 2026-10-17 — report-writer agent with pogo GPU rounds 8–9 fixture (round 2)
Verdict: replan

## Fix next
1. Decision chart (phone card 1, desktop top right): the change-vs-default panel has too many lines — brackets, run dots and shaded spread drawn together; user: "It's a little bit unclear. There's too many lines now".
2. The desktop and phone runs of the same fixture give tail speculation different rows (desktop: −0.49 s, 1 vs 1, unproven; phone: +1.03 s, 3 vs 3, drop). Compare the two report.html decision tables.

## Criteria
- [x] R1 — PASS — carried from round 1 (frontmatter opus/high, README line 30, CHANGELOG Unreleased); not changed this round.
- [x] R2–R5, R7–R9 — PASS — `run.sh check desktop` and `check phone`: check.py PASS, 12 checks each (86 / 74 figures); phone first screen ends at 838 css px, desktop at 597. User, desktop first screen (picture at 1530 px, shown in chat): "Works".
- [x] R4/R5/R10/R11 traps — PASS — check.py `traps`: 4 flagged, none quoted as a plain figure; card 1 box shows full-tail-1 not run, 42.6% vs 35.2% conflict, tail v2 unproven, full-run wall not measured.
- [x] R6 — PASS — out/sendback/work/plans/DATA_REQUEST.md exists and the sendback report dir has no report.html (only old evaluator files).
- [x] R9 — PASS — 10 phone cards, all 780 px wide (2x of 390), tallest 1740 px = 870 css px; the user read card 1 on the phone.
- [x] R12 — PASS — RUBRIC.md has criterion 21 (deciding difference visible); REVIEW.md round 1 filled in; user read a generated report.
- [x] R13 — PASS — check.py `checked_line` PASS in both modes ("numbers.json has 86 figures; check.py: PASS …").
- [ ] Amendment: deciding difference visible at a glance — FAIL (user) — card 1 chart; user: "It's a little bit unclear. There's too many lines now".
- [x] Amendment: fix lives in the general rules — PASS — report-writer.md lines 65–67 and render.py state the rule in general terms; check.py `decision_chart` enforces it; RUBRIC.md row 21.

Timing: the user was on the phone (EVAL_NOTES: phone-sized PNGs in chat), so no windows were opened; card 1 and a desktop screenshot were shown in chat. There are no evshow timing lines.

## Amended
- Decision chart must show the deciding gap with few marks, not stacked brackets/dots/bands (user).

## User said
- "I'm on my phone"
- Card 1 chart: "It's a little bit unclear. There's too many lines now"
- Desktop top screen: "Works"
- "I also want the subagent to itself run a checker subagent to give it a second set of eyes"
