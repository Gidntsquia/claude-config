# Spec: weekly-roundup reruns from the same machine replace that machine's data instead of appending
Drafted 2026-10-11.

## Ask
> Make sure if I run the weekly roundup from th same machine multiple times, the data for "me" is merged instead of appeneded (i.e. we don't duplicate project data)

User's answers:
- Symptom: "Not seen yet, make it robust".
- Identity key: "Person + hostname".
- Rerun policy: "Latest cap % wins, as now"; "Fresh everything from this machine"; "Option 4 since the project may have been updated since we last ran the weekly roundup, so the deep dive and things should reflect that".
- Proof: "Docker test: A, A again == A once"; "Unit test on gather_data.py".
- Same hostname, different person: "This won't happen, and if it does we should signal an error".
- Rewrite scope on rerun: "Deep-dive paragraphs", "Things fixed", "Feature assignments", "Card pictures and card-meta".
- Ownership: "Pool records authorship".
- Unit test: "tests/test_gather_data.py via pytest".

## What to build
Harden `skills/weekly-roundup` so that any number of reruns from one machine for one week leave exactly one contribution from that machine in the week's pool, page and archive. `gather_data.py` keys a contribution on person + hostname, errors when the same hostname reappears under a different person, drops that machine's old sessions, commits, feature assignments and authored page parts, and recomputes from scratch. The pool records which device authored each deep-dive card and each "Things fixed" entry so the skill rewrites only this machine's parts on a rerun and keeps other machines' parts untouched. A pytest file proves the script's merge rules without Docker; the existing Docker harness gains an A-then-A-again scenario whose result must equal a single run.

## Facts
- `gather_data.py` (826 lines) already replaces the entry whose `device` label equals `--device` (default `getpass.getuser()@socket.gethostname()`), keeps `others`, and merges projects by remote URL then repo folder name (`merge_projects`); sessions dedupe by id, "this machine (last) wins". Read from the source, 2026-10-11.
- The pool `features` map in `--pool-in` is applied by default on a rerun; the skill text tells the agent to start from it and only assign this machine's sessions, so stale assignments for sessions no longer reported can persist. Read from SKILL.md and the `--features-file` handling.
- SKILL.md "Joining run" tells the agent to keep every existing card's picture, paragraph, card-meta and every "Things fixed" entry, so a rerun today never refreshes this machine's own prose.
- `build_archive.py` inserts or replaces a week by `weekStart` (SKILL.md step 5), so the archive does not duplicate on rerun as long as the agent updates the week's artifact in place rather than publishing a new one.
- `tests/check.py` already has "S3 == S1 (rerun replaced, did not duplicate)" for the sequence A→B→A; there is no A→A scenario, no hostname-change scenario, and no page-level (card count, Things fixed) check.
- `state.json` holds `person`; the pool's `devices[]` entries hold `device`, `person`, `collected_at`.

## Requirements
Each is marked (user) or (default).
1. Contribution key (user). A pool contribution is identified by `hostname` plus `person` (the person after the script's fuzzy matching). `--device` stays as the display label; the script derives `hostname` from it (text after `@`) or from `socket.gethostname()` and stores it as its own field in each `devices[]` entry. Older pool entries without a `hostname` field get it parsed from `device` when loaded.
2. Rerun replaces (user). When `--pool-in` holds an entry with this hostname and the same person, the script removes that entry completely (its sessions, commits, misc, feature assignments, authored parts) before adding the fresh one. After the run the pool has exactly one entry for this hostname, every other entry byte-identical to before (except `cap_pct`/`cap_pct_at` when a new cap is given).
3. Same hostname, different person (user). If the stored entry for this hostname has a different person than this run's `--person`, the script exits non-zero with a message naming both people and the hostname, writes nothing, and SKILL.md tells the agent to stop and report it to the user rather than work around it.
4. Shared projects (default). A project both this machine and another reported keeps the other machine's sessions and commits; only this machine's are replaced. Commit hashes and session ids shared by both count once, as today.
5. Feature assignments (user). On a rerun the script drops every `features` link to a session this machine reported before, keeps links for other machines' sessions, and the skill reassigns this machine's sessions from scratch (reusing existing feature names where they fit). The `--features-file` passed on the rerun still replaces the stored map in full; the script warns on stderr about any link to a session no longer in the pool and drops it.
6. Authorship in the pool (user). The pool gains `authored`: per project (keyed as `merge_projects` keys it) the `hostname` that last wrote its deep-dive paragraph, picture and card-meta; per "Things fixed" entry its text id and the `hostname` that wrote it. `embed_pool.py` writes it with the rest; `gather_data.py` passes it through and, on a rerun, lists in its output `rewrite`: the project names and Things-fixed ids owned by this hostname (plus projects only this machine worked on).
7. Rerun rewrites this machine's prose (user). SKILL.md's joining-run section is amended: for every project in `rewrite`, the agent rewrites the deep-dive paragraph, re-picks the picture and card-meta from the current repo state, and re-derives this machine's "Things fixed" entries from transcripts, removing the old ones in `rewrite`; cards and entries owned by other hostnames are kept verbatim as today. Numbers and colors are always replaced from the new output, as today.
8. Cap % (user). Unchanged: a new `--cap-pct` wins and updates `cap_pct_at`; omitting it keeps the stored value; a lower figure still warns.
9. Page uniqueness (default). After a rerun the page has one list row, one pie slice per person, one deep-dive card and one Data sources row per project/machine; exactly one `roundup-data` block. SKILL.md's output checklist gains: on a rerun, `devices` count equals the count before the run.
10. Archive (default). A rerun updates the week's artifact in place and the archive entry by `weekStart`; the archive never gains a second entry or a second artifact for the week. SKILL.md step 0 states that a page already listing this hostname means "rerun", and that the agent must never publish a new artifact for a listed week.
11. Unit tests (user). `skills/weekly-roundup/tests/test_gather_data.py`, run with `uv run pytest skills/weekly-roundup/tests`, using small pool JSON fixtures and a fake files dir / projects dir (no Claude, no Docker, no network). Cases: first run creates one entry; rerun same hostname+person yields one entry with totals equal to a single run; rerun drops this machine's old feature links and keeps the other machine's; same hostname different person exits non-zero and writes nothing; two hostnames with the same person stay as two entries; legacy entry without `hostname` is matched by the parsed label; `rewrite` lists this hostname's authored projects and Things-fixed ids.
12. Docker scenario (user). `tests/run.sh` gains scenario S4: run A, then A again (same container, fresh fake commits added between runs are allowed but the expected values account for them). `check.py` asserts S4's pool `devices` length is 1, totals equal the hand-computed single-run values in `expected.json`, the page has one card per project and no duplicated Things-fixed text, and the test archive lists the week once. PASS/FAIL per line as the other scenarios.
13. Reporting (default). After a rerun the skill's report to the user says "replaced this machine's earlier data from <collected_at>" and lists what was rewritten.
14. No change for first runs and joining runs from a new hostname (default): output identical to today's.

## Constraints
- Python 3 standard library only in `gather_data.py`, `embed_pool.py`, `build_archive.py` (as today); tests use pytest run via `uv`.
- Only files under `skills/weekly-roundup/` change (scripts, SKILL.md, tests). The real Roundup Archive and real week artifacts are never touched; Docker scenarios use throwaway artifacts as today.
- SKILL.md edits keep its existing structure and voice; add the rules where the matching step already is.
- The pool format stays backward compatible: pages written before this change load and merge.

## Acceptance criteria
- [ ] 1, 2, 14: `uv run pytest skills/weekly-roundup/tests` passes; the rerun case shows one `devices` entry with `hostname`, totals equal to the single run, other entries unchanged.
- [ ] 3: pytest case: same hostname, different person → exit code ≠ 0, stderr names both people and the hostname, `--pool-out` file not created.
- [ ] 4: pytest case with a shared project: other machine's sessions/commits still present after rerun; shared ids counted once.
- [ ] 5: pytest case: feature link to a session this machine no longer reports is gone; other machine's links remain; stderr warns on a dangling id.
- [ ] 6: `roundup-data` block from a Docker run contains `authored` with hostnames per project and per Things-fixed entry; script output contains `rewrite`.
- [ ] 7, 10: SKILL.md joining-run section, step 0, and checklist contain the rerun rules; `grep -n rewrite skills/weekly-roundup/SKILL.md` finds them.
- [ ] 9, 12: `tests/run.sh` S4 then `check.py`: 0 FAIL lines; S4 page has one card per project, one Data sources row, one `roundup-data` block; test archive has one entry for the week.
- [ ] 11: test file exists at `skills/weekly-roundup/tests/test_gather_data.py` and needs no Docker or network.
- [ ] 13: S4's second-run log contains "replaced this machine's earlier data".
