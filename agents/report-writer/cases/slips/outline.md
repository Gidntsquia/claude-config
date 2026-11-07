# Outline

## Recap

You asked for every source in the base context tallied, in raw and Fable-equivalent tokens, and justified by use. Every session starts with {A_total} raw tokens by the audit's four-character count ({A_measured} at the billed ratio), {fe_turn} a turn, and the built-in tool schemas are {p_tools} of it, while the logs back only {a_used} with a session count. The ending goes back to the reference session's first request and says the base context is tallied, most of it is text you never wrote, and most of it has no usage count to justify it.

## Sections

| # | heading | ask clause | settles with | words |
|---|---|---|---|---|
| 1 | Text you never wrote filled the turn | in terms of how many tokens they take up | {A_total} {fe_turn} | 200 |
| 2 | 🧮 What fills the base context every turn? | I want every source tallied up | {p_tools} | 150 |
| 3 | 🔭 How much of it do the logs back? | I also want each source justified as to why it's important | {a_used} {a_notmeasured} | 160 |
| 4 | ⏱️ What waits until it is called? | MCP servers, skills, etc. | {B_total} {B_unused} | 140 |
| 5 | 🔀 What do the named projects add? | audit every component of my context | {eval_A} {asst_B} | 150 |
| 6 | 🔁 Back to that first request | clean up the global base context of my Claude code | {A_measured} | 130 |

## Left out

- Section C, configured but not loaded — costs nothing per turn
- the frequently used projects beyond the named three — not named in the ask
- MCP per-tool detail rows — already inside their server rows
- per-row justification text — a description, not usage evidence
