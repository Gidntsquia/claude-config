---
name: test-speedup
description: Make a slow test suite fast. Measures the suite, then wires parallel execution, changed-files-only local runs, fast/slow tiering, fixes to the slowest tests, and both halves of the policy that keeps it fast — a CLAUDE.md section and a PreToolUse hook that blocks whole-suite runs — so the agent stops running everything after every small change and stops writing redundant tests. Also finds the retread: the expensive thing (engine, browser, container, seeded DB) stood up over and over to check plumbing one shared run already proves, which is usually the largest number in the pass — measured and proposed, then folded into a single file on the user's yes. Use this whenever tests or CI feel slow — including when the user is just complaining ("the tests take forever", "CI is so slow now", "I stopped running the suite") rather than asking for a fix, when a repo has piled up agent-written tests, when Claude keeps running the full suite for a one-line edit, or when asked to speed up, profile, parallelize, tier, consolidate, deduplicate, or triage a test suite. Prefer it over ad-hoc timing: it measures first, and the infrastructure steps never lose a test. Runs end to end; pauses only to get approval before cutting any test.
argument-hint: "[repo path, defaults to cwd] [quick]"
---

# Test speedup

Cut the wall-clock cost of the test command. Steps 1–3 and 4 are infrastructure
and policy and never lose a test. Step 3b is the one that removes duplication,
and it cuts nothing without the user's explicit yes.

A good test is a fast test. Runtime is part of a test's cost, paid on every run
by every person and every agent — so a suite that re-runs the expensive thing
fourteen times to check fourteen bits of plumbing is not thorough, it is
wasteful, and saying so with numbers is part of the job.

Run end to end. Stop only where a step says stop.

## What counts as done

Three conditions. All three get stated in the report, met or missed.

**The fast command finishes in under 60 seconds and under a fifth of the
baseline.** Both, not either. A 12-minute suite cut to a 2-minute fast tier is
a 6x win that still misses: two minutes is long enough that the agent and the
human each stop running it, which puts the repo back where it started.

**The guard is installed and passes its self-test** (`references/enforcement.md`).
Tiering is the mechanism; routing is what makes it pay. A repo can be perfectly
tiered and lose the entire gain to an agent that keeps typing the full-suite
command, and a CLAUDE.md paragraph on its own does not stop that.

**The retread is measured and put to the user** (step 3b). Most slow suites are
not slow because any one test is slow. They are slow because the same expensive
thing — the engine, the browser, the container, the migrated database — is stood
up over and over to check plumbing that one run already proved. Tiering hides
that cost behind a marker; the union still pays it. You are not done having only
moved the bill.

The union time matters much less **once the retread is gone** — it runs on push
and in CI, off the critical path. Optimize the command that gets typed fifty
times a day, but do not use "the union is off the critical path" as a reason to
leave a 10x duplication in it.

A good test is a fast test. Runtime is not a neutral property of a test; it is
part of its cost, paid every run by every person and every agent. A test that
takes ten seconds to tell you what a hundred-millisecond test already told you
is not being thorough — it is charging rent.

Measure it, never infer it: `scripts/measure.sh time -- <FAST_CMD>` is cheap by
construction and does **not** count against the full-suite budget. A report
quoting a full-suite improvement while never timing the command the agent
actually runs is the main way this pass ships a result nobody feels.

Under target after step 3 → you still owe step 3b's retread measurement, then go
to step 5; skip step 4's rounds. Still over when step 4's ladder runs out → say
so plainly, name the three biggest remaining costs and what each would take. An
honest miss is useful.

## Run budget and overlap

**Three full-suite runs, total: baseline, post-parallel, final union.** Nothing else runs the whole suite — every other check is collect-only or a named subset. A fourth run is a bug, not thoroughness.

Subset timings are not full runs and are not budgeted: `measure.sh time -- <cmd>` on the fast tier, the changed-files command, or one file costs seconds and is how step 3 and step 4 know whether they are done. Take them freely — one at a time, since they share the lock.

