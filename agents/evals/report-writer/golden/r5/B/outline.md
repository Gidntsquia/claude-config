# Outline

Written after the golden (2026-11-06) so `check.py --prose`'s focus group can read it. The golden predates the outline
step; these rows are the plan its thread already follows.

## Recap

You asked whether number 4 removed unneeded wait times, and generation 7 of the first plain run is the unit that shows it. The fix made a warm generation slower by {tail_diff}, because the wait moved into the tail instead of leaving. So number 4 is built and gets the right answers, and it stays off.

## Sections

| # | heading | ask clause | settles with | words |
|---|---|---|---|---|
| 1 | The wait that cost a second | removing unneeded wait times | {gw_def1_g7} {tail_diff} | 260 |
| 2 | ⏱️ Where did the extra second land? | removing unneeded wait times | {pf_tail_g7_tail} {pf_def_g7_tail} | 160 |
| 3 | 🧮 How much work did the idle workers do? | removing unneeded wait times | {tl1_speculated} {tl1_discard_pct} | 110 |
| 4 | 🔭 Is it any better on a long run? | number 4 | {gw_fulltail_pre_g79} | 110 |
| 5 | 🔀 Why trust the morning over the afternoon? | number 4 | {w_r9tail_runsall} {w_r9def_runsall} | 130 |
| 6 | 🧪 Did the other shapes do any better? | removing unneeded wait times | {w_tailv2} | 100 |
| 7 | ✅ Were the answers right? | number 4 | {det_tail_ckpts} {verify_tail} | 60 |
| 8 | 🔁 Back to that generation | I thought number 4 was one of the things I originally requested | {gw_tail1_g7} {tail_diff} | 160 |

## Left out

- certain feed — a side arm the ask did not name
- compact state — the round's other change, not number 4
