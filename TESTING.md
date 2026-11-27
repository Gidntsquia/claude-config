# Testing

## Run the tests

```
test/run                     # the quick tier: every OS, no network, nothing of yours touched
test/run all                 # quick, machine (real tools) and docker: before a release
test/run --only <feature>    # one feature's tests; the ids are the first column of test/features.txt
```

The last line is `PASS <n> tests` or `FAIL <failed> of <n>`. Nothing else is an argument.

## Read a failure

A failing run ends with one line per failed test, then the count:

```
FAILED install: install.sh --check prints PASS for every link after a fresh install
FAIL 1 of 800
```

The word after `FAILED` is the feature that broke; the rest is the test's name. Search `test/` for the name to find
the test; what it printed is higher up, under `not ok`. `FAILED lint:`, `FAILED features:` and `FAILED records:` come
from the checks made before any test runs; each says the file, the line and what to change.

## Add a test

1. Open the feature's file in `test/quick/` and copy a neighbouring `@test`.
2. Keep the line above it, `# bats test_tags=feature:<id>`, and rename the test after what a user sees.
3. Run `test/run`; see it fail before the code exists, pass after.

No other file is edited. A new feature is one more row in `test/features.txt` (`<id> | <description>`) and a file
copied from `test/quick/_template.bats`. A bug that reached a real machine gets a test also tagged `escape:<id>`;
a machine test that compares a stand-in with the real tool is also tagged `standin:<id>`. Never loosen or delete a
test to get a pass without saying why in the commit message.

## What a pass means

Every feature in `test/features.txt` behaved as its tests assert, on the system that ran them (CI: Linux, macOS and
Windows for quick; Linux and macOS for machine; Linux for docker), starting from throwaway homes: fresh, with your
own settings and files, a moved clone, older layouts, missing scripts, Windows without symlinks.

A pass does not cover:

- what only a signed-in session shows: the usage API's success answer, Claude Code's hooks, mods and permissions, and
  Claude following `UPDATING.md` by itself (`bin/release/rehearsal.sh`, before a release);
- real windows: Firefox and iTerm2 open only with `EVSHOW_LIVE=1` or in CI; WSL's Windows side has no runner;
- your own Mac: its PATH, shell files, and a `~/.claude` full of sessions and plugins;
- a skipped machine test (the line says which tool was absent); wording tests pin prose, not its truth.

## Why each piece exists

| Piece | Why it is kept |
|---|---|
| Lint, before any test | a fixed wait, the network, your real home or a fixed port made tests flaky or unsafe; refused by rule |
| Tiers | quick must run anywhere in minutes; real tools and Docker are slower and not on every system |
| Feature tags | a failure names the feature, and a feature whose last test is deleted fails the run |
| Planted faults (`bin/release/faults`) | a test that stays green when its feature is broken proves nothing |
| Repeated runs (`bin/release/repeat <n>`) | a test that passes only sometimes, or only in one order, is found before you are |
| Stand-in comparisons (`standin:<id>`) | 11 errors reached a real Mac because a stand-in differed from the tool it stood for |
| Record caps (`FAILED records:`) | this page (80 lines), `ARCHITECTURE.md` and `.claude/CLAUDE.md` stay short and name only real paths |

## How far to trust a pass

Rewritten by `bin/release/trust-report` from the tags and the last recorded runs in `test/results/`.

<!-- trust-report:start -->
| Question | Number | Made by |
|---|---|---|
| Does every feature have a test? | 26 of 26 features | `test/run` |
| Does a broken feature turn its tests red? | 73 of 75 planted faults caught | `bin/release/faults` |
| Would the old bugs be caught today? | 12 of 12 went red with the fix removed (12 have a test) | `bin/release/redgreen.sh` |
| Does the same code give the same answer? | 10 of 10 shuffled runs agreed | `bin/release/repeat <n>` |
| Do the stand-ins behave like the real tools? | 17 compared in the machine tier | tests tagged `standin:<id>` |

- `test/results/faults.txt`: measured 2026-11-27 04:21 PM ET on Darwin, commit 4bbcc43.
- `test/results/escapes.txt`: measured 2026-11-27 11:38 AM ET on Darwin, commit d0eb9ee.
- `test/results/repeat.txt`: measured 2026-11-27 02:05 PM ET on Darwin, commit 978e0de.
- Faults not caught: restore-sessions/resume-without-model statusline/unlock-time-utc usage-guard.
<!-- trust-report:end -->
