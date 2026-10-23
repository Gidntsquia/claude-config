# Filled the wait, lost a second

> I thought number 4 was one of the things I originally requested—I.e, removing unneeded wait times. I want it

<sub>you, in the round 9 planner session (fixture `plans/PLAN.md`, `## Ask`)</sub>

Number 4 was "start next round's battles during the wait".

Here is one of the waits. r9pre-ab-default-1, index 7, the first plain run on Saturday morning, 11:53 ET, took 12.84 s. Across that run 42.6% of GPU time was tail, the slack at the end of a launch: battles finish unevenly, the quick workers go idle, and the chip mostly sits until the slowest battle lands. Call it 5.5 s of this generation spent waiting.

Number 4 puts that idle time to use: workers with nothing to do start next round's battles for teams likely to survive the cut. That is speculation, done early, kept as a memo hit if the team survives, binned if not.

But the same generation with the fix on, in r9pre-ab-tail-1, took 12.94 s. Over the morning's A/B, three runs a side, a warm generation (generation 4 onward, once the pool is full) went from 12.60 s to 13.63 s, n = 3. The fix cost 1.03 s a generation.

## 🔭 Is it a fluke of short runs?

No. Long runs are worse. The one long run with the fix on, r9pre-full-tail, was taking 127.1 s a generation by generation 79 and died at 80 of 100 (exit 1). The plain 100-generation run did that same generation in 10.9 s. A run that died is a hint rather than a measurement, and the hint is that the cost grows with the pool.

The 40-generation standard run with the fix, full-tail-1, is not run: it exited 1 at generation 14 of 40 when the sidecar lost the GPU lock. So a full standard run with the fix on is not measured.

## 🧮 Did the filler do anything?

Plenty. r9pre-ab-tail-1 speculated 65,127 battles, threw 56% of them away because the team did not survive the cut, and fed the next round 21,928 from the memo, 12% of its pool of 182,630. The chip was busy. Busy and useful are different things, and a binned battle is work for nothing.

## ⏱️ Where did the seconds land?

In the tail, the one place they were meant to leave. The morning runs have no profile, so this comes from the afternoon build of the same fix, where the profiler was on. r9-ab-default-1, generation 7: 6.58 s in the main battle kernel, 5.04 s in the tail. r9-ab-tail-1, same generation: 3.31 s kernel, 6.61 s tail.

The main battles shrank by about three seconds, because some were already done. The tail grew by a second and a half. Over that run the tail share went from 42.0% to 55.4%.

Why the tail grows is not in these files. The log says speculation stops when the main battles end, so it is not the launch running on. My guess is memo traffic and ranking work landing in the tail window. It is a guess.

## 🔀 Why trust the morning over the afternoon?

Because the morning has three runs a side and the afternoon has one. That afternoon pair came out 12.12 s with the fix against 12.60 s without (n = 1), which is faster, and I do not know what changed between the 11:53 fork and the 14:05 build. One run each decides nothing.

There is also a conflict in the files for that run name. `runs.json` has r9-ab-default-1 at 12.80 s with a tail share of 42.6%, the morning's numbers under the afternoon's name. The lit fork's `evidence-profile.json` has the tail share at 35.2%, by a different ruler (time after half the main battles ended). Both stay on the table.

## 🧪 Did the other shapes do better?

Not enough to matter. The certain feed, which pushes battles for teams already proven to survive into the running kernel through a queue, came out at 13.20 s, 0.59 s slower than plain (n = 3).

Tail v2, the same speculation with the trigger at a quarter of workers idle instead of half, came out at 9.10 s in its only run (n = 1), which is unproven: one run, nothing beside it.

## ✅ Were the answers right?

Yes. Five-generation checkpoints with the fix on were identical to the plain path, 5 of 5, and the 3v3 verify pass agreed with the CPU on 100.00% of winners. Nothing was lost except time.

## 🔁 Back to r9pre-ab-default-1, index 7

12.84 s plain. 12.94 s with the wait filled. The generation after it went from 17.47 s to 19.59 s. About 5.5 s of waiting was there to be won back, and none of it came back.

Where that leaves the ask. Built, correct, slower by 1.03 s a warm generation, and the long run says the slope is the real problem. It stays off. The plain path is as it was.

Compact state, the other change from this round (battle state kept on-chip instead of in slow memory), is its own −0.54 s and is unaffected. If you want this pursued, the next run is tail v2 three a side against plain, then a profile of the 11:53 code so the tail has a bucket to blame, then one full standard run of each.

📚 `fixture/data/runs-all.json` (walls, tail shares, tail logs), `runs/r9-ab-*/gpu-profile.json`, `runs.json`, `lit/evidence-profile.json`, `full/full-tail-1.json`, `ab-tailv2.json`, `det-r9.txt`, `tail/verify3v3-tail.log`. Every figure is keyed in `numbers.json` and checked by `check.py --prose`.
