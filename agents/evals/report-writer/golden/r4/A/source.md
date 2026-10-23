# Where [[number 4]]'s second went

> I thought number 4 was one of the things I originally requested—I.e, removing unneeded wait times. I want it
~ you, in the round 9 planner session (fixture `plans/PLAN.md`, `## Ask`)

[[Number 4]] on that list: next round's battles during the wait.

One generation, then. r9pre-ab-default-3, [[index 7]], Saturday 12:08 ET, plain code, took {gw_def3_g7}, as ordinary as they come (that morning's three plain runs averaged {w_r9pre_def_mean}).

Over the whole run, {ts_default3} of the GPU's time was tail, the end of a launch, when the first workers have run out of battles and most of the chip waits for the last ones. By that share, about {tail_s_def3_g7} of this generation's {gw_def3_g7} were waiting.

[[Number 4]] fills that wait: idle workers start next round's battles for the teams likeliest to survive the cut. That is speculation, work done before anyone knows it is needed, kept as a memo hit if the team survives and thrown away if not.

But it went the wrong way. In that morning's A/B, three plain runs against three with the fix on, a warm generation went from {w_r9pre_def_mean} to {w_r9pre_tail_mean}, n = {w_r9pre_def_n} a side. (Warm: generation [[4]] onward, once the pool has filled.)

The fix, `POGO_GPU_STUDY=tail`, leaves the results alone, since the cut still comes from the full round. Only the time was supposed to move, and it added {tail_diff} to every warm generation. That gap is bigger than the spread within either side ({w_r9pre_def_spread} plain, {w_r9pre_tail_spread} with the fix), so it is not noise.

The wait was supposed to shrink. Something grew instead. The rest of this is a search for the second.

## Did the GPU do the work?

Yes. The run paired with our generation, r9pre-ab-tail-3, logged {tl3_speculated} speculated battles across its launches. Of those, {tl3_discard_pct} were discarded, because the team they were for did not survive the cut.

The round after each launch was served {tl3_served} battles from the memo, which is {tl3_served_pct} of its {tl3_pool}.

So the filler did fill. The chip was busy where it used to idle, and one battle in eight of the next round was already done when the round started. Busy is a cost, though, and this is the first place to look for the second. A speculated battle that gets discarded is pure cost. A kept one saves a battle later. The log says more than half were pure cost.

## Was every generation slower, or only some of them?

Not every one, and not evenly. The chart is our run pair, generation by generation, the time with the fix minus the time without.

::bars gd3_g0 gd3_g1 gd3_g2 gd3_g3 gd3_g4 gd3_g5 gd3_g6 gd3_g7 gd3_g8 gd3_g9 | hi=gd3_g7 | labels=g0 g1 g2 g3 g4 g5 g6 g7 g8 g9 | cap=Seconds added by the fix, r9pre-ab-tail-3 minus r9pre-ab-default-3, per generation. Dark bar is our generation.

Our generation, [[index 7]], moved only {gd3_g7}. Its neighbours lost {gd3_g6} and {gd3_g8}. Generation [[3]] lost {gd3_g3}, generation [[9]] nothing to speak of. If you had timed one generation and stopped, you could have come away with any story you liked. Three runs a side and six warm generations per run is what turns this into {tail_diff}.

## So where inside a generation did it grow?

The morning runs have no profile, so for this question I have to borrow one from the afternoon build of the same fix, where the profiler was on. In r9-ab-default-1, generation [[7]] spent {pf_def_g7_kernel} in the main battle kernel and {pf_def_g7_tail} in the tail. In r9-ab-tail-1 the same generation spent {pf_tail_g7_kernel} in the kernel and {pf_tail_g7_tail} in the tail.

Read that twice. The main battles got shorter, by about three seconds, because an eighth of them had already been fought. The tail got longer, by about a second and a half. The fix shortens the part of the generation it was never aimed at and lengthens the part it was aimed at. Over the whole afternoon run the tail share went from {ts_r9def_runsall} to {ts_r9tail_runsall}.

Why the tail grows I cannot tell from these files. The log says speculation stops when the main battles end, so it is not the launch running long. My guess is the memo traffic and the extra ranking work land in the tail window, but that is a guess, and the profiler buckets here do not split it.

## Does the afternoon agree with the morning?

No, and that is the awkward part. That afternoon pair, one run a side, came out {w_r9tail_runsall} with the fix against {w_r9def_runsall} without (n = {w_r9_n}). Faster. One run each is not evidence either way, and I do not know what changed in the code between the 11:53 fork and the 14:05 build.

It gets worse before it gets better. `runs.json` lists the afternoon names with the morning's numbers in them, so its row for r9-ab-default-1 says {w_r9def_runsjson} and a tail share of {ts_r9def_runsjson}, which is the 11:53 run.

The lit fork's `evidence-profile.json` says {ts_r9def_lit} for the same run name, measured with a different ruler, the time after half the main battles ended. Two files, one name, two tail share numbers, and a conflict I am leaving in the open instead of picking one.

## Does it get better or worse with more generations?

Worse, a lot. One longer run with the fix on, r9pre-full-tail, got to generation [[80]] of [[100]] before it exited [[1]]. By then a generation was taking {gw_fulltail_pre_g79}.

The plain 100-generation run took {gw_full100def_g79} for the same generation, and {w_full100_def} per warm generation over the whole run. A dead run's numbers are a hint rather than a result, and the hint is that whatever grows in the tail keeps growing as the pool of teams and memos grows.

The planned 40-generation standard run with the fix, full-tail-1, is not run either. It exited [[1]] at generation {ft_gens} of {ft_planned} when the sidecar lost the GPU lock. Nobody has timed a full standard run with the fix on, so that number is not measured. The ship test in the plan needs it.

## Did the other shapes of [[number 4]] do any better?

Adding the certain feed, which pushes battles for teams that have already provably survived into the running kernel through a queue, came out at {w_r9pre_cert_mean}, {cert_diff} against plain (n = {w_r9pre_cert_n}). Slower still, by less.

Tail v2, the same speculation with the threshold dropped from half the workers idle to a quarter, came out at {w_tailv2} in its only run (n = {w_tailv2_n}). That would be a big win, and it is unproven: one run, no spread, no pair.

## Did it at least compute the right thing?

Yes. Five-generation checkpoints with the fix on match the plain path, {det_tail_ckpts} of [[5]], and the 3v3 verify pass agreed with the CPU on {verify_tail} of winners. This was only ever about time.

## Back to [[generation 7]]

Our generation, r9pre-ab-default-3 [[index 7]], took {gw_def3_g7} with the wait in it. With the wait filled, in r9pre-ab-tail-3, the same generation took {gw_tail3_g7}. The one after it went from {gw_def3_g8} to {gw_tail3_g8}. The wait was {tail_s_def3_g7} and the filler did not give any of it back.

So the thing you asked for is built and it is correct, and it is slower. The cost is {tail_diff} per warm generation in the one test with enough runs to count, and a far worse slope over a long run. It stays off.

The plain path is unchanged, and the round's other change, compact state, which keeps battle state on-chip instead of in slow memory, is a separate {stack_diff} that stands on its own.

What I would try next. First, tail v2 in a three-a-side interleaved A/B, because its {w_tailv2}, unproven as it is, is the only number here that points the way you wanted. Then a profile of the 11:53 code, so the tail growth has a bucket. After that, one full standard run of each, since the slope is the part that would hurt you.

📚 Sources: `fixture/data/runs-all.json` (walls, tail shares, tail logs), `runs/r9-ab-*/gpu-profile.json`, `runs.json`, `lit/evidence-profile.json`, `full/full-tail-1.json`, `ab-tailv2.json`, `det-r9.txt`, `tail/verify3v3-tail.log`. Every figure is keyed in `numbers.json` and checked by `check.py --prose`.
