# Filled the wait, lost a second

> I thought number 4 was one of the things I originally requested—I.e, removing unneeded wait times. I want it
~ you, in the round 9 planner session (fixture `plans/PLAN.md`, `## Ask`)

[[Number 4]] was "start next round's battles during the wait".

Here is one of the waits. r9pre-ab-default-1, [[index 7]], the first plain run on Saturday morning, 11:53 ET, took {gw_def1_g7}. Across that run {ts_default1} of GPU time was tail, the slack at the end of a launch: battles finish unevenly, the quick workers go idle, and the chip mostly sits until the slowest battle lands. Call it {tail_s_def1_g7} of this generation spent waiting.

[[Number 4]] puts that idle time to use: workers with nothing to do start next round's battles for teams likely to survive the cut. That is speculation, done early, kept as a memo hit if the team survives, binned if not.

But the same generation with the fix on, in r9pre-ab-tail-1, took {gw_tail1_g7}. Over the morning's A/B, three runs a side, a warm generation (generation [[4]] onward, once the pool is full) went from {w_r9pre_def_mean} to {w_r9pre_tail_mean}, n = {w_r9pre_def_n}. The fix cost {tail_diff} a generation.

## 🔭 Is it a fluke of short runs?

No. Long runs are worse. The one long run with the fix on, r9pre-full-tail, was taking {gw_fulltail_pre_g79} a generation by generation [[79]] and died at [[80]] of [[100]] (exit [[1]]). The plain 100-generation run did that same generation in {gw_full100def_g79}. A run that died is a hint rather than a measurement, and the hint is that the cost grows with the pool.

The 40-generation standard run with the fix, full-tail-1, is not run: it exited [[1]] at generation {ft_gens} of {ft_planned} when the sidecar lost the GPU lock. So a full standard run with the fix on is not measured.

## 🧮 Did the filler do anything?

Plenty. r9pre-ab-tail-1 speculated {tl1_speculated} battles, threw {tl1_discard_pct} of them away because the team did not survive the cut, and fed the next round {tl1_served} from the memo, {tl1_served_pct} of its pool of {tl1_pool}. The chip was busy. Busy and useful are different things, and a binned battle is work for nothing.

## ⏱️ Where did the seconds land?

In the tail, the one place they were meant to leave. The morning runs have no profile, so this comes from the afternoon build of the same fix, where the profiler was on. r9-ab-default-1, generation [[7]]: {pf_def_g7_kernel} in the main battle kernel, {pf_def_g7_tail} in the tail. r9-ab-tail-1, same generation: {pf_tail_g7_kernel} kernel, {pf_tail_g7_tail} tail.

The main battles shrank by about three seconds, because some were already done. The tail grew by a second and a half. Over that run the tail share went from {ts_r9def_runsall} to {ts_r9tail_runsall}.

Why the tail grows is not in these files. The log says speculation stops when the main battles end, so it is not the launch running on. My guess is memo traffic and ranking work landing in the tail window. It is a guess.

## 🔀 Why trust the morning over the afternoon?

Because the morning has three runs a side and the afternoon has one. That afternoon pair came out {w_r9tail_runsall} with the fix against {w_r9def_runsall} without (n = {w_r9_n}), which is faster, and I do not know what changed between the 11:53 fork and the 14:05 build. One run each decides nothing.

There is also a conflict in the files for that run name. `runs.json` has r9-ab-default-1 at {w_r9def_runsjson} with a tail share of {ts_r9def_runsjson}, the morning's numbers under the afternoon's name. The lit fork's `evidence-profile.json` has the tail share at {ts_r9def_lit}, by a different ruler (time after half the main battles ended). Both stay on the table.

## 🧪 Did the other shapes do better?

Not enough to matter. The certain feed, which pushes battles for teams already proven to survive into the running kernel through a queue, came out at {w_r9pre_cert_mean}, {cert_diff} slower than plain (n = {w_r9pre_cert_n}).

Tail v2, the same speculation with the trigger at a quarter of workers idle instead of half, came out at {w_tailv2} in its only run (n = {w_tailv2_n}), which is unproven: one run, nothing beside it.

## ✅ Were the answers right?

Yes. Five-generation checkpoints with the fix on were identical to the plain path, {det_tail_ckpts} of [[5]], and the 3v3 verify pass agreed with the CPU on {verify_tail} of winners. Nothing was lost except time.

## 🔁 Back to r9pre-ab-default-1, [[index 7]]

{gw_def1_g7} plain. {gw_tail1_g7} with the wait filled. The generation after it went from {gw_def1_g8} to {gw_tail1_g8}. About {tail_s_def1_g7} of waiting was there to be won back, and none of it came back.

Where that leaves the ask. Built, correct, slower by {tail_diff} a warm generation, and the long run says the slope is the real problem. It stays off. The plain path is as it was.

 Compact state, the other change from this round (battle state kept on-chip instead of in slow memory), is its own {stack_diff} and is unaffected. If you want this pursued, the next run is tail v2 three a side against plain, then a profile of the 11:53 code so the tail has a bucket to blame, then one full standard run of each.

📚 `fixture/data/runs-all.json` (walls, tail shares, tail logs), `runs/r9-ab-*/gpu-profile.json`, `runs.json`, `lit/evidence-profile.json`, `full/full-tail-1.json`, `ab-tailv2.json`, `det-r9.txt`, `tail/verify3v3-tail.log`. Every figure is keyed in `numbers.json` and checked by `check.py --prose`.