**Per-test times from a parallel run are contention-inflated — never tier or
prioritise from them.** A `baseline` profile is taken with every worker
saturating the box, so a test's reported duration includes it waiting for CPU.
Files that looked like 45s, 41s and 34s in one parallel log measured 7s, 15s and
21s run alone — a different ordering, and the parallel log's was the wrong one.
Before deciding what to move or fix, time the candidates individually:

```
for f in <test files>; do b=$SECONDS; <run one file> >/dev/null 2>&1; echo "$((SECONDS-b)) $f"; done
```

Serial, cheap, unbudgeted — background it and work in its shadow. (On macOS
`/usr/bin/time -p` indents its output, so `awk '/^real/'` silently matches
nothing and every timing comes back empty; use the shell's own `SECONDS`.)

**Every one of those runs goes in the background, and you keep working while it runs.** The runs are the wall clock; all the analysis, drafting, and runner-invisible edits belong in their shadow, not after them. Launch with Bash `run_in_background: true` and `RESULT_FILE` set:

```
RESULT_FILE=$TMPDIR/ts-baseline.txt scripts/measure.sh baseline 50
```

The result block ends with a `DONE` line — that sentinel is how you tell a finished run from a partial file. Pick the numbers up from the task notification or by reading `RESULT_FILE`.

### While a run is in flight

Do the work the runner cannot see:

- Read the one stack reference; inspect CI config, hook infra, existing CLAUDE.md, `git log`.
- Write and commit **runner-invisible files**: CLAUDE.md, `.github/workflows/*`, `.husky/*`, `.pre-commit-config.yaml`, docs. Leave command strings you don't know yet as placeholders and fill them during a later run's shadow.
- Draft — do not apply — the config and test-file edits the next step needs.
- Draft the report.

Never, while a run is in flight:

- **Edit a file the runner reads.** `pytest.ini`, `pyproject.toml`, `setup.cfg`, `tox.ini`, `conftest.py`; `package.json`, `jest.config.*`, `vitest.config.*`; `.rspec`, `Gemfile`; `go.mod`, any `*_test.go`; `Cargo.toml`, `.config/nextest.toml`; `build.gradle*`, `gradle.properties`, `pom.xml`; and every test source file. Editing these mid-run gives you a number for a tree that no longer exists.
- **Install a dev dep.** A new pytest plugin landing during collection breaks the run you are measuring.
- **Start a second test process.** `measure.sh` takes an exclusive lock and exits 4 rather than let you; two runners contend for CPU and the timing becomes fiction. `measure.sh unlock` clears a lock left by a killed run.
- **Anything CPU-heavy** — a build, a full-repo grep, a mutation pass. Same reason.
- **`git checkout`, `git reset`, or a revert.** Committing already-written runner-invisible files is fine; changing the working tree under a running suite is not.

Never end a turn, and never write the report, with a run still in flight. Join first.

`quick` in `$ARGUMENTS` → stop after rung 1 of step 4 and drop to two runs. Step 3b still measures the retread and still reports the number — that is a grep and one timed call, and it is usually the largest finding in the pass. `quick` skips the folding work, not the measurement.

## 0. Preflight

Target dir: `$ARGUMENTS`, else cwd. Detect each stack by its **test-runner dependency**, not by marker file — a `package.json` for prettier is not a test stack.

| runner | reference |
|---|---|
| pytest | `references/python.md` |
| jest, vitest | `references/node.md` |
| go test | `references/go.md` |
| cargo test, nextest | `references/rust.md` |
| rspec, minitest | `references/ruby.md` |
| gradle, maven | `references/jvm.md` |

The guard install is stack-independent: `references/enforcement.md`, read once in step 1's shadow.

Confirm with `scripts/measure.sh detect`. No tests → say so and stop. Unlisted runner → same steps with that runner's own flags; say in the report it was improvised.

Several stacks → **measure them one at a time**, largest first; concurrent baselines contend and both numbers are wrong. But stack B's reference reading and wire-up belong in the shadow of stack A's run, same as everything else.

Clean worktree required (`git status --porcelain` empty) — dirty → stop, ask the user to commit or stash. Not a git repo → note it, skip the CI/hook wire-up.

Commit after each step. Guardrail 3's revert is a `git reset` of that one commit — between runs, never during one.

## 1. Baseline — run 1 of 3

Launch `scripts/measure.sh baseline 50` in the background **first**, before reading anything. One execution prints `RUNNER`, `WALL_SECONDS`, `EXIT`, `COUNT`, and the 50 slowest tests. 50, not 25: step 3 budgets against this list, and a top-25 on a four-figure suite usually accounts for too little of the wall clock to decide anything. Don't also call `run`, `count`, or `profile` — they re-execute the suite for numbers you already have, and the lock will refuse anyway.

Capped at 15 minutes via whichever of `timeout`/`gtimeout` exists (stock macOS has neither, in which case it runs uncapped and says so). Override with `CAP_SECONDS`. Exit 3 means the stack isn't covered — fall back to the reference's commands, still one pass, still backgrounded.

**In its shadow:** read the stack reference and `references/enforcement.md`. Inspect CI, hook infra, and any existing CLAUDE.md test section. Write and commit the CI changes (fast tier on push, full suite plus slow tier on PR and main — never reduce what runs before a merge), the git pre-push hook if hook infra already exists (none → propose it in the report, don't install one), and the `references/policy.md` block merged into CLAUDE.md with its four `<CMD>` placeholders still unfilled.

Also in this shadow, wire the **PreToolUse guard** per `references/enforcement.md`. Check `~/.claude/hooks/full-suite-guard.sh` and `~/.claude/settings.json` first: installed globally → the only thing this repo needs is the `.claude/test-commands.sh` stub, which is the guard's on switch. Otherwise install the repo copy, the stub, and the merged `settings.json` entry. All of it is runner-invisible, so it is safe here. The guard is what makes the policy hold — it blocks a test command that names no path, no filter and no tier, and hands back the narrow command instead. Prose asks; the hook decides.

Decide, on paper, the parallel mechanism and the tier mechanism from the reference.

**Join, then record** the exact command string, wall time, count, pass/fail, and the slow list. `COUNT=unknown` (jq missing, or an improvised runner) → say so and compare pass/fail only.

- Red baseline → rerun **only the named failures**, not the suite. Still red → stop and report; changes can't be verified against a broken suite. Green on rerun → flaky: record the flaky set, exclude it from every later comparison. Otherwise a flake gets blamed on this skill's edits and reverts good work.
- Over the cap → count via collect-only, treat pass/fail as unknown, compare only counts from here on.
- No per-test timing in the output → note it, skip step 4.

## 2. Parallelize — run 2 of 3

Between runs, so config edits and installs are safe now. Parallel setting into the config file, not the command line, so it applies to the default command. **Parallelism only — no tier filter yet**, else this step's number measures a tiered suite. Install dev deps with the repo's own package manager; on failure skip this step and report it. Report every install — they change the environment, not the diff.

Already at a sane parallel setting (jest and vitest default to parallel) → change nothing, skip this run, carry the baseline number forward, and say so. Don't spend a run confirming a config you didn't touch.

Otherwise launch `scripts/measure.sh baseline 50` in the background again. This one run is the after-number, the correctness check, and a fresh profile of a now-parallel suite — which is the profile step 4 should work from, since parallelism reorders the tail.

**In its shadow:** draft the tier markers from the baseline profile, draft the slow-tail fixes, draft the report. Written to disk only after the join.

**Join:**

- count and pass/fail match baseline → commit
- new failures → shared state; apply the isolation fallback in the stack reference, then rerun **only the failing files**
- still red → revert, list the colliding tests, continue

Then check the number, not just the exit code. On a box with 4+ cores, parallelism that bought less than 2x means something is serializing the suite — one huge test file under `--dist loadfile`, a session-scoped DB lock, a module-level fixture every worker rebuilds, `--runInBand` still in a script, or worker startup dominating a short suite. Diagnose it here from the profile; a suite that won't parallelize won't be rescued by tiering either.

## 3. Tier — no full run

Marker mechanism, slow excluded by default, plus an explicit slow-tier command and a **union command** that runs everything.

**Mark to the target, not to taste.** The profile is the top 50, not the whole suite, so budget against the total: start from `WALL_SECONDS`, subtract each test as you move it, and keep going down the list until the remainder is under target. Every test you move needs a reason visible in the profile — IO, network, DB, sleep, a container start, a fixture rebuild. A test that is merely slow with no such reason is a step 4 candidate, not a tier candidate: moving it hides the work instead of removing it, and the union pays for it anyway.

Three tests owning half the wall clock is the good case. If instead the tail is flat — no test dominates, the time is spread across thousands of sub-100ms tests — tiering cannot reach the target and step 4's ladder is the whole answer. Say so and don't mark 400 tests to force the number.

Widen the default command too: whatever the repo habitually types — `npm test`, `make test`, the `test` script — should now run the fast tier, with the union under a second, explicitly named target. That single line beats every paragraph of policy, because it needs nobody to read anything.

Two checks, both cheap, both before step 5 pays for a mistake:

- Union count == baseline count, collect-only. (Step 3 is still coverage-neutral — this check runs before 3b has cut anything, so baseline is the right number here.) Take it with the **union command's own** collect form (`pytest -m '' --collect-only -q`, `go test -tags=integration -list '.*' ./...`, and so on) — bare `measure.sh count` uses the runner's defaults, which you just taught to exclude the slow tier, so it answers the wrong question from here on. Not fast + slow — those sum to baseline only when the tiers are disjoint, and with Go build tags or Rust `#[ignore]` the slow command is a superset. A short union means tests fell through every filter.
- `scripts/measure.sh time -- <FAST_CMD>`: the number this pass is actually for. Record it. Under target → step 5. Over → step 4.

## 3b. Consolidate the retread — no full run

Tiering moved the bill. This step is where it gets cancelled, and it is usually
the largest number in the whole pass: a suite that tiers from 67s to 1s can
still have a 158s union, and the same work consolidates that union to 13s.

**Cutting tests is the user's call, not yours.** Everything up to here is
infrastructure — reversible, coverage-neutral, done without asking. This step
removes tests. Measure it, put it to the user with real numbers and a named
cost, and cut only what they approve. Do not delete a test on your own judgment
that it looked redundant, and do not skip the measurement because you assume
they will say no.

### Find the expensive primitive

One thing in the repo is expensive to stand up: an engine context, a browser, a
container, a seeded database, a compiled fixture. Find it, then count how many
times the suite pays for it:

```
grep -rc '<the expensive call>' <test dir> | grep -v ':0'
```

Count call sites, not files. Fourteen calls in one file is the finding; "this
file is slow" is not. Then time one call in isolation — a primitive that costs
20ms called 143 times is not your problem, and a primitive that costs 2s called
14 times is the whole problem.

### Sort what you find into three piles

- **Load-bearing.** The test asserts something about the expensive thing itself
  — battle mechanics, query planning, render output. Keep. These are the spec,
  and an end-to-end test does not cover them just by running the same code.
- **Retread.** The test stands the expensive thing up to check *plumbing around
  it*: that a report got written, a checkpoint resumed, a flag reached settings,
  a mode label is right. One shared run proves all of it. This is the pile.
- **Already cheap.** Touches the primitive with tiny hand-built inputs and costs
  ~0s. Leave it alone — deleting it buys no time and loses coverage. Say so
  explicitly, or a strict reading of "delete the duplicates" takes it too.

### The shape to fold into

One file becomes the only place the expensive thing runs. Inside it:

1. The expensive runs happen **once, at module scope**, not per test.
2. Independent runs launch **concurrently** — `Promise.all`, a parallel fixture,
   whatever the stack gives you — and each is handed the repo's own parallelism
   knob if it has one (`threads`, `-j`, a worker pool). Two levels of
   parallelism, across runs and within each.
3. Every test is an assertion **against those results**. In a good consolidation
   most tests report sub-millisecond.
4. Its header says it is the only file that does this, and says where new tests
   of that kind go.

That last line is what stops the regrowth. Write the rule into CLAUDE.md too:
*"a test that needs the engine to actually run belongs in `<file>`, asserted
against a shared run — not a fresh run, and not a new file."* Without it the
suite is back to eleven files inside a quarter.

### After cutting

- **Re-point every citation.** Deleting test files leaves dangling references in
  design docs and JSDoc — `grep -rn '<deleted>\.test\.' --include='*.md'` plus
  the source comments. Repoint them at where the coverage actually moved.
- **Say what was genuinely lost, in the commit and the report.** Some deleted
  tests pinned real, hard-won fixes. If a fix is now unpinned, the fix is still
  in the code and *nothing checks it* — that sentence belongs in the design doc
  next to the fix, not only in a chat message that scrolls away.
- Re-time the fast command, and take the union number for the report.

## 4. Escalate until the fast command hits the target

Rounds, cheapest first. Each round: apply a rung, run the affected files **once as a set** (never once per fix, never the full suite), then re-time with `measure.sh time -- <FAST_CMD>`. Stop the moment it comes in under target, or when the ladder runs out. Red after a round → bisect by reverting one fix at a time against that same file set.

`quick` in `$ARGUMENTS` → rung 1 only.

1. **Slow tail, mechanical.** The worst 5 in the fast tier after step 3: real sleep → fake clock; per-test fixture → module or session scope; live network → local stub; per-test DB build → transaction rollback or reused DB. Anything needing a design change goes in the report untouched.
2. **Fixed cost every test pays.** This is what a flat profile is made of, and no single test shows it. Time the runner doing nothing — for pytest, the wall time of `--collect-only` is pure overhead — then attack import cost, module-scope work at import time, an autouse fixture on the whole suite, per-test app or container construction, a `setUp` that builds what a class could build once. Cutting 40ms off 3000 tests is two minutes.

   **Time the repeated thing before you attack it.** A log line printed 143 times
   is a conspicuous suspect and an easy false lead: that one measured 24ms a
   call, so all 143 came to ~2s of a 156s suite, and the real cost was the
   simulation nobody had counted. `N × cost`, with `cost` actually measured,
   decides whether this rung is worth a single edit. Noisy repetition is not
   evidence of expense.
3. **Compile and transform cost.** `ts-jest` → `@swc/jest`; a cold Go or Rust build counted inside the run; Gradle without the build cache or configuration cache. Often the single biggest cut in a typed repo, and it changes no test.
4. **Parallelism that isn't paying** — the step 2 diagnosis, now fixed rather than noted: split the one giant file that pins a worker, give each worker its own DB or port, drop the global lock, raise or lower worker count to match the box.
5. **What's left is architectural.** Stop. Name it in the report — the fixture that rebuilds the world, the suite that needs a real service, the 2000 tests that each spin up an app — with an estimate for each. Do not start a redesign inside a speedup pass.

Rungs 2 and 3 are where a suite that "won't go faster" usually goes faster. Reaching for them is not scope creep; it is the difference between a tiered suite and a fast one.

## 5. Verify and report — run 3 of 3

Launch the union command in the background, once. **In its shadow:** fill all four `<CMD>` placeholders in CLAUDE.md, in `.claude/test-commands.sh`, and in any CI config or hook, with the real command strings from steps 2–4. Set `DEFAULT_IS_FAST=1` only if the repo's default script really does run the fast tier now. Then run `scripts/guard-selftest.sh .claude/hooks/full-suite-guard.sh` — both halves have to pass, since a guard that blocks everything just stops the agent testing at all. Then `grep -rnE '<[A-Z][A-Z_ ]*>' CLAUDE.md .claude .github .husky` and confirm it returns nothing — that catches the four `<*_CMD>` strings and the policy block's `<CONSOLIDATED_FILE>` / `<THE EXPENSIVE THING>` slots alike. An unfilled placeholder is worse than no policy, because the agent can't run the narrow command and falls back to the full suite. If step 3b did not consolidate, delete that paragraph from the block rather than shipping it with the slots empty. `<FILE_CMD>` in particular must bypass the tier exclusion (the reference gives the per-stack form): if `<FILE_CMD>` silently skips the slow tests in the file it names, it hands out false greens.

Also finish the report and the prune-candidate list.

**Join.** Pass/fail must be green and the count must match baseline, ignoring the recorded flaky set. This is the only verification steps 2–4 get, so a failure here means bisecting by commit — revert the guilty one, keep the rest, and re-verify.

If step 3b cut tests, the count legitimately dropped, and baseline is no longer the number to match. Match it against **the count you recorded immediately after 3b** instead, and report both deltas separately: what the infrastructure steps changed (must be zero) and what the approved cut removed (the number the user said yes to). Collapsing the two hides an accidental loss inside an intentional one.

Report, in this order:

1. **Did it hit the target** — measured fast-command time vs the 60s / one-fifth bar, and the baseline it came from. Missed → the three biggest remaining costs and what each would take. Never quote a fast-command time you did not measure with `measure.sh time`.
2. **Is it enforced** — guard active (global or repo-local), self-test passed. Repo-local → note that Claude Code asks the user to approve a new project hook the first time it fires, and that it does nothing until they do. Whether the repo's default test script now runs the fast tier.
3. **The retread** — how many times the suite stood the expensive thing up, what one call costs, what that came to, and what consolidating it would save or did save. Cut on a yes → the union before and after, the test count before and after, which files went, and **what coverage was genuinely lost** rather than merely moved. Cut declined or not offered → the number stays in the report as the largest remaining opportunity.
4. Before/after wall time for the union; the four commands as written, confirmed placeholder-free; baseline vs current count; each file changed, one line each; dev deps added; which ladder rungs were used and which were skipped; slow tail fixed vs deferred and why; flaky tests found; prune candidates; anything reverted and why; **and the number of full-suite runs this pass cost**.

## Prune candidates — measured, proposed, cut only on a yes

Near-duplicates differing only in an input literal (suggest parameterizing), tests asserting framework or ORM behavior, tests with no assertion, long-skipped tests, and the step 3b retread pile. Name the stack's mutation tester as a follow-up; don't run it, far too slow for this pass.

Each candidate gets its **measured** cost, not an impression — that is what turns
"these look redundant" into a decision the user can actually make. Then cut what
they approve and leave the rest, listing both.

Two ways this goes wrong, both seen in practice:

- **A regex that "finds" tests with no assertion.** Body-matching regexes
  truncate at the first closing brace and report dozens of false positives.
  Spot-check two before reporting any, and if it turns out broken, say the scan
  was unreliable rather than handing over the noise.
- **Reporting a raw count as a scope.** "232 tests across 16 files" is only a
  useful number if you have checked what is in it. Six of those files costing
  ~0s together do not belong in the same sentence as the nine costing 136s.

## Guardrails

- Count after == count before, **through steps 1–3 and 4**. Those steps are infrastructure and must be coverage-neutral: never delete, skip, or xfail a test there to improve a number. Step 3b is the one place the count may drop, only on the user's explicit yes, and the report states the before and after counts side by side.
- Never delete a test because you judged it redundant. Measure it, propose it, wait. The user owns their coverage.
- Three full-suite runs, each backgrounded, each with work happening in its shadow. Idle waiting and re-running to feel sure are the two biggest costs in this skill.
- One test process at a time. The lock enforces it; don't work around it.
- Never edit a file the runner reads, install a dep, or move the working tree while a run is in flight.
- Never end a turn or report with a run in flight.
- Dev dependencies only, every one listed. Never touch runtime deps.
- Red verification → revert that step's commit alone, continue with the rest, report it.
- Don't rewrite test logic or assertions. Step 4 changes how a test gets its environment, not what it checks. Step 3b may move an assertion into the consolidated file, but it carries it across intact — folding a test in means it asserts the same thing against a shared run, never a weaker thing against a cheaper one.
- Settings already present (a second run on the same repo) → update in place, never append a duplicate.
- The policy block ships with a filled-in **Which tests to run** table, and the guard ships installed and self-tested, or the pass isn't done. Tiering that nothing routes to gets ignored, and the suite is slow again within a week.
- Never report a speedup you didn't measure. The fast command gets its own timed run; the union number is not a stand-in for it.
- Tiering is not the finish line. If the fast command misses the target, work step 4's ladder until it lands or the ladder runs out — and if it runs out, say the number missed rather than reporting the union's improvement instead.
- Don't move a test to the slow tier just to make the fast number look better. The reason has to be visible in the profile.
