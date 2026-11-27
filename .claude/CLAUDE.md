# Working on this repo

This file is for sessions inside this clone. The root `CLAUDE.md` is something else: it installs into every user's
`~/.claude`.

## The planner, worker and evaluator

Three `claude --agent <name>` sessions build this repo, passing files in the gitignored `plans/`:

- planner turns what you ask for into `plans/PLAN.md`, a spec with acceptance criteria.
- worker builds it, records what it saw in `plans/WORKER_NOTES.md`; what you say to it outranks the plan.
- evaluator runs the result, asks you whether it works and writes `plans/EVAL.md`; the worker fixes what it lists.

Hand-off rules: `agents/USAGE.txt`.

## Before you change anything

- What exists and where new work goes: `ARCHITECTURE.md` (with the decisions that still hold and what is next).
- What is tested, per feature: `test/features.txt`.
- What a passing run proves and what it does not: `TESTING.md`.

## The one test command

`test/run` (quick tier; `test/run all` before a release). A change is done when it ends `PASS <n> tests`.

## Every change

1. Add or find the feature's row in `test/features.txt`.
2. Add its test first, from `test/quick/_template.bats`, tagged `feature:<id>`; see it fail; raise the row's count.
3. Follow "Adding a test" and the checklist in `TESTING.md`. A bug a person found gets an `escape:` test.
4. A new part, folder or decision goes into `ARCHITECTURE.md`; add a `CHANGELOG.md` line under `## Unreleased`.

Never loosen or delete a test to get a pass without saying why in the commit message.

@../AGENTS.md
