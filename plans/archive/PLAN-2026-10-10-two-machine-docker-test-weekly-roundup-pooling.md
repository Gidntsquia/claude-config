# Spec: Two-machine Docker test of weekly-roundup cross-machine pooling
Drafted 2026-10-10.

## Ask
> I want to test the new weekly roundup skill changes that are intended to allow multiple machines to pool their weekly usage data seemlessly using the artifact they generate as the data store. To do this, I want you to create two virtual machine / dockers / whatever makes sense with dummy claude session data, run the weekly usage skill, and see if they properly pool their data together. We can assume that the weekly usage skills won't be called at the same time (i.e. we don't have to worry about race conditions)

User's answers:
- Skill run: "Full Claude run in each container, and port in my credentials from this machine".
- Isolation: "Two Docker containers, since otherwise there may be leakage where the AI sees outside of its container".
- Fixtures: "Project unique to each machine, Misc should pool by machine; I want to know who did what usage".
- Right result: hand-computed expected totals; idempotence and order independence; visual check of the HTML.
- Containers: install Docker Engine in WSL via apt.
- Artifact stand-in: real Artifact tool, a throwaway test archive (real archive untouched).
- Run mode: non-interactive `claude -p` with answers in the prompt.
- Harness location: `skills/weekly-roundup/tests/` in this repo.

## What to build
A test harness under `skills/weekly-roundup/tests/` that installs Docker Engine in this WSL box if missing, builds one image containing Claude Code and this repo's `weekly-roundup` skill, starts two containers ("machine A" and "machine B") with distinct hostnames, this machine's Claude credentials, generated fake git repos under `/root/files` and generated fake session jsonl under `/root/.claude/projects`, then drives `claude -p` in each to run `/weekly-roundup` for the current week against a throwaway test Roundup Archive artifact. The harness runs the sequence A→B, then B→A on a fresh test archive, then A→B→A (rerun), pulls the resulting week page via the Artifact tool, and checks the embedded `roundup-data` pool against hand-computed expected numbers, prints PASS/FAIL per check, and opens the final page in Firefox for a visual check.

## Facts
- Docker and podman are not installed (`which docker podman` empty; no Docker Desktop under `/mnt/c`). Claude Code 2.1.296 at `~/.local/bin/claude`; credentials in `~/.claude/.credentials.json`.
- `gather_data.py` takes `--files-dir`, `--claude-projects`, `--device` (default `<user>@<hostname>`), `--pool-in <page.html|pool.json>`, `--pool-out`; merges projects by remote URL else folder name; keeps per-device totals (`devices[]`: device, sessions, fe_tokens, cost, weekly_pct) and tags every session and misc session with its `device`. `embed_pool.py` writes the `roundup-data` script block. `build_archive.py --base <published archive.html> --add <week.json>` maintains the archive page.
- Sessions are read from `*.jsonl` under each project dir (one session per file; fields used: `message.model`, `message.usage` with `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation`), windowed by timestamp. Misc = sessions whose project dir has no repo under files-dir.
- Current week: `weekStart` 2026-10-04, window Sun 2026-10-04 22:00 ET → now.
- Unverified: whether the `Artifact` tool is available to `claude -p` (non-interactive) sessions inside a container and whether it needs a browser login beyond `.credentials.json`. The worker must check this first; if Artifact is unavailable headless, fall back to the interactive-run path in Req. 12.

