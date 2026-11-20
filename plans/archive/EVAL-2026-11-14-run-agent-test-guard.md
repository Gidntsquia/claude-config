# Eval — 2026-11-14 — run-agent test.sh guard + resume of the killed report-loop worker (v1.3 larger plan reviewed)
Verdict: rerun worker (R1's no-flag half); the larger v1.3 plan is still open
no-flash: PASS (2 window(s) hidden before first paint, max exposure 0 ms, 2373 zlog samples over 237.2 s, 7 run window(s) never on-screen before their show)

## Fix next
- R1 without the flag: `cd skills/run-agent/scripts && python3 -c 'import launch;print("PATH" in launch.claude_environ())'` inside a Claude session printed False (expected True). If that is real, the hook can no longer recover TMUX from the parent outside tests.
- v1.3 is still open: Parts A (worker-building) and B (planner-building) have no plans/EVAL.md, and R21 is not done (`gh release view v1.3` → release not found; the latest tag is v1.2.1).
- R12 and R15 were not judged by the user: the status summary (plans/STATUS-v1-3-1386430343.md) never opened. VS Code timed out twice and Firefox once. The command evidence below passes.
- The first terminal item opened before test.sh had finished, so the user saw nothing ("It seems to have not run"). It worked once the run was done.

## Criteria
- [ ] R1 — FAIL (half) — with the flag `claude_environ()` → `{}` (PASS). Without the flag, in this evaluator session, `"PATH" in launch.claude_environ()` printed `False`, but the criterion expects a dict containing PATH. Normal (no-flag) parent lookup may be broken; rerun the plain R1 command in a live Claude session to see it.
- [x] R2 — PASS — the hook with the flag answered `test mode: refusing tmux respawn-pane on /tmp/tmux-1000/default`, not `ignored: agents replace their own pane`.
- [x] R3, R8 — PASS — the test.sh refusal and job-store guard cases PASS (plans/eval_r53_test.log).
- [x] R4 — PASS — `test mode: refusing the real job store`, exit=2, ~/.claude/run-agent mtime unchanged.
- [x] R5 — PASS — test.sh:25 trap, :26 `unset TMUX TMUX_PANE`; the --hook lines use `env -u TMUX` or no socket.
- [x] R6, R7 — PASS — user: "I see it now. It seemed to work" (the first show: "Nope, I don't see that at all. It seems to have not run"). The log has 2 canary lines.
      `opened evtest957131933 HWND=133528 (hidden: 133528 312 312 evtest957131933 (create 312 312))`; `elapsed 6.35 s (answer -> shown)`; `question emitted 22:38:59.573 ET (shown -> question 3.58 s)`
      Reopen: `opened evtest215556298 HWND=1051038 (hidden: 1051038 266 266 …)`; `not shown: window 1051038 overlaps terminal`; `question emitted 22:40:44.370 ET (shown -> question 108.37 s)`
- [x] R9 — PASS — lines 2-3 are Rule 1 / Rule 2; CHANGELOG has one line about the incident.
- [x] R10 — PASS — this eval's run of test.sh: `313 passed, 0 failed` (more than 246).
- [x] R11 — PASS — b09d5b5 touches only CHANGELOG.md and skills/run-agent/scripts/*.
- [x] R12 — PASS (command only, the user did not judge it) — the "Resume after the 9 Nov kill" section is present; bin/run-agent-dev and skills/run-agent-dev/ are still untracked.
- [x] R13 — PASS — e7e6f76 and 8c5b81a contain preflight.py, the check.py gate, cards.mjs, slips, and the worker.md/report-writer.md text.
- [x] R14 — PASS — the ledger got its row (9 Nov). A newer uncommitted row (14:08Z) comes from a later replay-report run, not from this worker.
- [x] R15, R16 — PASS (command only, the user did not judge it) — c17 row `worker-c17-report-loop-r1-worker-1794214385`: 7/7 hidden tests, false_claim false.
- [x] R17 — PASS — no new jobs.log line from this worker (the only 11-09 line is user job #54).
- [x] R18 — PASS — the archived v1.3 R1-R12 and R21 are still open as written. worker.md has 0 DATA_REQUEST.

## User said
"Nope, I don't see that at all. It seems to have not run"
"I see it now. It seemed to work"
