# Eval — 2026-10-29 — v1.3 master plan, Part D (run-agent) amendments
Verdict: rerun worker

## Fix next
- `test.sh` fails 3 group tests in a fresh run: "FAIL group: 2x2", "FAIL group: confirm window", "FAIL group: --here", with "no server running on …/split.sock" (plans/eval_r52/test.log; 160 passed, 3 failed, exit 1). The worker claimed 163 passed. This run overlapped the eval's own tmux sessions on the default server.
- The `--next` closing step is too wordy (new amendment).
- `--next worker`/`evaluator` suggests a fixed model and effort (`opus medium`, `--model opus --effort medium`); it should suggest default flags (new amendment).
- Parts A, B, C, the report loop, and R21 (release) are not built yet. Their planners have not run.

## Criteria
- [x] Amendment 1 (one call, four planners, new 2x2 window) — PASS — shell `run-agent <4-planner line>` + `y` in a WT/tmux session (planners stubbed by plans/eval_r52/bin/claude) made window 2 "4 agents": 4 panes in a 2x2 layout, one per folder. user: "Works" (this item also covered the Ask's run-agent part).
      elapsed 2.01 s (answer -> shown) · question emitted 03:08:16.988 ET (shown -> question 2.40 s)
- [x] Amendment 3 (replace or new window only) — PASS — the caller's window 1 still had one pane after the launch. user: "Works".
      elapsed 1.82 s (answer -> shown) · question emitted 03:08:48.760 ET (shown -> question 2.48 s)
- [ ] Amendment 2 (worded next step) — FAIL — this evaluator session's real `run-agent.sh --next worker "."` printed a sentence, `/run-agent worker "." opus medium`, "Or from any terminal, without run-agent:", and `claude --agent worker "." --model opus --effort medium`. user: "1. I want it more concise. 2. Worker and evaluator should be run with default flags; we shouldn't suggest a hard coded model or effort".
      elapsed 1.62 s (answer -> shown) · question emitted 03:09:16.230 ET (shown -> question 3.58 s)
- [ ] R20 (test.sh passes, tree clean) — FAIL — test.sh exit 1, 3 group tests failed (see Fix next). `git status --porcelain skills/run-agent` printed nothing.
- [ ] R1–R15, R21 — not graded — Parts A–C and the release are not built yet.

Captures were not read because the answers were Works, or a wording change that a capture would not change. After `evshow.sh end` the terminal was back where it started (`now -9 -9 2578 1408 1` = saved).

## Amended
- `--next` output is more concise: one short sentence, then each command form on its own line.
- Worker and evaluator next steps suggest no model or effort (replaces part of R19).

## User said
"Works" ×2.
"1. I want it more concise.
2. Worker and evaluator should be run with default flags; we shouldn't suggest a hard coded model or effort"
