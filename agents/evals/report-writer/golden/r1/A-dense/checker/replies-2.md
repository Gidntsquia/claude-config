# Replies, loop 2
Accepted 1, 2, 3, 4, 5, 7, 8:
1. Wrong-or-missing item reworded (lost default run + summary mislabels three runs); evidence-profile's warm figure for r9-ab-default-1 added to the tail section as a third value.
2. Occupancy chain: definition difference with occ/runs.json stated; n on both sides given.
3. "pre-fix" dropped. The data only shows r9pre at 11:53 ET and r9 at 14:05 ET with opposite directions, which is what the text now says. Verdict stays rerun.
4. Item reworded: the checkpoint match cites a log outside the data; base-a named as a default run.
5. "the one full run on disk" corrected; r9pre-full-tail and r9pre-full-certain (both exit 1) listed as not run.
7. Production chain n = 2 added.
8. "Three files" → "Files disagree"; the third value stays in the section (the box allows two figures).
Rejected 6: sum(generations[4:].buckets.tail) / sum(generations[4:].wall) on runs/ab-stack-1/gpu-profile.json gives 0.43672, equal to runs-all.json tailShare; the checker's 0.40 is a different formula. Definition text unchanged.
