# Report-writer rubric (rebuilt 2026-10-18)

Started from scratch. A row is added only after the user judged a golden card by eye; the old rubric is in
`archive/RUBRIC-2026-10-18.md`. Golden cards are hand-edited copies of build #3's `report.json`, rendered with
`render.py` only (`golden/make_r<N>.py`, `golden/r<N>/<variant>/cards/01-first.png`). Status: not signed off.

| # | Criterion | User's words that set it | Round / variant | check.py |
|---|-----------|--------------------------|-----------------|----------|
| 1 | Card 1 opens with the user's problem as a verbatim quote from the study's `PLAN.md` `## Ask` (or the ask the worker passed along when the report was asked for in a worker session), marked as a quote with where it was said, then one plain sentence on why it is worth solving | "Usually option 1 [the user's words from the planner session], unless I asked for the report in the worker session, in which case the worker should say pass along the quoted ask" | r1, B picked (all variants open this way) | ✔ `problem_first` (quoted form: a why line of at most 2 sentences after the quote) |
| 2 | The verdict answers the quote first, in its own terms, before naming what ships (e.g. "Not yet. Both wait-time fixes ran slower than default. Compact state is the change that ships.") | "Answer it first" (asked: the quote wants the wait-time fix, which ran slower) | r1, question 4 | by eye |
| 3 | Two passes: a dense first pass where every claim on card 1 carries a numbered evidence marker, then a concise pass that keeps the full evidence list on card 2 and shortens card 1 | "Perhaps we first make the report in this dense fashion with every claim linking back to precise evidence, and then we make a second pass which focuses on concision"; picked B (concise) over A (dense) | r1, B over A | ✔ `numbers_on_page` ignores markers; markers must resolve (render refuses an unknown `[[id]]`) |
| 4 | After the concise pass, card 1 keeps markers on the verdict and the deciding number only; the reading, the caveats and the table carry none; every claim's evidence (file, field, run, value) stays on card 2 | "You decide" (worker chose B's set: verdict + deciding number) | r1, B | by eye |
| 5 | Card 1's Wrong-or-missing box is a flat list of the caveats that bear on the decision (4 here: full run not measured, crashed run, tail-share conflict, one-run candidate); the rest move to card 2 | picked B (flat, 4 items) over C (sorted by kind, with the flipping assumption) | r1, B over C | ✔ `wrong_short`, `traps` |
| 6 | The decision chart shows each arm's own value (default as a bar beside the candidates, spread lines on each), so the base is visible; a chart of differences against default is not used on card 1 | "A; it's hard to tell what the base is in B" | r2, A (absolute bars) over B (change against default) | ✔ `axis_note`, `chart_reading` (the absolute form itself: by eye) |
| 7 | The quote makes sense on its own: when the user's words point at an item from an earlier page ("number 4"), a [bracketed note] inside the quote says what that item was; the user's words stay verbatim | "The quote from me isn't very descriptive. It refers to "option 4" yet it's not clear what that option was" | r3, said of r2's card 1 (both r3 variants carry the note) | ✔ `problem_first` (a numbered pointer with no [note] fails); render.py shows the note upright and grey |

## Process rules from the user (not report criteria)

