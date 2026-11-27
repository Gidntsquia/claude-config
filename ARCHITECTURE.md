# Architecture

The clone is the config: `./install.sh` links files from here into `~/.claude`, so an edit in either place is a change
to this repo. `test/run` checks that every path named here exists.

## Parts

| Part | Folder or file | New work goes |
|---|---|---|
| Installer | `install.sh`, `bin/merge-settings.py`, `bin/resolve-kept-edits.py`; guides `INSTALL.md`, `UPDATING.md` | a new installed item: a link in `install.sh` and a `--check` line |
| Installed global config | `CLAUDE.md`, `settings.json`, `statusline.sh` | `settings.json` is edited by the user, never by a Claude session |
| Agents | `agents/` (hand-off rules `agents/USAGE.txt`) | one `agents/<name>.md` per agent |
| Report writer | `agents/report-writer/`, `agents/evals/report-writer/` | build steps in the first, checks and golden reports in the second |
| Skills | `skills/` | `skills/<name>/SKILL.md`, its scripts beside it |
| Run scheduling | `skills/run-agent/`, `bin/run-agent` | `skills/run-agent/scripts/`, the MCP tools in `skills/run-agent/mcp/` |
| Hooks | `hooks/` (the usage guard, `hooks/usage-guard/`) | `hooks/<name>/`, wired in `settings.json` |
| Mods | `mods/defer-artifact/` | `mods/<name>/` |
| Evaluator tools | `local-tools/common/`, `local-tools/macos/`, `local-tools/wsl/` | by the system that can run it; Mac-only helpers never in `common/` |
| Assistant | `assistant/` | its server in `assistant/mcp/`, its guard hook in `assistant/hooks/` |
| Helper | `agents/helper.md`, `helper-mcp/` (reads the wiki, cloned into `wiki/`) | |
| Terminal setup | `bin/tmux-quad`, `iterm2/`, `wsl/` | per terminal or system |
| Tests | `test/run`, `test/quick/`, `test/machine/`, `test/docker/`, `test/helpers/`, `test/fixtures/` | `TESTING.md`, "Adding a test" |
| Test trust | `test/features.txt`, `test/faults/`, `test/escapes.txt`, `test/standins.txt`, `test/results/`, `test/lib/` | a row or patch beside the others |
| Release tools | `bin/release/` | run by hand before a release |
| CI | `.github/workflows/install.yml` | calls only `test/run` |
| Records | `ARCHITECTURE.md`, `TESTING.md`, `CHANGELOG.md`, `AGENTS.md`, `.claude/CLAUDE.md`, `README.md` | rewrite a stale line in place |
| Writing guides | `docs/` | |
| Sample project | `examples/first-project/` | |
| Retired tools | `bin/archive/` | |
| Plans and research | `plans/` (gitignored, this machine only) | |

## Decisions

<!-- At most 20 lines (blank ones not counted). Rewrite a replaced decision in place; git holds the history. -->
- One test command, `test/run`, locally and in CI, so a pass means the same thing everywhere.
- bats-core runs the tests: the maintained runner that works on bash 3.2 and Windows Git Bash.
- The feature list holds exact test counts, so a test cannot disappear without a diff that says so.
- Stand-ins in the quick tier must be compared with the real tool in the machine tier (`test/standins.txt`).
- Every test starts from a throwaway home; 11 errors reached a real Mac because tests began clean and faked what failed, so lived-in homes are tested too.
- An install never overwrites or backs up a file of the user's own; it says `kept yours`.
- The root `CLAUDE.md` is every installed user's global file; repo-only instructions live in `.claude/CLAUDE.md`.
- On a Mac the evaluator opens items in a separate Firefox, never moving the user's terminal or browser.

## Next

<!-- At most 10 lines. Delete a finished one. -->
- Vendor bats-core and its three libraries as submodules in test/vendor (until then bats comes from PATH).
- See CI pass on all three systems; Windows has not run the new tests.
- Test the update-by-claude flow without a real login, or keep `bin/release/rehearsal.sh` as a release step.
- Plant faults for the usage guard; compare the five unchecked stand-ins in `test/standins.txt` with the real tools.
- Fix report-writer printing a null figure two ways (`agents/report-writer/build.py`).
- Fix test-speedup naming the class, not the test, for Maven and Gradle, and `unknown` for Gradle- or pytest-only projects.
- Fix restore-sessions dropping a correction to a missing pane without saying so.
- Stop the helper server reading `.md` files outside the wiki through `../` (`helper-mcp/server.py`).
- Remove `win.sh geom` from the evaluator, or give the Windows-side tool one (`agents/evaluator.md`).
