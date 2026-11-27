# Testing

```
test/run [quick|machine|docker|all]    # quick is the default
```

The last line is `PASS <n> tests` or `FAIL <failed> of <n>`.

## What a pass means

Every listed feature behaved as asserted, in the listed environments and starting states.

- Features: `test/features.txt` (one line each, with how many tests cover it). A run fails when a test is added or
  deleted without that number changing.
- Environments: the machine you ran it on; in CI, Linux, macOS and Windows for `quick`, Linux and macOS for
  `machine`, Linux for `docker`.
- Starting states: the ones the tests build in a throwaway home (fresh, existing settings, your own files, a moved
  clone, older layouts, missing scripts, Windows without symlinks). No test reads or changes your own home.

## Trust report

Rewritten by `test/run --report` from `test/features.txt`, `test/escapes.txt`, `test/standins.txt` and
`test/results/`. A number is as old as the line under the table says.

<!-- trust-report:start -->
| Number | Value | Answers |
|---|---|---|
| Features with automated tests | 25 of 26 | completeness |
| Planted faults caught | 70 of 75 | sensitivity |
| Past real-machine errors with a test | 12 of 12 | fidelity |
| Repeated shuffled runs that agreed | 3 of 3 | consistency |
| Stand-ins with a test against the real tool | 16 of 21 | fidelity |

Features with no automated test:

- `update-by-claude`: manual: bash bin/release/rehearsal.sh

Stand-ins never compared with the real tool: usage-api wsl claude-hooks claude-mods claude-permissions (reasons in test/standins.txt).

Faults measured 2026-11-27 10:16 AM ET on Darwin, commit 1a2bddb with uncommitted changes.

- missed restore-sessions/resume-without-model
- missed statusline/unlock-time-utc
- missed update-by-claude/local-edits-discarded: the feature has no automated test
- missed update-by-claude/prerelease-picked: the feature has no automated test
- missed update-by-claude/relink-step-missing: the feature has no automated test
- short usage-guard: 0 of 3 faults planted

Past errors seen red with their fix removed: 12 of 12, measured 2026-11-27 08:57 AM ET on Darwin, commit 3c00fa4.

Repeat measured 2026-11-27 09:16 AM ET on Darwin, commit 3c00fa4 with uncommitted changes.
<!-- trust-report:end -->

How each number is made:

| Number | Command |
|---|---|
| Planted faults caught | `test/run --faults` (three patches per feature in `test/faults/<id>/`, each in a scratch clone; the feature's tests must fail) |
| Past errors seen red | `bin/release/redgreen.sh` (macOS, about 25 minutes; commit first) |
| Repeated runs that agreed | `test/run quick --repeat <n> [--seed <s>]`; weekly in CI as `repeat`, 300 runs on 10 runners, added up by `test/run --agree` |
| Report | `test/run --report` |

## What a pass does not cover

Still open from the November 2026 Mac update, where 11 errors reached a real Mac past green tests:

- Stand-ins that differ from the real thing where no test compares them: the success answer of the usage API with a
  live login token; a Keychain dialog in a desktop session; a laptop sleeping or waking during a scheduled run; WSL's
  Windows side; Claude Code's hook, mod and permission handling (reasons in `test/standins.txt`).
- Real Firefox windows and the real iTerm2: opt-in (`EVSHOW_LIVE=1`) or CI-only machine tests.
- Not a real person's Mac: Homebrew PATH, your shell's rc files, a `~/.claude` with sessions, history and plugins.
- Claude following `UPDATING.md` from the pasted README sentence: only `bin/release/rehearsal.sh`, never in CI.
- Stash and merge on a clone with local commits and diverged history; older layouts nobody wrote down; links nested
  more than two deep; a clone moved some other way than `mv` of the whole folder.
- Every `settings.json` hook with its file missing is only checked for the hooks the tests name.
- Wording tests pin prose; they do not show the prose is right.
- `hooks/usage-guard/` has no planted faults: the guard refused the session that tried to read its code. The status
  line's unlock time is likewise not checked, so its planted fault is missed.
- Resuming a session with its model (`restore-sessions` `apply.sh`) needs bash 4: the test skips on macOS, and the
  planted fault there is caught only on Linux.
- Report cards are drawn for real only where Playwright is installed (`PLAYWRIGHT_DIR`); elsewhere that test skips.
- Two evaluator picture tests (line range, colours) replace the repo's `phone-bidi.py` with a file copy; the real
  pictures are checked only by the `phone-pictures` tests.

Some machine tests run only where their tool exists and say why they skipped: GNU `ps`, `pgrep`, `date`,
`journalctl` (Linux), Maven, RSpec, Docker. A pass with skips did not compare those.

## The tiers

| Tier | Folder | What it uses |
|---|---|---|
| quick | `test/quick/`, pytest files in `skills/`, `hooks/`, `helper-mcp/`, `assistant/` | throwaway homes and stand-ins; no network, no fixed waits, no windows |
| machine | `test/machine/` | the real tools: keychain, usage API over TLS, Firefox, tmux, `claude`; a missing tool is a skip that says why |
| docker | `test/docker/` | a fresh ubuntu:24.04 container |

Every run first lints the test files and compares the tags with `test/features.txt`, `test/escapes.txt` and
`test/standins.txt`. `test/run --only <feature>` runs one feature's quick and machine tests.

## Adding a test

1. Copy the case in `test/quick/_template.bats` into the file for the feature (shared functions go in
   `test/helpers/`, fixtures in `test/fixtures/`).
2. Tag it `# bats test_tags=feature:<id>` and raise that feature's number in `test/features.txt`.
3. Run `test/run`.

## The escape rule

An error that got past the tests to a real machine gets an id in `test/escapes.txt`, a test tagged `escape:<id>` that
fails without the fix, and a row in `bin/release/redgreen.sh` that shows it failing.

## Checklist for whoever writes a test (Claude included)

1. Write the test first and show it failing.
2. One behavior per test, named after what a user sees.
3. Assert on outputs and files, never on internal calls.
4. No new stand-in without a machine test against the real tool (`standin:<id>`, listed in `test/standins.txt`).
5. No edit or deletion of an existing test in a change to the code it tests unless the commit message says why.
6. Run the new test 10 times.

## Differences from the old test scripts

The old shell scripts were ported to bats in November 2026; every old check maps to a test.

- Fixed waits became polling with a deadline. Scheduled-run tests are slower (about 520 s for run-agent run one file
  after another, against 237 s).
- "SKIP no Firefox" became a skip with a reason on each test; iTerm2 tests are skipped off macOS.
- Install: a missing `/usr/bin/python3` in the stock scenario now fails instead of passing with a skip line; CI
  requires the old tags, so a shallow clone fails.
- Install: labels read `.claude` for `~/.claude`; the keychain comparison runs in each scenario.
- Evaluator tools: process-exit checks wait up to 5 s; each phone-picture test checks only its own Firefox; the live
  tests use the repo's tools and need `EVSHOW_LIVE=1`.
- run-agent: the "default tmux server" checks use a server of the same shape in a test folder, never yours; three
  concurrent handoffs are held together by a fixture, not by timing; one prompt was reworded for the lint.
