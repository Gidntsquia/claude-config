# NOTES

## Length

short — the ask is about one thing (the base context) and one tally decides it. The B section and the named projects are parts of that same tally, so four middle sections, budgets summing to 600.

## Visuals

| section | block or none | why |
|---|---|---|
| 🧮 What fills the base context every turn? | ::table | seven sources, each with a raw count and a per-turn FE cost |
| 🔭 How much of it do the logs back? | ::split | Section A broken into called, unused and not measured |
| ⏱️ What waits until it is called? | ::split | Section B broken into called and not called |
| 🔀 What do the named projects add? | ::table | three named projects across four quantities |

## Openings

pick: moment — the audit run at 05:16 ET on 5 November and its reference session give a time, an identifier and a billed figure
runner-up: person — the planner session holds the ask, but the data folder has no note of what you were doing while the audit ran
runner-up: break — no run in the data failed, so there is no exit code to open on

The last two ledger lines took `log-line` and `expected-vs-got`.

1. "At 05:16 ET on 5 November the audit opened one old session and read it." — kept, but the second clause is filler
2. "The audit that wrote these numbers ran on Jaxon-PC at 05:16 ET on 5 November, and it took the text Claude Code keeps off disk from one old session log." — kept
3. "Here is the session the audit borrowed its text from." — struck, 2 (narrating the text)
4. "It all started with one session, then." — struck, 5 and 3
5. "One session, one request, one bill." — struck, 1 and 7
6. "A Slay the Spire session (44904a3d) carried 103,524 characters and that is the whole story." — struck, 4 (ID as subject) and 9
7. "The audit simply borrowed the system prompt from an old session at 05:16 ET." — struck, 20 (simply)
8. "In the early hours of 5 November, a pivotal log was opened by the audit." — struck, 8 (pivotal) and 9
9. "Before you typed a word in that session, its first request had already gone out at 103,524 characters." — struck, no time of the audit run and the figure typed before its key; kept for the second paragraph's idea
10. "On 5 November at 05:16 ET, not on the day you asked, the audit read its ruler from another project." — struck, 6 (not X frame)

Picked 2: it names the clock time, the machine and what the audit was doing, and the next sentence can give the session's identifier and figure.

## Focus

| heading | clause | focus (checker) | action taken |
|---|---|---|---|
| 🧮 What fills the base context every turn? | I want every source tallied up | advances | kept |
| 🔭 How much of it do the logs back? | I also want each source justified as to why it's important | advances | kept |
| ⏱️ What waits until it is called? | MCP servers, skills, etc. | advances | kept |
| 🔀 What do the named projects add? | audit every component of my context | advances | kept |

## Self-review

| before | after | tell |
|---|---|---|
| You use Bash and Read in nearly every session, and still the study never tallied tool calls, so their use is not measured. | Tool calls are in the logs, but the study never tallied them, so the tools' use is not measured. | claim the data does not hold (no tool-use count exists) |
| I cannot justify the grey part from use | I cannot justify the not-measured part from use | one name per thing (18); the split's colour is not known |
| {asst_B} on demand, most of it the schemas of its own MCP server | {asst_B} on demand, nearly half of it the schemas of its own MCP server | wrong claim, 3,977 of 8,984 is under half |
| at its ratio the base context alone is {A_measured} of every session's turns | at that session's ratio the base context comes to {A_measured} on every turn of every session | grammar |
| I take it as typical because its directory holds no project files, so what it carried at the start is the same base context every session on this machine carries. | I take it as typical because that first turn carried the base context every session here carries, plus one project AGENTS.md of {sts_A}. | claim the data contradicts (checker) |
| at that session's ratio the base context comes to {A_measured} | at that session's ratio the base context's {A_total} raw tokens come to {A_measured} | two sizes not reconciled (checker recap) |
| One tool fills most of the first row. | One tool fills most of the base context's first row. | thread names the ask's subject |
| more than all the rows under it put together | more than every other source in the base context outside the tools row | thread names the ask's subject |
| Most of it is Claude Code's own text. | Most of the base context is Claude Code's own text. | thread names the ask's subject |
| the Fable 5.1 cache-read price in the study's own unit | (cut, rule moved into 🧮 without the version number) | digit typed in prose |
| for skills, agents and MCP tools | for skills and agents it can see invoked in a log | 7 (rule of three) |
| The Artifact tool, which "renders an HTML file as an Artifact: a web page hosted on claude.ai", has a schema of {artifact_raw} by itself, | The Artifact tool "renders an HTML file as an Artifact: a web page hosted on claude.ai". Its schema is {artifact_raw} by itself, | 46-word sentence (13) |
| that one request came to one per {ref_ratio} | that one request (n = [[1]]) came to one per {ref_ratio} | check.py card1: the But states n |
| {A_total} raw tokens (and five like it) | {A_total} by the raw count, {eval_A} raw, … | unit printed twice on the card |

## Checker

| loop | key or claim | severity | right or wrong | what changed | status |
|---|---|---|---|---|---|
| 1 | asst_mcp, "most of it the schemas" | medium | right | already "nearly half" after self-review | fixed |
| 1 | ref_chars, "holds no project files" | medium | right | opening now names the project AGENTS.md ({sts_A}) | fixed |
| 1 | "You use Bash and Read in nearly every session" | low | right | already cut in self-review | fixed |
| 1 | recap / A_measured | high | right | recap rewritten to give both rulers, ending names {A_total} beside {A_measured}; state words unchanged, no second read | fixed |

checker: loops=1 raised=4 fixed=4 open=0 tokens=577639 seconds=124

## Recap

You asked for every source in the base context tallied, in raw and Fable-equivalent tokens, and justified by use. Every session starts with {A_total} raw tokens by the audit's four-character count ({A_measured} at the billed ratio), {fe_turn} a turn, and the built-in tool schemas are {p_tools} of it, while the logs back only {a_used} with a session count. The ending goes back to the reference session's first request and says the base context is tallied, most of it is text you never wrote, and most of it has no usage count to justify it.
