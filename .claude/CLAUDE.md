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
- The tests, on one page (run, read a failure, add a test, what a pass means): `TESTING.md`.

## Every change

`test/run` is the one test command; a change is done when it ends `PASS <n> tests`. Add the test first, as
`TESTING.md` says, and see it fail. Features are listed in `test/features.txt`. A new part, folder or decision goes
into `ARCHITECTURE.md`; add a `CHANGELOG.md` line under `## Unreleased`.

@../AGENTS.md
