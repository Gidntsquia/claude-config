# Research for the round-3 golden cards (2026-10-18)

Collected after the user said "you have done insufficient research" and "this is way too dense" (r2). Amazon's memo
formats are excluded. Each line gives the source; what it implies for card 1 follows the arrow.

## How dense a summary should be, and how to get an LLM there

- Chain of Density (Adams et al. 2023, https://arxiv.org/abs/2309.04269): 5 rewrites at a fixed length, each adding
  facts. Human first-place votes by step: 8.3 / 30.8 / 23.0 / 22.5 / 15.5 %. Step 2 won (0.129 entities per token),
  preferred density about 0.15, close to human-written summaries (0.151). Readability fell after step 1-2.
  → Card 1 should carry about as many facts as a person would write, not every fact. Our r2 card is past step 5.
- Nielsen (1997, https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/): a page cut to
  about half the words was 58% more usable; concise + scannable + objective together 124%.
  → Halve card 1's words.
- Two passes: RARR (https://arxiv.org/abs/2210.08726) writes, then checks each claim and edits out what is unsupported;
  STORM (https://arxiv.org/abs/2402.14207) outlines first, then writes; AnalysisBank (https://arxiv.org/abs/2609.00818)
  plans the report as "data signal → analytical move" pairs, not fixed sections.
  → Dense grounded pass, then a concise pass (the user's idea), with the plan built around the one or two findings
  that answer the ask.
- Claim checking: FActScore (https://arxiv.org/abs/2305.14251) splits text into atomic facts and checks each; Proof-
  Carrying Numbers (https://arxiv.org/abs/2509.06902) has the renderer, not the model, check every figure and mark
  failures. → Keep evidence off card 1's prose; `numbers.json` + `check.py` already do the PCN part.
- Prompting (Anthropic best practices and Opus 5 notes, platform.claude.com; OpenAI GPT-5.1 guide; Google Gemini
  strategies): lead with the outcome; tell the model what to do rather than what not to do; give concrete length limits
  ("at most 2 sentences"); positive examples steer format more reliably than rules; "do not pad with filler sections,
  redundant summaries, or boilerplate". Show and Tell (https://arxiv.org/abs/2511.13972): rules plus one example gave the
  most stable control. → The writer gets a short rule list plus one golden card 1 that obeys it exactly.
- Wikipedia "Signs of AI writing": inflated significance, trailing "-ing" clauses, rule of three, "not just X but Y",
  heavy bold, bold-header bullets, formulaic closers. → Matches the user's write-readme tells; `voice` checks some.
- Not found: any study setting word counts per block or figures per screen. Budgets below are design choices to test
  by eye.

## Rules for a short decision card, and reference reports

- ONS "Main points" (https://service-manual.ons.gov.uk/content/writing-for-users/writing-main-points-and-analysis): up to
  six bullets, one point each, under 25 words ("what you can say in one breath"), the figure to remember first, one main
  value per bullet, the period said once in a lead-in. → A "main points" card 1.
- GOV.UK sentence length (https://insidegovuk.blog.gov.uk/2014/08/04/sentence-length-why-25-words-is-our-limit/): at 14
  words average readers understand over 90%, at 43 words under 10%. US Army AR 25-50: main point first, active voice,
  about 15 words per sentence. → Sentences on card 1 average about 15 words, none over 25.
- NN/g: users read 20-28% of a page's words; inverted pyramid; F-pattern (top and left edge, first two words of an item
  carry it); phones punish hard, dense text more than desktop (2016 study, about 30 ms per word slower on hard passages).
  → Each block starts with its key words; the less read, the less there should be.
- Tufte (NASA / "Cognitive Style of PowerPoint"): bullets as "grunts" lose causes and actors, so use full sentences; a
  reassuring headline must not sit above a buried caveat. → Points are full sentences; the caveat that bears on the
  ask stays on card 1.
- Experiment readouts: Statsig's decision framework (one primary metric, guardrails, one of ship / discuss / do not
  ship), Eppo's overview tab (hypothesis, key takeaways, decision), Kohavi (one overall metric, guardrails, a trust check
  first). → One decision, one deciding metric, the trust checks named.
- Reference reports found: Rust compiler weekly perf triage
  (https://github.com/rust-lang/rustc-perf/blob/main/triage/2026/2026-10-11.md: verdict first in 3 plain sentences,
  one small table, one line per change, noise called noise); Mozilla Perfherder regression alert (action and owner up
  front, one table). Not yet shown to the user. The user rejected the first three (GOV.UK organ donation trial, Python
  3.11 What's New, Discord Go to Rust): "I don't like any of them".
- Axios Smart Brevity (headline, one-sentence lede, "Why it matters", "What's next"): only third-party summaries
  could be read; known for dropping context.
