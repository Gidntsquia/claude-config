# Testing
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
| run-agent | 329 | 275 | 178 | terminal-setup | 19 | 18 | 9 |
| usage-api | 3 | 2 | 4 | phone-pictures | in evaluator-tools | 11 | 15 |
| evaluator-tools | 140 | 71 | 73 | wsl-tools | 2 | 0 | 33 |
| windows-install | in install | 0 | 8 | helper | 0 | 0 | 13 |
| usage-guard | 286 | 0 | 9 | assistant | 0 | 0 | 15 |
| report-writer | 0 | 0 | 34 | doc-skills | 0 | 0 | 11 |
| restore-sessions | 0 | 0 | 32 | context-trims | 0 | 0 | 6 |
| test-speedup | 0 | 0 | 18 | test-runner | 0 | 11 | 61 |

Written by `bin/release/trust-report` from the tags and `test/results/`. Measured: faults 2026-11-28 02:17 AM ET on Darwin, commit 26853e3 with uncommitted changes; old bugs 2026-11-28 01:22 AM ET on Darwin, commit 26853e3; repeat 2026-11-28 03:01 AM ET on Darwin, commit 62a1d61. Faults not caught: restore-sessions/resume-without-model.
<!-- trust-report:end -->

## Run the tests
```
test/run                     # Quick tier: runs on every OS, uses no network and a throwaway home
test/run all                 # Quick, machine (real tools) and docker. Run it before a release
test/run --only <feature>    # One feature's tests. The ids are the first column of test/features.txt
```
The last line is `PASS <n> tests` or `FAIL <failed> of <n>`.

## Read a failure
```
FAILED run-agent: /run-agent time: a length of time after in counts from now [worker in 90m]
FAIL 1 of 632
grep -rn "a length of time after in counts from now" test/    # What the test printed is higher up, under "not ok"
```
Each failed test gets one `FAILED` line with its feature, its name and, for a test that loops over a case list, the failing case in brackets.

## Add a test
```
worker in an hour => 2026-10-22 19:00 | in an hour |    # A new input for a behaviour with a case list is one line in that list
# bats test_tags=feature:<id>                           # Otherwise copy a neighbouring @test with this line above it and rename it
test/run --only <id>                                    # It should fail before the code exists and pass after
cp test/quick/_template.bats test/quick/<id>.bats       # A new feature. It also needs a row in test/features.txt
bin/release/repeat 10                                   # A new test file has to pass this before it's committed
```
A new case or test for an existing feature edits no other file, and a bug that reached a real machine adds `,escape:<bug>` to the tag line.

## What a pass means
```
test/run all                      # CI runs quick on Linux, macOS and Windows, machine on Linux and macOS, docker on Linux
EVSHOW_LIVE=1 test/run machine    # Opens real Firefox windows on a Mac. Without it only CI does
bin/release/rehearsal.sh          # Covers what only a signed-in session shows (the usage API's success answer, Claude Code's hooks, mods, permissions)
```
A pass says every feature in `test/features.txt` behaved as its tests assert on the system that ran them, which leaves out WSL's Windows side, your own PATH, shell files and `~/.claude`, and any skipped machine test.