- At most two options per round ("I want to see only two options max per round", r1).
- Golden cards are shown as 390 px phone PNGs in chat, next to the current card.
- From r3 on, the worker builds the cards and the evaluator shows them ("you should work through the plan start to finish
  and the evaluator should show me these", r2).
- Reference reports: none kept. The user rejected all three shown in r1 ("I don't like any of them").

## Open, waiting on the user's eyes (not criteria yet)

- r2: "We're not even close. This is way too dense, you have done insufficient research". Round 3 answers it with two
  lighter card 1s (`golden/r3/`): A keeps the chart, B puts three main points in its place. Both move the deciding line
  and the decision table to a "The numbers" card 2. A row is written here only after the user picks.

## Round of 2026-10-21 — essay form, Opus writer, regression eval

The writer was rewritten from a blank page around golden r5 B (`golden/r5/B/`, the storyteller card set) on Opus
medium; the old fable/high prompt is `archive/report-writer-2026-10-21.md`. What the golden set fixed, now checked by
`check.py --prose` (rows 8-14 below are mechanical; no row is signed off until the user reads the new builds):

| # | Criterion | Where it comes from | check.py |
|---|-----------|---------------------|----------|
| 8 | Card 1 holds the verbatim ask as a quote with where it was said, a [bracketed note] when the ask points at an item, a label line of at most six words when the ask names an option, the microcosm (one named typical unit told as an event) and the "But" paragraph with both means and n, all inside one 390×844 screen | golden r5 B; plan R3 | `card1` |
| 9 | No run ID is a sentence subject; runs are named by what they are, the ID in parentheses once | plan R4 | `ai_tells` (run_id_subject) |
| 10 | No section titled caveats, summary or verdict; no verdict word; the ending returns to the microcosm's unit with its after numbers and the state of the ask | plan R3 | `no_summary_sections`, `ending`, `expected` (state words) |
| 11 | Every figure on the page is a `{key}` into numbers.json with file and field or a recomputable derivation; derived values recompute within tolerance; no digit typed in prose | plan R2, R8 | `figures`, `numbers_match_sources`, `numbers_on_page` |
| 12 | Every trap in the study's TRAPS.md is told as a plain sentence (its flag words together in the body) and its trap number never appears as a plain figure; the most-runs source decides each candidate's n | plan R8 | `traps`, `most_runs` |
| 13 | Every regex-checkable tell in `docs/ai-tells.md` is absent; sentences ≤45 words, paragraphs ≤8 lines, no fragments under four words; terms defined once at first use | plan R4, R6; style.md | `ai_tells`, `voice`, `voice_prose`, `prose_shape`, `terms_once`, `paragraphs` |
| 14 | The last line prints the checker loops, raised, fixed, open, checker tokens and wall seconds, or `checker: off` | plan R9 | `checker_line` |

Human-only tells (not coded): aphorisms (ai-tells 3), uniform sentence length (13, partly coded), title-case and
emoji decoration (14), parenthetical habit (17), elegant variation (18), no first-hand detail (23).

### Amendment of 2026-10-21 (after the user read gpu on and gpu off)

User: "The first box in the report is the question, not my answer… The logic doesn't follow from paragraph 1 to
paragraph 2." The investigation is `~/files/agent-eval-experiment/report-writer/INVESTIGATION.md`. New rows, all
mechanical, all passing on golden r5 B and failing on both rejected GPU builds:

| # | Criterion | Where it comes from | check.py |
|---|-----------|---------------------|----------|
| 15 | The first quote is the user's own words (≤60 words, a person as speaker, no sentence of `question.txt` in it) | amendment; INVESTIGATION 1 | `ask_quote` |
| 16 | Card 1 leads with the answer: a title that is not a question, then an answer line with the deciding figure (new form) or the user's own short ask (golden form); never the study's question | amendment; INVESTIGATION 2 | `lead_answer` |
| 17 | Every section heading but the last asks the question that section settles (ends in `?`), no two alike; the last section returns to the microcosm under a plain heading | amendment; INVESTIGATION 3 | `headings_ask` |
| 18 | The microcosm's unit (its `[[ident]]`, run ID or clock time from card 1) is named again in at least one middle section | amendment; INVESTIGATION 4 | `microcosm_thread` |

Human-only, added this round: whether the answer line answers the ask, whether each heading is the question the
previous section raised, and the length choice (short when the user asked about one thing; `## Length` in NOTES.md
gives the reason).

## Round of 2026-10-22 — send-back, natural-error rate, no writer-made data files

| # | Criterion | Where it comes from | check.py / harness |
|---|-----------|---------------------|--------------------|
| 19 | When the deciding comparison is inconclusive (95% CI includes zero, n below two on a side, an asked-for arm not run or not measured) the writer writes `NEEDS-DATA.md` + `needs-data.json` + `NOTES.md ## Send-back`, no report, and ends with `send-back: needs data` | user on F (mcp): "send back to the worker and tell it to collect more data until it's conclusive before writing the full report" | `report_eval.py`: `expected.json` `"expect": "send-back"` with `arms`; checks `needs_data`, `no_report`, `arms_named`, `rule_named`, `notes_send_back`, `needs_keys_resolve`, `last_line`; row fields `send_back`, `send_back_rule` |
| 20 | No writer-made data files: every `numbers.json` file is a study file under `--data`, never under the report dir; aggregates over rows use the `[?k=v]…\|agg` field syntax | INVESTIGATION.md "Writer-made data files" (worker-on cited `report/tally.json`) | `numbers_match_sources` ("is a writer-made data file"); `build.py` refuses to fill such a key |
| 21 | The checker study reports a natural finding rate (cold checker on the checker-off builds, each finding scored right or wrong by hand) apart from the planted catch rate, and check.py's own catches apart from both | user on G: "it's not clear how often the errors naturally come up and whether the 25% extra cost is worth it in normal usage cases" | `report_eval.py --cold <f>`; `gather_natural.py` → `fixtures/checker/data/natural.json`, `mechanical.json`; `planted.json` untouched |
