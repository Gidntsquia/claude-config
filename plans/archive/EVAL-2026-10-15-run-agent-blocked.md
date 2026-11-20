# Eval — 2026-10-15 — /run-agent names the new claude session and takes a fuzzy "force" word
Verdict: not decided yet. Rerun the evaluator once tmux driving is allowed (the code isn't at fault; the live checks never ran)

## Fix next
- Live `/run-agent` checks not yet judged: the auto-mode classifier refused to start claude in my own tmux sessions and type into them ("Tmux Self Drive"). User: "I'll allow tmux driving" (they will add a permission rule, then rerun).

## Criteria
- [x] R1–R2, R4 (script) — PASS — TMUX unset in skills/: rc=1, `claude --agent planner "x" --model opus --name "planner: claude-config (opus)"`; non-git temp dir: `--name "worker: tmp.2zKnmOPaSB"` (log plans/eval_r17_script.log).
- [x] R3 — PASS — `-- --name mine` printed one `--name "mine"`.
- [ ] R1, R12 live (prompt box / pane title shows `planner: claude-config`) — not yet judged (tmux driving refused).
- [ ] R5, R7 force variants swap with no question — not yet judged (tmux driving refused).
- [ ] R5 `yolo force` / `yolo-run` — not yet judged (tmux driving refused).
- [ ] R6 `"go now"` still confirms — not yet judged (tmux driving refused).
- [ ] R8 `force` / `planner force` stop messages — not yet judged (tmux driving refused).
- [ ] R9 `worker "."` confirmation ends in `--name "worker: claude-config"`, No -> `nothing changed` — not yet judged (tmux driving refused).
- [x] R11 — PASS — SKILL.md diff has force words (step 1), force behavior (steps 3–5), `--name` rule (step 6), `[force]` argument-hint; README /run-agent lines mention force words; `--help` prints the `--name` line.

## User said
- "I'll allow tmux driving"
