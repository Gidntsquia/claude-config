Merge this into the repo's CLAUDE.md, filling in the four commands. Keep the wording and keep **Which tests to run** first — that section is the reason this block exists. An agent that reads only the writing rules will still run the whole suite after a one-line edit, which is the single biggest source of wasted test time in a repo that has already been tiered.

Leaving a `<...>` placeholder unfilled makes the section worse than absent: the agent can't run the narrow command, so it falls back to the full suite. The consolidated-file paragraph under **Before adding a test** has two more slots, `<CONSOLIDATED_FILE>` and `<THE EXPENSIVE THING>` — fill them if step 3b consolidated, and delete the paragraph outright if it didn't. A rule pointing at a file that doesn't exist is worse than no rule.

This block is only half the policy. `references/enforcement.md` is the half that enforces it — ship both, because an agent that never reads CLAUDE.md still hits the hook.

---

## Tests

### Which tests to run

Match the run to the change. **The default is the narrowest run that covers what you touched.** The full suite is a specific step with specific triggers, not the safe choice to reach for every time.

| what you changed | what to run |
|---|---|
| a doc, comment, README, or log string | nothing |
| one function, or one file | that file's tests: `<FILE_CMD>` |
| a few files inside one module | those files' tests, or `<CHANGED_CMD>` |
| shared code, a fixture, a helper the suite imports | `<FAST_CMD>` |
| a dependency, lockfile, CI config, or test-runner config | `<FULL_CMD>` |
| nothing — you are about to push or open a PR | `<FULL_CMD>` |

These override the table:

- **A small change gets a small run.** Running the full suite to check a one-line edit isn't caution, it's the default being ignored. If you can name the file you changed, you can name the tests to run.
- **After a failure, re-run that test, not the suite.** Widen only once it's green, and only one step up the table.
- **At most one full-suite run per session**, at the end. Having already run it is a reason not to run it again, not a reason to be sure.
- **The pre-push hook and CI run everything before anything merges.** Wide breakage is caught there. Mid-change your job is the narrow run; you are not the last line of defense.
- **Don't run tests to prove unrelated code still works.** That is what the tiering is for.

A `PreToolUse` hook blocks whole-suite commands and prints the narrow one to run instead. When you see `BLOCKED:`, run what it suggests. `TS_FULL=1 <cmd>` overrides it and exists for the four cases above — the user asked, the runner config or a dependency changed, or you are about to push. It is not the way past a block you'd rather not think about.

If you genuinely can't tell which tests cover a change, run `<CHANGED_CMD>` — not the full suite.

### Before adding a test

**A good test is a fast test.** Runtime is not a neutral property — it is part of
the test's cost, paid on every run by every person and every agent. A test that
takes ten seconds to tell you what a hundred-millisecond test already told you is
not thorough, it is charging rent. Before adding one, check that it earns its
place.

**A test that needs `<THE EXPENSIVE THING>` to actually run belongs in
`<CONSOLIDATED_FILE>`, asserted against one of the shared runs already at module
scope there — not a fresh run of its own, and not a new file.** This is the rule
that keeps the suite fast. Standing the expensive thing up again to check that a
flag reached settings, a file got written, or a mode label is right re-pays the
whole cost for an assertion a shared run already supports.

- One test per behavior, not per branch of the same code path. Tests differing only in an input literal should be one parameterized test.
- Don't test framework, standard library, or ORM behavior.
- Don't add characterization tests for code written in the same change.
- Search the suite for existing coverage before adding a test.
- New tests run in under 100ms unless tagged slow or integration. Anything touching network, disk, or a real database gets the tag.
- Fake clock over sleeping. Stub over live service. Fixtures get the widest scope that's still correct.
- Deleting a test that no longer earns its runtime is a normal part of a change — do it, and say so in the summary.

### Commands

- One file: `<FILE_CMD>`
- Changed files only: `<CHANGED_CMD>`
- Fast tier: `<FAST_CMD>`
- Full suite (union of fast and slow): `<FULL_CMD>`
