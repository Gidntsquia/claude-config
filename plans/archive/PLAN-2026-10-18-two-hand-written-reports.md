# Spec: Two hand-written reports on the fixture study; the user picks one or sends it back

## Ask
"Replan based on plans/EVAL.md". "The report shouldn't match industry stuff... It should match something that actually makes sense to me."
User's answers: "My README style, for a study"; past report "lacked focus"; "Say what happened to what I asked for"; "No editing from me. Worker writes 2 completed reports with different approaches, and I will see if either actually looks good"; hand-written from fixture data; "Worker chooses two"; thread "Did the thing I asked for work"; "Phone pngs should be delivered to the evaluator".
On writing: Brooker is "the best by far... It has a hook and then brings that to a point"; "variance is a key component; if it's too predictable, it's not that interesting. AIs can also too rigidly follow rules"; "A bad opening makes me not want to read the rest. But the whole report is important"; "I personally am a fan of the 'microcosmic example' strategy for introductions"; "Try to avoid the report sounding like it was written by AI".
Princeton synthesis accepted as the backbone: motive (puzzle, set up with a "But"), thesis drives structure, orienting just enough, evidence analyzed; microcosm = one real generation, quote still at top; ban all four AI tells; one question per section answered with one number; microcosm stays in view and returns at the end; "Backbone + the two reports must differ in the parts the profile leaves open"; length "whatever the puzzle needs".

## What to build
Two complete reports on the fixture study (`agents/evals/report-writer/fixture/`, GPU round 9), written by hand by the worker. Each answers one puzzle: the user asked for the wait-time fix ("number 4"), it should have made rounds faster, it made them slower; where did the time go and what happens to the ask now. Same backbone, different everywhere else. The evaluator shows the phone PNGs and asks A, B or neither.

## Facts
- Repo: ask quote in `fixture/plans/PLAN.md` `## Ask`: "I thought number 4 was one of the things I originally requested—I.e, removing unneeded wait times. I want it". "Number 4" = round 8 rec 4 (start the next round's battles while the GPU waits). Numbers with file/field in `agents/evals/report-writer/out/build/report/numbers.json`; per-generation walls (`genWalls`) and `tailShare` per run in `fixture/data/runs-all.json`. Tail speculation 13.63 s/gen vs default 12.60 (n=3 each), tail+certain 13.20, tail v2 9.1 (one run). `TRAPS.md` lists planted conflicts; `check.py` checks numbers and traps. Voice: `skills/write-readme/references/style.md`.
- Web (2026-10-18): Princeton lexicon (tortoise.princeton.edu/lexicon) and Walk/Harvey "Motivating Moves": motive = the genuine puzzle the thesis answers, "the main business of your introductory paragraphs", "usually introduced by... 'But'"; "thesis should determine structure"; Tortoise 2022: a puzzle narrows scope, small close readings build the argument. Microcosmic opening = one small, real, representative case first; it returns at the end. Wikipedia "Signs of AI writing": AI vocabulary, inflated significance, brochure tone, rule-of-three, "not X but Y", bold/emoji decoration, summary endings.
- Kept examples (worker reads all first): Brooker "Meet Alice" brooker.co.za/blog/2026/06/19/waiting.html; What If what-if.xkcd.com/1/ and /3/; Spolsky "Things You Should Never Do, Part I"; Wait But Why "The Fermi Paradox"; Graham "Write Like You Talk"; Paterson "Async Python is not faster"; Muratori "Clean Code, Horrible Performance". Not to imitate: cocky, dense, or AI-sounding pieces.

## Requirements
1. (user) No report-writer/report-checker run; the three agent files unchanged. Worker writes both reports after reading the kept examples.
2. (user) Top: the ask quoted verbatim with where it was said; "number 4" explained in ≤6 words outside the quote.
3. (user) Opening: one real, typical generation from `runs-all.json` (run and index named) with its wall time and tail share; then the "But": the fix fills that wait and the round got slower (both means, n). No length limit; judged by whether it pulls.
4. (user) One puzzle, one thread: only what the puzzle needs. Other arms one line each, only where they change the answer. No caveats section.
5. (user) Middle: each section asks the next question and settles it with one number from `numbers.json`; the microcosm generation stays the running example; unknowns are admitted where they arise; every number is explained in plain words.
6. (user) Ending: the microcosm returns with its after numbers, then the state of the ask (built, slower, off for now, what to try). No ship/no-ship word, no summary.
7. (user) Each key term (tail, warm gen, speculation, certain feed, compact state) explained once in plain words at first use. Traps that bear on the fix stated plainly in the body.
8. (user) Voice: `style.md` plus bans: rule-of-three, "not X but Y"/"X, not Y", inflated words (pivotal, crucial, robust, delve, showcase, serves as), brochure tone, summary endings, uniform sentence length, bold beyond one IMPORTANT, em dashes.
9. (user) A and B share 2–8 and differ in pacing, length, tone, humor, question order, chart or not. Labelled in the evaluator's message, not in the report.
10. (default) Every figure traces to `numbers.json` or fixture data; `check.py` passes on both. Sources named once in a short line or 📚 section.
11. (user) Each report rendered to 390 css px PNGs, one per ~844 px screenful, saved with `report.md` under `agents/evals/report-writer/golden/r4/<A|B>/`; the evaluator shows them.
12. (user) Worker ends with `plans/WORKER_NOTES.md` "For the evaluator": PNG paths, labels, one question (A, B, neither, with notes). On A or B the next round makes it golden and rewrites `RUBRIC.md` from it; on neither, back to the planner.
13. (default) Nothing committed.

## Constraints
Repo stack: bash, Python via uv, Node/playwright (`cards.mjs`), Markdown. Reuse an existing renderer. The backbone is not a template: where it is silent the worker chooses, and A and B choose differently.

## Acceptance criteria
- [ ] R1: no agent runs in logs; sha256 of agent files unchanged.
- [ ] R2, R3: first screenful shows quote, ≤6-word label, named generation with numbers, the "But" with means and n.
- [ ] R4–R6: each section has one number; the microcosm run/index appears in opening, middle and ending; other arms ≤1 line; last paragraph has after numbers and the state of the ask.
- [ ] R7, R8: terms defined at first use; grep for banned phrases, em dashes, triplets, bold finds nothing.
- [ ] R9: A and B visibly differ side by side.
- [ ] R10: `check.py` passes on both.
- [ ] R11, R12: PNGs under `golden/r4/A` and `B`; WORKER_NOTES has paths, labels, the one question.
