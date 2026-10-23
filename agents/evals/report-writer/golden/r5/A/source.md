# Where the second came from

> I thought number 4 was one of the things I originally requested—I.e, removing unneeded wait times. I want it
~ you, in the round 9 planner session (fixture `plans/PLAN.md`, `## Ask`)

[[Number 4]] meant next round's battles during the wait.

At 12:08 on Saturday morning the GPU started the third plain run of the day (r9pre-ab-default-3), and about a minute and a half in, generation [[7]] took {gw_def3_g7}.

Workers in a launch never finish together, and once the quick ones run out of battles most of the chip sits until the last one lands. That stretch is the tail. It was {ts_default3} of that run's GPU time, so about {tail_s_def3_g7} of our generation's {gw_def3_g7} was the chip waiting.

[[Number 4]] spends that wait: an idle worker picks a team likely to survive the cut and fights its next-round battles early. The code calls this speculation, and the early battle is kept in a memo if the team survives and thrown away if it is cut.

But the wait did not shrink. In that morning's A/B, three plain runs against three with the fix on, a warm generation (generation [[4]] onward, once the pool has filled) went from {w_r9pre_def_mean} to {w_r9pre_tail_mean}, n = {w_r9pre_def_n} a side.

---

The fix added {tail_diff} to every warm generation, and the runs on each side sat within {w_r9pre_def_spread} of each other without the fix and {w_r9pre_tail_spread} with it, so the second is bigger than either side's scatter.

The fix, `POGO_GPU_STUDY=tail`, was never going to change a result, because the cut still comes from the full round. Only the time was supposed to move, and it moved the wrong way. I went through the files looking for where that second came from, one question at a time.

## Did the GPU fill the wait?

It did, and the tail log of the run paired with ours (r9pre-ab-tail-3) says how much. Across its launches the idle workers fought {tl3_speculated} battles early. The team behind {tl3_discard_pct} of those did not survive the cut, so those battles were thrown away.

The round after each launch got {tl3_served} battles from the memo, which is {tl3_served_pct} of its {tl3_pool}.

One battle in eight of the next round was already fought when the round began, and the chip was busy where it used to sit. The other side of that count is the first place to look for the second: more than half of the early battles were fought for a team that was about to be cut, and every one of those cost chip time and saved nothing.

## Was every generation slower, or only some?

Only some of them were, and by wildly different amounts. The chart is our run pair, generation by generation, the time with the fix minus the time without.

::bars gd3_g0 gd3_g1 gd3_g2 gd3_g3 gd3_g4 gd3_g5 gd3_g6 gd3_g7 gd3_g8 gd3_g9 | hi=gd3_g7 | labels=g0 g1 g2 g3 g4 g5 g6 g7 g8 g9 | cap=Seconds added by the fix, r9pre-ab-tail-3 minus r9pre-ab-default-3, per generation. The dark bar is our generation.

Our generation, [[index 7]], moved only {gd3_g7}. The one before it lost {gd3_g6} and the one after it {gd3_g8}. Generation [[3]] lost {gd3_g3}, generation [[9]] lost {gd3_g9}, which is nothing. If you had timed one generation and stopped, the story could have gone either way. Three runs a side with six warm generations each is what settles it at {tail_diff}.

## Where inside a generation did the time go?

The morning runs had no profiler on, so for this question I borrowed the afternoon build of the same fix, where it was. In the afternoon's plain run (r9-ab-default-1), generation [[7]] spent {pf_def_g7_kernel} in the main battle kernel and {pf_def_g7_tail} in the tail. In the afternoon's run with the fix (r9-ab-tail-1), the same generation spent {pf_tail_g7_kernel} in the kernel and {pf_tail_g7_tail} in the tail.

The main battles got shorter by about three seconds, because some of them had already been fought. The tail got longer by about a second and a half. The fix shortened the part of the generation it was never aimed at and lengthened the one part it was built to shrink. Over that whole afternoon run the tail share went from {ts_r9def_runsall} to {ts_r9tail_runsall}.

