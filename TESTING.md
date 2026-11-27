# Testing
## Run the tests
```
test/run                     # the quick tier: every OS, no network, nothing of yours touched
test/run all                 # quick, machine (real tools) and docker: before a release
test/run --only <feature>    # one feature's tests; the ids are the first column of test/features.txt
```
The last line is `PASS <n> tests` or `FAIL <failed> of <n>`. Nothing else is an argument.

## Read a failure
```
FAILED install: install.sh --check prints PASS for every link after a fresh install
FAIL 1 of 800
```
A failing run ends with one such line per failed test: the feature that broke, then the test's name. Search `test/`
for the name; what the test printed is higher up, under `not ok`. `FAILED lint:`, `FAILED features:` and
`FAILED records:` come from the checks made before any test runs; each says the file, the line and what to change.

## Add a test
1. Open the feature's file in `test/quick/` and copy a neighbouring `@test`.
2. Keep the line above it, `# bats test_tags=feature:<id>`, and rename the test after what a user sees.
3. Run `test/run`; see it fail before the code exists, pass after.

No other file is edited. A new feature: a row in `test/features.txt` (`<id> | <description>`) and a copy of
`test/quick/_template.bats`. A bug that reached a real machine: a test also tagged `escape:<id>`; a machine test of a
stand-in against the real tool: `standin:<id>`. Each test's verdict (keep, merge, delete): `test/review.md`.

## What a pass means
Every feature in `test/features.txt` behaved as its tests assert, on the system that ran them (CI: Linux, macOS and
Windows for quick; Linux and macOS for machine; Linux for docker), from throwaway homes. Not covered: what only a
signed-in session shows (the usage API's success answer, Claude Code's hooks, mods and permissions:
`bin/release/rehearsal.sh`); real windows (Firefox and iTerm2 open only with `EVSHOW_LIVE=1` or in CI; WSL's Windows
side has no runner); your own Mac's PATH, shell files and `~/.claude`; a skipped machine test (its line says why).

## Why each piece exists, and how far to trust a pass
<!-- trust-report:start -->
| Piece | Why it is kept | Today |
|---|---|---|
| Lint, before any test | a fixed wait, the network, your real home or a fixed port made tests flaky or unsafe | refused by rule: the run fails |
| Tiers | quick must run anywhere in minutes; real tools and Docker are slower and not on every system | quick, machine, docker |
| Feature tags | a failure names the feature, and a feature whose last test is deleted fails the run | 26 of 26 features |
| Planted faults (`bin/release/faults`) | a test that stays green when its feature is broken proves nothing | 77 of 78 planted faults caught |
| Old bugs replayed (`bin/release/redgreen.sh`) | a past error's test must fail again when its fix is taken out | 12 of 12 went red with the fix removed (12 have a test) |
| Repeated runs (`bin/release/repeat <n>`) | a test that passes only sometimes, or only in one order, is found before you are | 10 of 10 shuffled runs agreed |
| Stand-in comparisons (`standin:<id>`) | 11 errors reached a real Mac because a stand-in differed from the tool it stood for | 17 compared in the machine tier |
| Record caps (`FAILED records:`) | this page, `ARCHITECTURE.md` and `.claude/CLAUDE.md` stay short and name only real paths | this page: at most 80 lines |

Written by `bin/release/trust-report` from the tags and `test/results/`. Measured: faults 2026-11-27 06:40 PM ET on Darwin, commit 3255399; old bugs 2026-11-27 06:09 PM ET on Darwin, commit 8c957cf; repeat 2026-11-27 02:05 PM ET on Darwin, commit 978e0de. Faults not caught: restore-sessions/resume-without-model.

| Old bug that reached a real machine, its fix taken out again | Test that went red |
|---|---|
| install.sh linked hooks/usage-guard to itself on an older install | updating a pre-v1.3 layout: hooks becomes a real folder of links and the clone keeps its own |
| a missing guard script blocked every tool | usage-guard script missing: each of the 7 hook commands exits 0 |
| a moved clone's broken links were counted as the user's own files | moved clone: plain ./install.sh from the new path relinks everything and calls nothing yours |
| a pull would have taken away iTerm2's preferences | update from v1.2.1: iTerm2 points at the clone until install.sh runs, and not after |
| --check failed on kept untracked files | your own files: an untracked file with a personal path is a warning naming it, not a failure |
| the run-agent tests failed on macOS's BSD tools | an agent's run with no pane left waits, opening no window, session or claude |
| the usage API call always failed on macOS | the real usage API answers a made-up token with HTTP 401 over verified TLS |
| a job scheduled after a usage window ran late or was skipped | a window run fires at its stored time although the API moved on, until 60 s later |
| two jobs scheduled in the same second got one id | three handoffs at the same instant get three job ids, each for its own folder |
| a Keychain Not Found dialog came from a throwaway home | fresh install: install.sh exits 0 and install.sh --check passes |
| the Windows CI job broke unseen because CI ran only at a release | windows: the test workflow runs the quick tier on Windows for every push to main and pull request |
| on Windows without symlinks a rerun after an update kept the old copies | windows: a rerun after an update refreshes unedited copies and keeps edited ones |

| Feature | checks on main | tests after the port (ab957fb) | now | Feature | main | port | now |
|---|---|---|---|---|---|---|---|
| install | 276 | 111 | 107 | weekly-roundup | 18 | 18 | 21 |
| user-settings | in install | in install | 8 | defer-artifact | 16 | 0 | 5 |
| updates | in install | in install | 45 | update-by-claude | 0 | 0 | 3 |
| install-check | in install | in install | 23 | statusline | 0 | 0 | 10 |
| installed-text | 3 | 3 | 4 | agent-prompts | 0 | 0 | 13 |
| run-agent | 329 | 275 | 255 | terminal-setup | 19 | 18 | 9 |
| usage-api | 3 | 2 | 4 | phone-pictures | in evaluator-tools | 11 | 15 |
| evaluator-tools | 140 | 71 | 71 | wsl-tools | 2 | 0 | 33 |
| windows-install | in install | 0 | 8 | helper | 0 | 0 | 13 |
| usage-guard | 286 | 0 | 9 | assistant | 0 | 0 | 15 |
| report-writer | 0 | 0 | 34 | doc-skills | 0 | 0 | 11 |
| restore-sessions | 0 | 0 | 32 | context-trims | 0 | 0 | 6 |
| test-speedup | 0 | 0 | 18 | test-runner | 0 | 11 | 58 |
<!-- trust-report:end -->
