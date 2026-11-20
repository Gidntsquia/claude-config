# AI writing tells

A list of the habits that make a reader say "an AI wrote this" and stop reading. Each entry has a name, why a
reader hears AI in it, one real example (from the round 4 fixture reports `agents/evals/report-writer/golden/r4/A|B/report.md`
where one exists, otherwise from the research named at the end), and the fix. Any AI writing for this repo reads
this list before it writes and again before it hands the text over. The checks marked `check.py` are caught by
`agents/evals/report-writer/check.py --prose` (`ai_tells` check); the rest need a human read.

## Found by the user (2026-10-21)

1. **Fragments and one-word answers** (`check.py`: sentence under four words). A sentence with no verb, or a
   one-word reply to the heading's question, is a drum hit. People talking do not answer "Yes." and move on; they say
   what the yes is. Example (r4 A): "One generation, then." / "Yes. The run paired with our generation…" / "Faster."
   (r4 B): "Plenty." / "No. Long runs are worse." Fix: fold the answer into the first full sentence. "The GPU did the
   work: the paired run logged 61,424 speculated battles."
2. **Narrating the text itself** (`check.py`: "Here is", "Here are", "Call it", "The rest of this"). Sentences about
   the document instead of about the thing. A person telling you a story does not announce the story. Example (r4 B):
   "Here is one of the waits." (r4 A): "The rest of this is a search for the second." / "Read that twice." Fix: delete
   the sentence and start with the event. "The first plain run that morning hit generation 7 at 11:55 and took
   12.84 s."
3. **Aphorisms and generalities without a number**. A tidy line that would be true of any study: it sounds wise and
   carries nothing. Example (r4 A): "Busy is a cost, though." (r4 B): "Busy and useful are different things, and a
   binned battle is work for nothing." / "It gets worse before it gets better." Fix: replace the maxim with the
   measurement that made you think it. "36,514 of those battles were thrown away, so most of the busy time bought
   nothing."
4. **Run IDs as the subject of a sentence** (`check.py`: `r9[a-z0-9-]*` at sentence start). A code name doing a
   person's job: "r9pre-ab-tail-1 speculated 65,127 battles" reads like a log line. Example (r4 B): "r9pre-ab-tail-1
   speculated 65,127 battles…" (r4 A): "r9pre-ab-default-3, index 7, Saturday 12:08 ET, plain code, took 12.59 s".
   Fix: say what the run is, with the ID in parentheses or a footnote the first time. "The third plain run that morning
   (r9pre-ab-default-3) speculated…"

## From the research

5. **"X, then." openers and other stagey beats** (`check.py`: ", then." at sentence end). "One generation, then."
   is a line from a stage play, not from a colleague. Fix: say the thing. "Take generation 7 of the third plain run."
6. **"Not X but Y", "X, not Y", "Y rather than X", "not only X but also Y"** (`check.py`: "rather than", "not only";
   the contrast forms are already in the `voice` check). The contrast frame fakes depth by denying something nobody
   claimed. Example (r4 A): "A dead run's numbers are a hint rather than a result." Fix: state the positive. "A dead
   run's numbers are a hint."
7. **Rule of three** (`check.py`: three parallel items joined by commas and "and" in one sentence, already in
   `voice_prose`). Three-beat lists, three-beat rhythms, three short sentences in a row. Example (r4 B): "Built,
   correct, slower by 1.03 s a warm generation." Fix: two items, or four, or one sentence each with its number.
8. **Inflated words**: pivotal, crucial, robust, delve, tapestry, landscape, showcase, leverage, seamless,
   "serves as" for "is", testament, navigate, elevate, harness (`check.py`: `voice_prose`). Fix: the plain word.
9. **Brochure tone and inflated significance**: "a pivotal moment", "this matters because", "this guide walks you
   through", "a game-changer". Fix: say what changed and by how much.
10. **Summary endings and signposts**: "In conclusion", "In summary", "To sum up", "Overall" (`check.py`: "In
    conclusion"). Example (r4 A): "So the thing you asked for is built and it is correct, and it is slower." as a
    wrap-up after the numbers already said it. Fix: end on the last fact, or on the microcosm's after numbers.
11. **"Despite challenges" closes and hedge sandwiches**: "While X is important, it is worth noting Y." Fix: one
    claim, one number, no cushion.
12. **Vague attribution**: "experts say", "it is widely known", "studies show". Fix: name the file, run or person.
13. **Uniform sentence length**. Every sentence 12 to 18 words, every paragraph three sentences. Reads like a
    metronome. Fix: let one sentence run long with the detail and the next be short because it has one fact.
14. **Bold labels, title case, bullets with bold lead-ins, emoji as decoration, tables where prose would do**
    (`check.py`: bold in `voice_prose`). Fix: prose, sentence case, one emoji per heading at most (style.md).
15. **Em dashes** (`check.py`: `voice`). Fix: a comma, a full stop or parentheses.
16. **Didactic asides and forced wit**: "Read that twice.", "So the filler did fill.", "Note that…", a joke that
    explains itself. Example (r4 A): both of those. Fix: cut; let the number do the work.
17. **Parenthetical asides as a habit**. One per report is fine; one per paragraph is a tic. Example (r4 A): "(Warm:
    generation 4 onward, once the pool has filled.)" right after "(0.46 s plain, 0.53 s with the fix)". Fix: make it
    a sentence or drop it.
18. **Elegant variation**: swapping synonyms to avoid repeating a word (the chip, the GPU, the card, the device).
    Fix: call a thing one name and keep it.
19. **Stock openers and closers**: "In today's world", "Let's dive in", "Here's the thing", "At the end of the day",
    "I hope this helps". Fix: delete.
20. **Emphasis fillers**: actually, really, exactly, simply, just, clearly, notably, at all (`check.py`: `voice`).
    Fix: delete the word.
21. **Colon taglines and one-word verdicts after a colon**: "Deterministic: yes." (`check.py`: `voice`). Fix: a
    sentence.
22. **Semicolon chains** (`check.py`: `voice`). Fix: two sentences.
23. **Soulless perfect grammar with no first-hand detail**: nothing that shows a person was there (the time of day,
    what the log looked like, what you tried and gave up on). Fix: one concrete detail per section from the data,
    with its source.
24. **Excessive hedging**: "it may be the case that", "potentially", "to some extent", stacked. Fix: say what the
    number supports, and name the one thing you do not know.
25. **Questions as section headings answered with a verdict word** ("Did it work? Yes."). A heading may ask; the
    first sentence under it answers in full.

## How to add one

Append a numbered entry: the name in bold, why a reader hears AI in it, one real example (quote the file), and the
fix. If a regex can catch it, add the pattern to `AI_TELLS` in `agents/evals/report-writer/check.py` and run
`python3 -I check.py golden/r4/A --prose` to see it fire. Mirror the change to `wiki/AI-Tells.md`.

Sources: Wikipedia "Signs of AI writing"; Graphite's 2026 em-dash study (Fast Company); The Conversation (2026) on
"not X, but Y" and the rule of three; DEV (2026) on three-beat rhythms and hedge sandwiches; PCWorld's self-audit on
parentheticals; Riedman on "In conclusion" and hedging; Surfer and Writesonic on uniform sentence length and stock
openers; `skills/write-readme/references/style.md` for the user's own flagged sentences.
