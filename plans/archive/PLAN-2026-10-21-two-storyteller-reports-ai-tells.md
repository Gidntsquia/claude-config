# Spec: Two reports on the fixture study, written in a storyteller's voice, with an AI-tells list the user keeps growing

## Ask
"Replan based on plans/EVAL.md". EVAL verdict: both r4 reports "read as AI-written from the first line, so the user stops reading"; "the planner should rethink how to make the writing sound human, not just patch these tells". User on A: "Sounds like AI wrote it right from the get go. 'one generation, then' is not something a human would write. Investigate". On B: "I can't even get past the first sentence. 'Here is one fo teh waits' is clearly an AI written sentence, and makes me not want to read any further".
This round's answers, verbatim:
- Base form: "Option 1 [a message to a coworker] sounds immediately AI, so that's out. I want to keep the essay backbone, but I want the AI to pay much closer attention to that first sentence since it's the most important. Do additional research into how to make an AI output sound less like AI text"
- First sentence: "Option 4 [still a small story]; keep the research and ideas we had before. The microcosmic example and the Princeton research was good. We simply need to bring the AI writer to the next level. I want to try getting the AI to turn into a professional writer persona-- I've heard that can yield better results"
- Tells (all four picked): fragments and one-word answers; narrating the text itself; aphorisms and generalities; run IDs as the subject. "Do additional research to find more of these. I also want you to write down somewhere what these tells are. I want to create a list that I can continue expanding until we have all the AI tells on it, so that future AIs can avoid them"
- Check: "Full report, pick as before"
- Tells list lives in: "Option 2 [docs/ai-tells.md] and option 3 [wiki page]. make sure the wiki is stored in this folder in a gitignored subfolder"
- Persona: "I want a fiction/non-fiction writer. I want someone who is good at writing interesting stories. I'm not favorable to engineering/science writers since they tend to be a bit dry"
- First line: "Option 1 [draft ten, cut, pick] and option 2 [write it last]"
- Checker: "Add the mechanical ones, self-review the rest"
Carried from the archived plan (PLAN-2026-10-18-two-hand-written-reports.md): everything the user said there still holds: README-style for a study, "Say what happened to what I asked for", Brooker "has a hook and then brings that to a point", "variance is a key component", "microcosmic example" intros, Princeton backbone (motive with a "But", thesis drives structure), one puzzle one thread, phone PNGs to the evaluator, two reports that differ where the backbone is silent.

## What to build
Two complete reports on the fixture study (`agents/evals/report-writer/fixture/`, GPU round 9), hand-written by the worker in the voice of a storytelling writer, same puzzle as last round (the user asked for "number 4", it should have made rounds faster, it made them slower, where did the second go, what happens to the ask). Before writing, the worker creates `docs/ai-tells.md`, a list of AI writing tells with examples from the r4 reports and the fix for each, mirrors it as a wiki page in the gitignored `wiki/` clone, adds the regex-checkable tells to `check.py`, and writes the opening sentence last from ten candidates. The evaluator shows the phone PNGs and asks A, B or neither.

## Facts
- `/wiki/` is already in `.gitignore` ("GitHub wiki clone (its own repo)") and a `wiki/` directory exists in the repo root; the README links `https://github.com/Gidntsquia/claude-config/wiki`. No `docs/` directory exists yet.
- Last round's reports: `agents/evals/report-writer/golden/r4/A|B/report.md` (+ `source.md`, built by `golden/make_r4.py`, checked by `check.py --prose`). A opens "One generation, then."; B opens "Here is one of the waits."
- Research (2026-10-21, web): Wikipedia "Signs of AI writing" names: inflated significance ("pivotal moment"), brochure tone, vague attribution, "despite challenges" closes, AI vocabulary (delve, tapestry, pivotal), "serves as" instead of "is", "not only X but also Y", "not X but Y", "Y rather than X", rule of three, title case, bold, bullets with bold labels, emoji as decoration, tables where prose fits, section summaries, didactic asides, elegant variation (synonym swapping). Graphite study (Fast Company, 2026): em dashes have nearly vanished from Claude Opus 5.5 output; stock phrases "this matters because", "this guide walks"; more commas, longer words, formulaic closes. The Conversation (2026): "not X, but Y" and rule of three as a shared house style. DEV (2026): three-beat rhythms, "hedge sandwiches" ("While X is important, it is worth noting Y"), forced wit. PCWorld self-audit: parenthetical asides the most flagged habit. Riedman: soulless perfect grammar, "In conclusion" signposts, excessive hedging. Surfer/Writesonic: uniform sentence length, neutral tone, no first-hand detail, stock openers.
- Persona research: Xiao et al. 2026 (arXiv 2605.29420): role prompts raise perceived expertise and structure and lower readability and directness; USC study (secondhand): personas help tone and style tasks. Takeaway: a persona plus explicit style constraints, not a job title alone.
- Unverified: Riedman tells 6-10 (paywalled); Wikipedia page read to 100 k chars of 255 k.

