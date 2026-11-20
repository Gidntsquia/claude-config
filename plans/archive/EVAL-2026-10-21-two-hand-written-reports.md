# Eval — 2026-10-21 — Two hand-written reports on the fixture study
Verdict: replan

## Fix next
1. Both reports read as AI-written from the first line, so the user stops reading. A opens "One generation, then."; B opens "Here is one of the waits." (golden/r4/A|B/report.md line 9).
2. The same voice runs through the bodies: one-word self-answers ("Yes." "No." "Plenty."), stage-direction lines ("The rest of this is a search for the second"), aphorisms ("Busy and useful are different things"), "a hint rather than a measurement" (an "X, not Y"), run IDs as sentence subjects.
3. check.py's voice/voice_prose checks (rewritten by the worker this round) pass both reports, so they do not catch what the user calls AI tells.
4. Neither A nor B picked; no golden, no RUBRIC rewrite.

## Criteria
- [x] R1 — PASS — sha256 of the 3 agent files matches WORKER_NOTES (2839da8e…, 8db0f085…, 59f009bf…); the worker.md diff was already there before this round.
- [ ] R2, R3 — FAIL — quote, label, generation and "But" are all on card 1, but user on A: "Sounds like AI wrote it right from the get go. "one generation, then" is not something a human would write. Investigate"; on B: "I can't even get past the first sentence. "Here is one fo teh waits" is clearly an AI written sentence, and makes me not want to read any further".
- [ ] R4–R6 — FAIL — not judged past the opening; the user stopped at the first sentence of each (answers above).
- [ ] R7, R8 — FAIL — grep finds no banned words, bold or em dashes outside the quote and check.py voice passes, but the user judged both as AI voice (above).
- [ ] R9 — FAIL — the reports differ (8 cards with a chart vs 5 with emoji headings), but both fail the same way, so there is nothing to pick. Side-by-side page not shown.
- [x] R10 — PASS — check.py --prose: A PASS (10 checks, 86 figures), B PASS (10 checks, 57 figures); plans/eval_r35_checks.log.
- [x] R11, R12 — PASS — 8 PNGs in golden/r4/A/cards, 5 in B/cards; WORKER_NOTES has paths, labels and the question.
- [x] R13 — PASS — HEAD still 1c97637; nothing committed.
- Show timing (evshow history): A (1st open, images broken) elapsed 6.09 s (answer -> shown), question emitted 10:53:54.034 ET (shown -> question 3.32 s); B (broken) elapsed 2.5 s (answer -> shown); A reopened by hand after the fix (no elapsed line), question emitted 10:54:57.907 ET (shown -> question 42.33 s, counted from the broken B show; the fix happened in between); B elapsed 2.13 s (answer -> shown), question emitted 10:56:18.278 ET (shown -> question 4.66 s).
- Evaluator error: on the first open the image src paths in my viewer pages were broken, so the PNGs showed blank (user: "The report is blank on my PC screen (Image attached)"). Fixed with relative paths, capture confirmed, asked again.

## User said
- "The report is blank on my PC screen (Image attached)"
- "Sounds like AI wrote it right from the get go. "one generation, then" is not something a human would write. Investigate"
- "I can't even get past the first sentence. "Here is one fo teh waits" is clearly an AI written sentence, and makes me not want to read any further"
- Next step: "Replan (Recommended)": the planner should rethink how to make the writing sound human, not just patch these tells.
