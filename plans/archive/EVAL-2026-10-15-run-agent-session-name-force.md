# Eval — 2026-10-15 — /run-agent names the new claude session and takes a fuzzy "force" word
Verdict: ship

## Fix next
- Nothing breaks a criterion. The user confirmed the amendment themselves; no windows were opened this round.

## Criteria
- [x] R1–R2, R4 (script) — PASS — TMUX unset: rc=1, `claude --agent planner "x" --model opus --name "planner: claude-config (opus)"`; non-git temp dir: `--name "worker: tmp.EBTiOaX4wE"` (plans/eval_r18_script.log).
- [x] R3 — PASS — `-- --name mine` printed one `--name "mine"`.
- [x] R1, R12 live — PASS — user saw the name in the swapped pane last round ("Worked"); the title was only missing while the warning prompt blocked startup, which the fix removes. user: "It works, I confirmed myself"
- [x] R5, R7 — PASS — `worker yolo force` swapped with no AskUserQuestion and no force word in argv (last round). Other force words not re-driven; user: "It works, I confirmed myself"
- [x] R6 — PASS — last round, user: "Works"
- [x] R8 — PASS — last round, `planner force` → `planner needs a prompt`, user: "Works"
- [x] R9 — PASS — Run? confirmation ends in `--name "worker: claude-config"` (last round); "No" path not re-driven.
- [x] R11 — PASS — SKILL.md/README mention force and `--name`; `run-agent.sh --help` mentions `--name` (eval_r18_script.log).
- [x] Amendment (user): `yolo force` worker starts at once, no bypass-permissions warning — PASS — fix is `"skipDangerousModePermissionPrompt": true` in settings.json (uncommitted). user: "It works, I confirmed myself"
  No item was shown this round, so there is no evshow history (no elapsed / shown -> question lines).

## User said
- "It works, I confirmed myself"