## Requirements
1. (user) `tests/setup_docker.sh`: if `docker` is missing, installs `docker.io` via apt, starts the daemon, adds the user to the `docker` group, and verifies `docker run hello-world`. Idempotent.
2. (user) `tests/Dockerfile`: Ubuntu base, git, python3, Node, Claude Code (same major version as the host), the repo's `skills/weekly-roundup/` copied to `/root/.claude/skills/weekly-roundup/`. Nothing from the host outside that skill directory and the credentials is mounted; containers have no access to the host's `~/files` or `~/.claude/projects`.
3. (user) Credentials: the host's `~/.claude/.credentials.json` (and `~/.claude.json` oauth account fields if needed for login) copied read-only into each container at start; never baked into the image; the image and any logs never contain the token.
4. (default) Two containers: hostname `machine-a` and `machine-b`, user `root`, so device labels are `root@machine-a` and `root@machine-b`.
5. (user) `tests/make_fixtures.py <machine>` generates, inside the container: machine A gets repo `/root/files/alpha-app` (remote `https://github.com/test/alpha-app`, 3 commits dated within the window, 1 before it) and machine B gets `/root/files/beta-tool` (remote `https://github.com/test/beta-tool`, 2 commits in window). Neither repo exists on the other machine.
6. (user) Fixture sessions: machine A gets 2 jsonl sessions under `/root/.claude/projects/-root-files-alpha-app/` and 1 Misc session under `/root/.claude/projects/-root-scratch/` (no repo); machine B gets 1 session for beta-tool and 2 Misc sessions. Token counts are fixed round numbers per session (e.g. 100k/200k/50k cache-read etc.), models `claude-sonnet-4-5` and `claude-fable-5-1`, timestamps inside the window, one assistant message dated before the window that must be excluded. Expected totals are written to `tests/expected.json` by the generator.
7. (user) Throwaway archive: `tests/run.sh` first has container A publish a new empty Roundup Archive artifact (built with `build_archive.py` from an empty weeks list) and records its URL; both containers' `state.json` carry that `archive_url`; the host's `state.json` and the real archive are never read or written by containers.
8. (user) Each run: `claude -p "<prompt>" --dangerously-skip-permissions` where the prompt says: run /weekly-roundup for this week, cap-pct is N, assign features yourself, do not ask questions, publish, then print the week page URL on the last line. cap-pct: A=40, B=55; the rerun of A passes no new cap-pct (prompt says keep the stored one). Each run's full stdout/stderr is saved under a gitignored `tests/out/<scenario>/<machine>.log`.
9. (user) Scenarios, each on a fresh throwaway archive: S1 A then B; S2 B then A; S3 A, B, then A again. After each scenario the harness fetches the week page HTML (via a short `claude -p` Artifact read, or the URL if public) into `tests/out/<scenario>/week.html` and extracts the `roundup-data` block.
10. (user) Checks (`tests/check.py`, PASS/FAIL per line, nonzero exit on any FAIL): `devices` has exactly `root@machine-a` and `root@machine-b`; projects are exactly alpha-app and beta-tool, each with its machine in `devices` and its expected commit count (in-window only) and FE tokens; Misc sessions carry the right `device` and per-device Misc totals match expected; per-device totals (`sessions`, `fe_tokens`) match expected; `cap_pct` is 55 in S1 and S3 (newest wins; rerun without a value keeps 55) and 40 in S2; `window_start`/`token_window_start` equal across all contributions; S1 and S2 pools are identical ignoring `collected_at`, `features` naming and `cap_pct`; S3 equals S1 ignoring the same fields (rerun replaced, did not duplicate, A's data).
11. (user) Visual check: the harness opens `tests/out/S3/week.html` in a new Firefox window (per CLAUDE.local.md) so the user can see both projects, both devices in the Data sources drawer with their usage, and Misc attributed per machine.
12. (default) If the Artifact tool is unavailable in `claude -p` (Fact 5), `run.sh` opens one Windows Terminal window per container (`term-open.sh`) running `claude` interactively with the same prompt, and the user runs the three scenarios by hand; checks and visual step are unchanged.
13. (default) The harness tells the user at the end which throwaway artifacts were created (URLs) so they can delete them; it does not delete anything in the account.
14. (default) `tests/README.md` (≤30 lines): prerequisites, one command to run everything, what each scenario proves, cost note (each `claude -p` run spends real tokens on this account).
15. (default) Nothing in `skills/weekly-roundup/` outside `tests/` changes unless a check exposes a pooling bug; a bug fix is a separate, clearly described change the worker reports.

## Constraints
- Shell + Python 3 (stdlib only) for the harness, matching the skill's existing scripts; Dockerfile on Ubuntu 24.04; Claude Code installed via the official installer.
- Containers never see host paths other than the skill dir copy and the credentials file; no host `~/files` or `~/.claude/projects` mounts.
- `tests/out/` is gitignored. No commit by the worker unless asked.

## Acceptance criteria
- [ ] 1: `tests/setup_docker.sh` then `docker run hello-world` succeeds; second run is a no-op.
- [ ] 2, 3: `docker history` of the image shows no credentials layer; `grep -r <token prefix> tests/out` finds nothing.
- [ ] 4: `docker exec machine-a hostname` → `machine-a`; pool devices labelled `root@machine-a`, `root@machine-b`.
- [ ] 5, 6: inside each container `ls /root/files` shows only its own repo; `tests/expected.json` exists with per-machine totals.
- [ ] 7: host `skills/weekly-roundup/state.json` unchanged (`git diff` empty) and the real archive artifact's weeks list unchanged after the full run.
- [ ] 8, 9: `tests/out/S1..S3/*.log` and `week.html` exist; each log ends with an artifact URL.
- [ ] 10: `python3 tests/check.py` prints all PASS and exits 0.
- [ ] 11: Firefox window shows the S3 page with alpha-app, beta-tool, both devices and per-machine Misc in Data sources.
- [ ] 13, 14: final output lists throwaway artifact URLs; README has the one-command run line.

## Amendments
- 2026-10-11 "I want "Jet" usage and "Jaxon" usage to be grouped in the pie chart. Like it should list all the Jet projects then list all the Jaxon projects (or whoever has most usage at top, then whoever has less on the bottom)"
  - [ ] (user) On the week page, the pie chart and its legend group slices by person: all of one person's projects (and their Misc) together, then the next person's; the person with the most usage comes first.
