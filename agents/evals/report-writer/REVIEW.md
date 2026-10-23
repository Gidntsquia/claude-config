# Review rounds

One entry per round in which the user read a generated report. Each entry records the report shown, the verdict
per rubric criterion, the user's words, and what was added to `RUBRIC.md` or `check.py` because of it.

## Round 1 — 2026-10-17, phone cards (recorded from plans/EVAL.md of that round)

- Report: `out/phone/cards/01..07-*.png` from `bash run.sh phone` (fixture: pogo GPU rounds 8–9, question in
  `fixture/question.txt`); builds of 2026-10-17, 2:30–2:50 PM ET. check.py: desktop PASS (10 checks, 81 figures);
  phone PASS (10 checks, 89 figures); `run.sh sendback` wrote plans/DATA_REQUEST.md (loop 1 of 3) and no report.
- The user read cards 1–3 on a phone ("Yes, and I'm on phone right now"; "Show me phone sized pngs"). The desktop
  HTML was opened in Firefox but not judged.
- Verdicts:
  - Card 1 (verdict, next action, deciding number, Wrong-or-missing; the Ask: know at once what ships, the next step
    and what is wrong): **Works** — rubric 1, 2, 3, 4, 9, 10, 11 pass.
  - Card 2 (decision chart, warm s per generation as bars from zero: 11.70 / 11.16 / 11.63 s): **Fails** — user:
    "The difference is hard to see in the chart because the bars are so close in size together. When we make
    changes, though, to the agent, I want the changes to be generalized."
  - Card 3 (decision table): **Works** — rubric 6, 16 pass.
  - Evaluator: card 1 was 1,201 css px tall and held no chart or table; the first ~800 css px did not show the
    decision (rubric 1 "first screen" read strictly). check.py `first_screen` passed anyway.
- Added because of this round:
  - Rubric 21 "Deciding difference visible" and check.py `decision_chart`: render.py now draws a change-vs-baseline
    panel (diverging bars scaled to the differences, baseline spread shaded around zero) ahead of the measured
    values for every bars chart with a baseline and one or more other measured items; the agent prompt names
    `baseline`, `change_key` and `better`. General rule, not fixture-specific.
  - Rubric 22 "First screen fits" and check.py `first_screen_fits`: all six first-screen elements live in one card;
    cards.mjs measures where they end at 390 px (limit 1000 css px, aim 844) and at 1530 px (limit 1250); the
    question moves to card 2; the agent prompt gives the word budget.
- Still provisional: the user has not yet seen the change-vs-baseline chart or the new first card (round 2).

## Round 2 — 2026-10-17, phone card 1 and the desktop first screen (from plans/archive/EVAL-2026-10-17-report-writer-r2.md)

- Report: `out/phone/report/cards/01-first.png` and a desktop screenshot at 1530 px, shown in chat (the user was on
  the phone). check.py PASS in both modes (12 checks; 86 / 74 figures); phone first screen ended at 838 css px,
  desktop at 597.
- Verdicts:
  - Desktop first screen: **Works**.
  - Card 1 chart (change-vs-default panel with brackets, run dots and the shaded baseline spread): **Fails** —
    user: "It's a little bit unclear. There's too many lines now".
  - Evaluator: the desktop and phone runs of the same fixture disagreed on tail speculation (desktop −0.49 s, 1 vs 1,
    unproven from runs.json; phone +1.03 s, 3 vs 3, drop from runs-all.json) because each mode was a separate
    agent run.
  - User, new ask: "I also want the subagent to itself run a checker subagent to give it a second set of eyes".
- Added because of this round (round 3 build):
  - Rubric 21 rewritten and rubric 23 added: plain measured bars with one spread line each; the writer chooses the
    axis start per chart (`axis_min`, `axis_reason`), the renderer labels "(axis does not start at 0)" and draws
    break marks; check.py `axis_note`. The change-vs-baseline panel and `decision_chart` are gone.
  - Rubric 24 and check.py `modes_match`: one agent run per report; run.sh `build` then renders both modes from one
    report.json. Rubric 25 and `most_runs`: the source with the most runs per arm wins (TRAPS.md names the
    expected n per candidate).
  - Rubrics 26–28, `agents/report-checker.md` (Opus) and check.py `checker_line`: the writer (now Fable) spawns the
    checker through the Agent tool; cold verdict, findings, at most 2 revision loops, open findings in the
    Wrong-or-missing box, counts on the last line. `run.sh planted` plants a shifted figure, a flipped verdict and a
    dropped trap and expects the checker to name each.