Why the tail grows is the one thing these files do not say. The log shows speculation stopping when the main battles end, so the launch is not running long. My guess is that the memo traffic and the extra ranking work land in the tail window, and the profiler's buckets do not split the tail finely enough to confirm or deny it.

## Does the afternoon agree with the morning?

It does not, and this is where the data is thinnest. The afternoon pair, one run a side, came out {w_r9tail_runsall} with the fix against {w_r9def_runsall} without (n = {w_r9_n}), so the fix looked faster there. One run each decides nothing, and I do not know what changed in the code between the 11:53 fork and the 14:05 build.

The files for that afternoon run also disagree with each other. The summary file `runs.json` carries the afternoon names with the morning's numbers inside, so its row for r9-ab-default-1 reads {w_r9def_runsjson} with a tail share of {ts_r9def_runsjson}, the 11:53 figures.

The lit fork's `evidence-profile.json` puts the tail share for the same run name at {ts_r9def_lit}, measured by a different ruler, the time after half the main battles had ended. That is a conflict I am leaving in the open, since picking one would mean trusting a file over the run's own profile.

## What happens over a long run?

A long run makes it much worse. The one long run with the fix on (r9pre-full-tail) reached generation [[80]] of [[100]] and then exited [[1]]. By generation [[79]] a single generation was taking {gw_fulltail_pre_g79}. The plain 100-generation run did generation [[79]] in {gw_full100def_g79} and averaged {w_full100_def} per warm generation over the whole run.

A run that died gives a hint and no more, and the hint is that whatever grows in the tail keeps growing as the pool of teams and memos grows.

The planned 40-generation standard run with the fix, full-tail-1, is not run either. It exited [[1]] at generation {ft_gens} of {ft_planned} when the sidecar lost the GPU lock. Nobody has timed a full standard run with the fix on, so that number is not measured, and the ship test in the plan asks for it.

## Did the other shapes of [[number 4]] do better?

The certain feed, which pushes battles for teams already proven to survive into the running kernel through a queue, came out at {w_r9pre_cert_mean} in its three morning runs, {cert_diff} slower than plain (n = {w_r9pre_cert_n}). That loss is smaller than the tail's own and has the same sign.

Tail v2, the same speculation with the trigger moved from half the workers idle to a quarter, came out at {w_tailv2} in its only run (n = {w_tailv2_n}). That would be a large win if it held, and with one run and nothing beside it the number is unproven.

## Did it at least get the right answers?

It did, and the five-generation checkpoints with the fix on matched the plain path, {det_tail_ckpts} of [[5]], and the 3v3 verify pass agreed with the CPU on {verify_tail} of winners. The fix never touched what the GPU computed, only how long it took.

## Back to [[generation 7]]

Our generation, [[index 7]] of the third plain run, took {gw_def3_g7} with the wait left in it. With the wait filled, in the paired run with the fix on, the same generation took {gw_tail3_g7}. The generation after it went from {gw_def3_g8} to {gw_tail3_g8}. About {tail_s_def3_g7} of waiting was there to be won back, and the filler gave none of it back.

The thing you asked for is built and it computes the right answers, and it costs {tail_diff} per warm generation in the one test with enough runs to count, with a far steeper cost over a long run, so it stays off and the plain path is as it was.

Compact state, the round's other change, which keeps battle state on the chip instead of in slow memory, is a separate {stack_diff} that stands on its own.

If you want the wait back, the next run is tail v2 three a side against plain, interleaved like the morning A/B. After that, a profile of the 11:53 code, so that the growing tail gets a bucket of its own. After that, one full standard run of each, because the long run is the part that would hurt you.

📚 Sources: `fixture/data/runs-all.json` (walls, tail shares, tail logs), `runs/r9-ab-*/gpu-profile.json`, `runs.json`, `lit/evidence-profile.json`, `full/full-tail-1.json`, `ab-tailv2.json`, `det-r9.txt`, `tail/verify3v3-tail.log`. Every figure is keyed in `numbers.json` and checked by `check.py --prose`.
