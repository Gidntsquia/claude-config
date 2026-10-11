# weekly-roundup pooling test

Two Docker containers (`machine-a`, `machine-b`) with fake git repos and fake Claude sessions each run
`/weekly-roundup` for the current week against a throwaway Roundup Archive; `check.py` verifies the pooled data.

Prerequisites: WSL2 with sudo or `wsl.exe -u root`, Claude credentials in `~/.claude/.credentials.json`,
Windows Firefox. `setup_docker.sh` installs Docker Engine (`docker.io`) if missing.

Run everything: `skills/weekly-roundup/tests/run.sh`
Headless `claude -p` has no Artifact tool, so `cc.sh` drives interactive `claude` in tmux inside each container
(root needs `IS_SANDBOX=1` for `--dangerously-skip-permissions`). `run.sh --interactive` opens one terminal per
container instead, for driving the scenarios by hand.

Scenarios (each on a fresh archive):
- S1 A (cap 40) then B (cap 55): first run creates the page, second joins it; newest cap (55) wins.
- S2 B (55) then A (40): same pool in the other order; cap is 40.
- S3 A, B, then A again with no cap: the rerun replaces A's data, no duplicates; cap stays 55.

Each run also names who the usage belongs to with a different fuzzy spelling (A: "Jet" / "jett" / "jet Lee",
B: "Jaxson" / "jax"), so the checks prove they pool into one "Jet" and one "Jaxon".
Checks (`check.py`, nonzero exit on FAIL): devices, person per machine and pool people, per-project
device/commits/FE tokens, per-machine Misc, per-machine totals, cap, windows, S1==S2==S3 pools. Expected numbers:
`expected.json` (from `make_fixtures.py`).
Output: `out/` (gitignored): logs per run and `week.html` per scenario. S3's page opens in Firefox.

Cost: each scenario is 3-4 full claude runs (about 11 interactive runs in all) on this account. Throwaway artifacts are
listed at the end; delete them yourself. The real archive and host `state.json` are never touched.