## Round 3 — 2026-10-17, pending the user's reading

- Report: `bash run.sh desktop` / `bash run.sh phone` from one `run.sh build`. To judge: card 1 on the phone (bars,
  axis start, break marks: which candidate is ahead and by how much), desktop and phone tables identical, the
  checker's findings on the last line, `run.sh planted` exit 0.
- Verdicts (first reading, on the phone, card 1 as a PNG in chat):
  - Bars with a chosen axis start, one build for both modes, checker: **Better** — user: "This is better than
    before, but it seems the pictures are orphaned without analysis in this photo".
  - Card 1 chart stood between the Wrong-or-missing box and the table with no sentence saying what it shows: **Fails**.
- Added because of this reading (amendment 2026-10-17):
  - Rubric 29 and check.py `chart_reading`: every chart carries a `reading` in report.json, printed under it (who is
    ahead, by how much, clears the spread or not); render.py refuses a chart without one; the checker scans the
    reading as a claim.
- Second reading (on the phone, card 1 as a PNG): chart reading present: **Better**. User: "The language of the report is a
  bit too academic. I want it written in my style, see the write-readme skill".
- Added because of this reading (user instruction in the worker session, 2026-10-17):
  - Rubric 30 and check.py `voice`: report-writer.md gains a Voice section pointing at
    `skills/write-readme/references/style.md`; the check fails "X, not Y" contrasts, emphasis words, em-dashes outside
    the question block, colon taglines opening a heading or paragraph, and one-word verdicts after a colon. The 7:12 pm
    build had 8 tells ("slower, not noise", "rerun, not drop", "Identity: …", "Compact state: …" headings).
- Third reading (on the phone, card 1 as a PNG; plans/EVAL.md 2026-10-17): chart reading **Works**, modes match, checker
  line, planted errors all pass. The report as a whole: **Fails**. User: "It's not right yet. This is better than before,
  but it's dense. It's a wall of AI text. It also doesn't use my style from the write-readme skill. The problem that
  we're aiming to solve must be discussed in the beginning. Also why it's worth solving".
- Added because of this reading (amendment 2026-10-17):
  - Rubric 31 and check.py `problem_first`: report.json gains `problem.what` / `problem.why`; render.py prints them as
    the first paragraph of card 1 and the desktop page, before the verdict, and refuses a report without them.
  - Rubric 32 and check.py `wrong_short`: card 1 runs problem → verdict → next action → deciding number → chart +
    reading → table → Wrong-or-missing; the box holds at most 6 items of one line each (two at most), with normal-weight
    figures; details move to a section. `voice` also fails semicolon chains and a verdict that is a label plus fragments.
    report-writer.md shows the rejected verdict beside the sentence that replaces it.
- Worker follow-up to the third reading (2026-10-18): card 1 of the rebuilt report still said the 0.54 s gap in the
  verdict and again in the reading, and the Wrong-or-missing items read like log lines ("runs.json full null", three
  figures in one item). Rubric 33 and check.py `first_once` (no figure in more than one of verdict, deciding number and
  chart reading) and a stricter `wrong_short` (plain sentences: no `.json` names, at most two figures per item).
- Fourth reading: pending (the evaluator fills this in from plans/EVAL.md).

## Golden-card rounds — 2026-10-18 (plan "Define a good report"; no report-writer run)

Cards are hand-edited copies of build #3's report.json, rendered with render.py only (`golden/make_r<N>.py`). The
rubric was rewritten from scratch (`RUBRIC.md`; the old one is `archive/RUBRIC-2026-10-18.md`).