## Requirements
1. (user) No report-writer/report-checker run; `agents/report-writer.md`, `report-checker.md`, `worker.md` unchanged.
2. (user) `docs/ai-tells.md`: one tell per entry with a name, why a reader hears AI in it, one real example (from r4 A/B where one exists, else from the research), and the fix. Must include the user's four (fragments and one-word answers; sentences about the text itself such as "Here is", "Call it", "The rest of this is"; aphorisms and generalities without a number; run IDs as sentence subjects), the research list in Facts, and the earlier bans (rule of three, "not X but Y"/"X, not Y"/"Y rather than X", inflated words, brochure tone, summary endings, uniform sentence length, bold, em dashes). Ends with a short "How to add one" line so the user can keep extending it. Linked from the README Documentation list.
3. (user) The same list as a wiki page `AI-Tells.md` in the `wiki/` clone (gitignored, already present; pull it first; if the clone is missing, clone `https://github.com/Gidntsquia/claude-config.wiki.git` into `wiki/`). Not pushed.
4. (user) Persona: before writing, the worker writes a one-paragraph bio of a storytelling writer (fiction and narrative non-fiction, known for openings that make a reader keep going, not an engineer or science writer) in `WORKER_NOTES.md`, names two or three real writers it draws on, and writes both reports as that writer explaining this study to the user. Default: A and B are the same persona; they differ in pacing, length, humour, question order, chart or not.
5. (user) Opening written last: the worker finishes the whole thread first, then writes ten candidate first sentences for the microcosm (a named, typical generation from `runs-all.json`, told as a plain event), strikes any that hit `docs/ai-tells.md` or that a person would not say aloud, picks one, and records all ten with the reason for each strike in `WORKER_NOTES.md`.
6. (user, carried) Top: the ask quoted verbatim with where it was said; "number 4" explained in ≤6 words outside the quote. Then the microcosm, then the "But": the fix fills the wait and the round got slower (both means, n).
7. (user, carried) One puzzle, one thread; each section asks the next question and settles it with one number from `numbers.json`; terms (tail, warm, speculation, certain feed, compact state) explained once at first use; traps that bear on the fix stated in the body; other arms one line each; no caveats section; ending returns to the microcosm with its after numbers and the state of the ask; no ship word, no summary.
8. (user) Runs are referred to as what they are ("the third plain run that morning"), with the run ID in parentheses or a footnote the first time, never as a sentence subject.
9. (user) `check.py --prose` gains regex checks for the mechanical tells: sentences under four words, sentences starting "Here is/are", "X, then.", "Call it", "The rest of this", a run ID (`r9[a-z0-9-]*`) at sentence start, "rather than", "not only", "In conclusion", three parallel items joined by commas and "and" in one sentence. Both reports pass. The r4 A and B reports must fail the new checks (proof they catch what the user saw).
10. (user) Self-review: after the opening is chosen, the worker reads every sentence against the full `docs/ai-tells.md` and logs each change (before, after, tell name) in `WORKER_NOTES.md`.
11. (user, carried) Every figure traces to `numbers.json` or fixture data; sources named once in a short line. Each report rendered to 390 css px PNGs under `agents/evals/report-writer/golden/r5/<A|B>/` with `report.md`; the evaluator shows them on the phone and asks one question: A, B or neither, with notes.
12. (default) Nothing committed. Labels for A and B live in the evaluator's message, not in the reports.

## Constraints
Repo stack: bash, Python via uv/`python3 -I`, Node/playwright (`cards.mjs`), Markdown; reuse `make_r4.py` as `make_r5.py`. Voice: `skills/write-readme/references/style.md` plus `docs/ai-tells.md`. The backbone is a structure, not a template: where it is silent the persona decides, and A and B decide differently.

## Acceptance criteria
- [ ] R1: no agent runs in the transcript; sha256 of the three agent files unchanged.
- [ ] R2, R3: `docs/ai-tells.md` exists with every listed tell, an example and a fix each; `wiki/AI-Tells.md` has the same content; README links it; `git status` shows `wiki/` untracked by ignore.
- [ ] R4: WORKER_NOTES has the persona bio with named writers.
- [ ] R5: WORKER_NOTES lists ten openings, strikes with reasons, and the pick; the pick is the report's first sentence after the label.
- [ ] R6, R7: first screenful shows quote, label, microcosm, "But" with means and n; each section settles one number; the microcosm run/index appears in opening, middle and ending.
- [ ] R8: grep finds no sentence beginning with a run ID.
- [ ] R9: `check.py --prose` passes on r5 A and B and fails on r4 A and B with the new checks named in the output.
- [ ] R10: WORKER_NOTES has the self-review change log.
- [ ] R11: PNGs under `golden/r5/A` and `B`; WORKER_NOTES has paths, labels and the one question; the user reads past the first sentence and picks A, B or neither.
- [ ] R12: HEAD unchanged.
