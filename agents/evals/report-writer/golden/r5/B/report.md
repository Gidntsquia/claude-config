# The wait that cost a second

> I thought number 4 was one of the things I originally requested—I.e, removing unneeded wait times. I want it
~ you, in the round 9 planner session (fixture `plans/PLAN.md`, `## Ask`)

[[Number 4]] was next round's battles.

A little before 11:55 on Saturday morning the GPU was partway through generation [[7]] of that day's first plain run (r9pre-ab-default-1), and most of its workers had nothing to do. That generation took {gw_def1_g7}.

Across the run, {ts_default1} of the GPU's time was tail, the stretch after the quick workers run out of battles while the chip waits for the slowest one, so about {tail_s_def1_g7} of those {gw_def1_g7} were waiting.

[[Number 4]] gives the idle workers something to do: each picks a team likely to survive the cut and fights its next-round battles early. The code calls this speculation, and the early battle goes into a memo if the team survives and into the bin if it is cut.

But the same generation with the fix on (r9pre-ab-tail-1) took {gw_tail1_g7}. Three runs a side that morning, a warm generation (generation [[4]] onward, once the pool is full) went from {w_r9pre_def_mean} to {w_r9pre_tail_mean}, n = {w_r9pre_def_n}.

---

The fix cost {tail_diff} a generation. You asked for less waiting and the chip found a way to wait more.

## ⏱️ Where did the extra second land?

It landed in the tail, the one place it was supposed to leave. The morning runs had no profiler on, so this comes from the afternoon build of the same fix, where it was.

In the afternoon's plain run (r9-ab-default-1), generation [[7]] spent {pf_def_g7_kernel} in the main battle kernel and {pf_def_g7_tail} in the tail. With the fix on (r9-ab-tail-1), the same generation spent {pf_tail_g7_kernel} in the kernel and {pf_tail_g7_tail} in the tail.

The main battles shrank by about three seconds, because some had already been fought. The tail grew by a second and a half, and over the whole afternoon run its share went from {ts_r9def_runsall} to {ts_r9tail_runsall}.

Why the tail grows is the one thing the files do not say. The log shows speculation stopping when the main battles end, so my guess is memo traffic and ranking work landing in the tail window, and the profiler's buckets are too coarse to confirm it.

## 🧮 How much work did the idle workers do?

A lot of it, and most of it for teams that were about to be cut. The run with the fix on that was paired with our generation [[7]] (r9pre-ab-tail-1) fought {tl1_speculated} battles early. The team behind {tl1_discard_pct} of them did not survive the cut, so those battles went in the bin. The next round got {tl1_served} battles from the memo, {tl1_served_pct} of its pool of {tl1_pool}.

So the chip was busy where it used to sit, and more than half of that busy time went to battles nobody needed. The memo paid back one battle in eight and the bin took the rest.

## 🔭 Is it any better on a long run?

A long run makes it far worse. The one long run with the fix on (r9pre-full-tail) was taking {gw_fulltail_pre_g79} a generation by generation [[79]] and died at [[80]] of [[100]] (exit [[1]]). The plain 100-generation run did generation [[79]] in {gw_full100def_g79}. A run that died is a hint and no more, and the hint is that the cost grows with the pool.

The 40-generation standard run with the fix, full-tail-1, is not run: it exited [[1]] at generation {ft_gens} of {ft_planned} when the sidecar lost the GPU lock. So a full standard run with the fix on is not measured, and the plan's ship test wants that number.

## 🔀 Why trust the morning over the afternoon?

Because the morning has three runs a side and the afternoon has one. That afternoon pair came out {w_r9tail_runsall} with the fix against {w_r9def_runsall} without (n = {w_r9_n}), which looks faster, and I do not know what changed between the 11:53 fork and the 14:05 build. One run each decides nothing.

The files for that afternoon run also quarrel. The summary file `runs.json` has r9-ab-default-1 at {w_r9def_runsjson} with a tail share of {ts_r9def_runsjson}, which are the morning's numbers under the afternoon's name.

The lit fork's `evidence-profile.json` has the tail share at {ts_r9def_lit}, by a different ruler (time after half the main battles ended). That conflict stays on the table, because I have no reason to trust one file over the other.

## 🧪 Did the other shapes do any better?

None of them did enough to change the answer. The certain feed, which pushes battles for teams already proven to survive into the running kernel through a queue, came out at {w_r9pre_cert_mean}, {cert_diff} slower than plain (n = {w_r9pre_cert_n}).

Tail v2, the same speculation with the trigger at a quarter of the workers idle instead of half, came out at {w_tailv2} in its only run (n = {w_tailv2_n}). One run with nothing beside it leaves that number unproven, and it is also the only number in this study that points the way you wanted.

## ✅ Were the answers right?

They were right, and the five-generation checkpoints with the fix on matched the plain path, {det_tail_ckpts} of [[5]], and the 3v3 verify pass agreed with the CPU on {verify_tail} of winners. The fix lost time and nothing else.

## 🔁 Back to that generation

Generation [[7]] of the first plain run took {gw_def1_g7} with the wait in it and {gw_tail1_g7} with the wait filled. The generation after it went from {gw_def1_g8} to {gw_tail1_g8}. About {tail_s_def1_g7} of waiting was there to be won back, and none of it came back.

So the ask is built, it gets the right answers, and it is slower by {tail_diff} a warm generation, with the long run saying the slope is the real problem, so it stays off and the plain path is as it was.

Compact state, the other change from this round (battle state kept on the chip instead of in slow memory), is its own {stack_diff} and is unaffected.

If you want the wait back, run tail v2 three a side against plain, then profile the 11:53 code so the tail has a bucket to blame, then run one full standard run of each.

📚 `fixture/data/runs-all.json` (walls, tail shares, tail logs), `runs/r9-ab-*/gpu-profile.json`, `runs.json`, `lit/evidence-profile.json`, `full/full-tail-1.json`, `ab-tailv2.json`, `det-r9.txt`, `tail/verify3v3-tail.log`. Every figure is keyed in `numbers.json` and checked by `check.py --prose`.

::checker off
