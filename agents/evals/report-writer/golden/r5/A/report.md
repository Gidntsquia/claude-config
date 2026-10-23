# Where the second came from

> I thought number 4 was one of the things I originally requested—I.e, removing unneeded wait times. I want it

<sub>you, in the round 9 planner session (fixture `plans/PLAN.md`, `## Ask`)</sub>

Number 4 meant next round's battles during the wait.

At 12:08 on Saturday morning the GPU started the third plain run of the day (r9pre-ab-default-3), and about a minute and a half in, generation 7 took 12.59 s.

Workers in a launch never finish together, and once the quick ones run out of battles most of the chip sits until the last one lands. That stretch is the tail. It was 41.6% of that run's GPU time, so about 5.2 s of our generation's 12.59 s was the chip waiting.

Number 4 spends that wait: an idle worker picks a team likely to survive the cut and fights its next-round battles early. The code calls this speculation, and the early battle is kept in a memo if the team survives and thrown away if it is cut.

But the wait did not shrink. In that morning's A/B, three plain runs against three with the fix on, a warm generation (generation 4 onward, once the pool has filled) went from 12.60 s to 13.63 s, n = 3 a side.

The fix added 1.03 s to every warm generation, and the runs on each side sat within 0.46 s of each other without the fix and 0.53 s with it, so the second is bigger than either side's scatter.

The fix, `POGO_GPU_STUDY=tail`, was never going to change a result, because the cut still comes from the full round. Only the time was supposed to move, and it moved the wrong way. I went through the files looking for where that second came from, one question at a time.

## Did the GPU fill the wait?

It did, and the tail log of the run paired with ours (r9pre-ab-tail-3) says how much. Across its launches the idle workers fought 61,424 battles early. The team behind 55% of those did not survive the cut, so those battles were thrown away.

The round after each launch got 21,641 battles from the memo, which is 12% of its 182,630.

One battle in eight of the next round was already fought when the round began, and the chip was busy where it used to sit. The other side of that count is the first place to look for the second: more than half of the early battles were fought for a team that was about to be cut, and every one of those cost chip time and saved nothing.

## Was every generation slower, or only some?

Only some of them were, and by wildly different amounts. The chart is our run pair, generation by generation, the time with the fix minus the time without.

(chart: gen 0 tail minus default, pair 3 +2.59 s, gen 1 tail minus default, pair 3 +1.30 s, gen 2 tail minus default, pair 3 +0.18 s, gen 3 tail minus default, pair 3 +2.04 s, gen 4 tail minus default, pair 3 +1.36 s, gen 5 tail minus default, pair 3 +1.23 s, gen 6 tail minus default, pair 3 +1.93 s, gen 7 tail minus default, pair 3 +0.32 s, gen 8 tail minus default, pair 3 +1.27 s, gen 9 tail minus default, pair 3 +0.02 s)

Seconds added by the fix, r9pre-ab-tail-3 minus r9pre-ab-default-3, per generation. The dark bar is our generation.

Our generation, index 7, moved only +0.32 s. The one before it lost +1.93 s and the one after it +1.27 s. Generation 3 lost +2.04 s, generation 9 lost +0.02 s, which is nothing. If you had timed one generation and stopped, the story could have gone either way. Three runs a side with six warm generations each is what settles it at 1.03 s.

## Where inside a generation did the time go?

The morning runs had no profiler on, so for this question I borrowed the afternoon build of the same fix, where it was. In the afternoon's plain run (r9-ab-default-1), generation 7 spent 6.58 s in the main battle kernel and 5.04 s in the tail. In the afternoon's run with the fix (r9-ab-tail-1), the same generation spent 3.31 s in the kernel and 6.61 s in the tail.

The main battles got shorter by about three seconds, because some of them had already been fought. The tail got longer by about a second and a half. The fix shortened the part of the generation it was never aimed at and lengthened the one part it was built to shrink. Over that whole afternoon run the tail share went from 42.0% to 55.4%.

Why the tail grows is the one thing these files do not say. The log shows speculation stopping when the main battles end, so the launch is not running long. My guess is that the memo traffic and the extra ranking work land in the tail window, and the profiler's buckets do not split the tail finely enough to confirm or deny it.

## Does the afternoon agree with the morning?

It does not, and this is where the data is thinnest. The afternoon pair, one run a side, came out 12.12 s with the fix against 12.60 s without (n = 1), so the fix looked faster there. One run each decides nothing, and I do not know what changed in the code between the 11:53 fork and the 14:05 build.

The files for that afternoon run also disagree with each other. The summary file `runs.json` carries the afternoon names with the morning's numbers inside, so its row for r9-ab-default-1 reads 12.80 s with a tail share of 42.6%, the 11:53 figures.

The lit fork's `evidence-profile.json` puts the tail share for the same run name at 35.2%, measured by a different ruler, the time after half the main battles had ended. That is a conflict I am leaving in the open, since picking one would mean trusting a file over the run's own profile.

## What happens over a long run?

A long run makes it much worse. The one long run with the fix on (r9pre-full-tail) reached generation 80 of 100 and then exited 1. By generation 79 a single generation was taking 127.1 s. The plain 100-generation run did generation 79 in 10.9 s and averaged 10.09 s per warm generation over the whole run.

A run that died gives a hint and no more, and the hint is that whatever grows in the tail keeps growing as the pool of teams and memos grows.

The planned 40-generation standard run with the fix, full-tail-1, is not run either. It exited 1 at generation 14 of 40 when the sidecar lost the GPU lock. Nobody has timed a full standard run with the fix on, so that number is not measured, and the ship test in the plan asks for it.

## Did the other shapes of number 4 do better?

The certain feed, which pushes battles for teams already proven to survive into the running kernel through a queue, came out at 13.20 s in its three morning runs, 0.59 s slower than plain (n = 3). That loss is smaller than the tail's own and has the same sign.

Tail v2, the same speculation with the trigger moved from half the workers idle to a quarter, came out at 9.10 s in its only run (n = 1). That would be a large win if it held, and with one run and nothing beside it the number is unproven.

## Did it at least get the right answers?

It did, and the five-generation checkpoints with the fix on matched the plain path, 5 of 5, and the 3v3 verify pass agreed with the CPU on 100.00% of winners. The fix never touched what the GPU computed, only how long it took.

## Back to generation 7

Our generation, index 7 of the third plain run, took 12.59 s with the wait left in it. With the wait filled, in the paired run with the fix on, the same generation took 12.91 s. The generation after it went from 17.22 s to 18.49 s. About 5.2 s of waiting was there to be won back, and the filler gave none of it back.

The thing you asked for is built and it computes the right answers, and it costs 1.03 s per warm generation in the one test with enough runs to count, with a far steeper cost over a long run, so it stays off and the plain path is as it was.

Compact state, the round's other change, which keeps battle state on the chip instead of in slow memory, is a separate −0.54 s that stands on its own.

If you want the wait back, the next run is tail v2 three a side against plain, interleaved like the morning A/B. After that, a profile of the 11:53 code, so that the growing tail gets a bucket of its own. After that, one full standard run of each, because the long run is the part that would hurt you.

📚 Sources: `fixture/data/runs-all.json` (walls, tail shares, tail logs), `runs/r9-ab-*/gpu-profile.json`, `runs.json`, `lit/evidence-profile.json`, `full/full-tail-1.json`, `ab-tailv2.json`, `det-r9.txt`, `tail/verify3v3-tail.log`. Every figure is keyed in `numbers.json` and checked by `check.py --prose`.