- r1 (old card 1 + A dense / B concise / C caveats sorted by kind; phone PNGs in chat):
  - Problem quote source: "Usually option 1 …" → rubric 1.
  - Picked B concise over A dense → rubric 3, 4 (markers only on the verdict and the deciding number; the rest of the
    evidence moves to card 2).
  - Picked B's flat caveat list over C → rubric 5.
  - Verdict when the quote asks for something that lost: "Answer it first" → rubric 2.
  - Process: "I want to see only two options max per round".
  - References (GOV.UK organ donation trial, Python 3.11 What's New, Discord Go to Rust): "I don't like any of
    them". Nothing kept.
- r2 (A answer-first with absolute bars / B the same with a chart of change against default):
  - "A; it's hard to tell what the base is in B" → rubric 6.
  - The card as a whole: **Fails**. User: "We're not even close. This is way too dense, you have done insufficient
    research, and you should work through the plan start to finish and the evaluator should show me these".
  - Added because of this reading: a second research pass (`golden/RESEARCH.md`: Chain of Density, ONS main points,
    GOV.UK sentence length, NN/g); render.py `first.move_down` (deciding line, chart, table to a "The numbers" card 2)
    and `first.points` (2-4 main points under the verdict); the numbers card keeps card 1's phone sizes.
- r3 (built by the worker, shown by the evaluator; both from r2 A):
  - A trimmed: quote, why (15 words), two-sentence verdict, next action, chart with a one-line reading, 4 caveats.
    Deciding line and table on card 2. Card 1 ends at 595 css px (current build: 939).
  - B main points: the chart moves to card 2 too; three one-point bullets under a one-sentence verdict. Card 1 ends at
    512 css px.
  - While r3 was being built, of the quote on r1-r2: "The quote from me isn't very descriptive. It refers to "option 4"
    yet it's not clear what that option was" → rubric 7. The quote keeps the user's words and gains "[round 8's
    recommendation 4: start the next round's battles while the GPU waits on the last ones]"; check.py `problem_first`
    fails a numbered pointer with no note. Card 1 now ends at 634 (A) and 551 (B) css px.
  - Reading: pending (the evaluator fills this in).

## Round of 2026-10-21 — essay form on Opus, seven card sets (pending the user's reading)

Writer rewritten (`agents/report-writer.md`, Opus medium; archive `archive/report-writer-2026-10-21.md`); build
pipeline `agents/report-writer/build.py` (report.md + numbers.json → report.html + cards); checker reads report.md.
Eval harness: `~/files/agent-eval-experiment/report-writer/` (`report_eval.py`, cases/gpu with expected.json frozen
from golden r5 B, fixtures worker/planner/token/mcp/checker). Shown this round, in order: gpu on, gpu off, worker on,
worker off, token, mcp, checker (`builds/<fixture>-<on|off>/cards/`). Golden r4 A fails `ai_tells` under the new
check; r5 B passes all 19 checks; r5 B with one figure shifted fails `expected`.

- Reading: pending (the evaluator fills this in).

- Reading (gpu on, gpu off, 2026-10-21): rejected. "The first box in the report is the question, not my answer. The
  report in general is not as good as the golden one, so we've missed the mark. The logic doesn't follow from
  paragraph 1 to paragraph 2." → rubric 15–18 and INVESTIGATION.md. Root causes: the agent prompt said to quote
  `question.txt` whole when it was the ask and the GPU fixture had no `ASK.md`; the length rule counted the
  question's candidates; sections were organised by arm with topic headings. The other five sets were not read.

## Round of 2026-10-21, second pass — answer first, question headings, the user's words

Agent prompt changed (card 1 = title as conclusion, answer line, the user's ask from `ASK.md`, question headings,
microcosm returning in a middle section, length from the user's ask); `cases/gpu/ASK.md` added; `check.py` gains
`ask_quote`, `lead_answer`, `headings_ask`, `microcosm_thread`. All nine builds rebuilt with the new prompt
(`builds/<fixture>-<on|off>/`; the rejected ones kept under `builds/prev-round/`).

- Reading: pending (the evaluator fills this in).

## Round of 2026-10-22, third pass — send-back on inconclusive data, natural-error rate, worker-on without a tally

User on the mcp report (F): good, but when the data is inconclusive the writer should send the study back for more
data before writing. User on the checker report (G): planted catches do not say how often errors come up naturally
or whether the ~25% cost is worth it. `--check worker` failed `numbers_match_sources` on 43 keys citing
`report/tally.json`, a file the writer made (INVESTIGATION.md "Writer-made data files").

Changes: the writer prompt gains a send-back step (rules `ci_includes_zero`, `n_below_two`, `arm_not_run`) and the
"no writer-made data files" rule; `build.py`/`check.py` gain the `[?k=v]…|agg` field syntax and refuse files under
the report dir; `cases/mcp` is an eval case expecting a send-back; `report_eval.py --cold` runs the checker cold on
an off build; `fixtures/checker/data/natural.json` and `mechanical.json` added and the checker report rebuilt;
worker-on rebuilt under the rule. Shown: checker v2, the mcp send-back (NEEDS-DATA.md as cards), worker-on rebuilt.

- Reading: pending (the evaluator fills this in).
