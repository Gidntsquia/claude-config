# Eval — 2026-10-15 — /run-agent takes a working directory (round 21)
Verdict: ship

## Fix next
- Nothing failed. Live driver checks R3, R4/R5, R6, R8, R11 were still running when this was written; result lands in plans/eval_r21_drive.log (all passed last round except R11 force, never observed).

## Criteria
- [x] R1/R2/R7/R9 — PASS — `cd '/home/jaxon/files/ai-sandbox' && claude --agent planner "x" --name "planner: ai-sandbox"`, rc=1 (plans/eval_r21_static.log).
- [x] R2 — PASS — real claude in ~/files/claude-config/skills: Run? `claude --agent worker "." --name "worker: ai-sandbox"  (in /home/jaxon/files/ai-sandbox)?` (plans/eval_r21_drive.log).
- [ ] R3 — BLOCKED — `bash plans/eval_r21_drive.sh <id> <scratch>` (case r3 + ls diff), still running.
- [ ] R4/R5 — BLOCKED — same driver, cases r4no/r4yes, still running.
- [ ] R6 — BLOCKED — same driver, case r6, still running.
- [x] R8 — PASS — my Yes swap of `/run-agent planner in ~/files/ai-sandbox`: pane_current_path=/home/jaxon/files/ai-sandbox, title `✳ planner: ai-sandbox`.
- [x] R10 — PASS — `no such directory: /nonexistent`, rc=2.
- [ ] R11 — BLOCKED — `TMUX= run-agent.sh worker` output unchanged (rc 1); force half = driver case r11b, still running.
- [x] R12 — PASS — argument-hint and README line 30 contain `in <dir>`; `--help` lists `--cwd|-C <dir>`.
- [x] R13 — PASS — `24 passed, 0 failed`, rc 0.
- [x] Amendment (planner, no prompt) — PASS — `TMUX= run-agent.sh planner` -> `claude --agent planner --name "planner: claude-config"`, rc 1; live Run? shows the same, no prompt argument; user: "Works".
- [x] Ask — PASS — user: "Works" (live terminal: planner started by `/run-agent planner in ~/files/ai-sandbox`, empty input box, statusline ai-sandbox).
  `elapsed 2.75 s (answer -> shown)`; `question emitted 12:33:50.098 ET (shown -> question 2.04 s)`

## User said
- "Works"
