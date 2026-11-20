# Eval — 2026-10-14 — /run-agent skill
Verdict: ship

## Fix next
Nothing failed.

## Criteria
- [x] R1 — PASS — both files exist, script +x; settings.json has `"run-agent": "user-invocable-only"`; ~/.claude/skills/run-agent -> repo skills/run-agent.
- [x] R6, R13 — PASS — `--list` prints evaluator helper planner worker claude general-purpose Explore Plan statusline-setup (rc 0); `nosuch` rc 2 "unknown agent: nosuch" + list; no args rc 2 usage.
- [x] R9 — PASS — TMUX unset: `run-agent.sh worker` rc 1, "not inside tmux; run:" / `claude --agent worker "."`.
- [x] R8, R10, R11 (+ the Ask) — PASS — RA6 pane: `/run-agent worker "fix the $HOME bug"`, Yes -> same pane became `@worker · ~/files/claude-config`; claude-config sessions 7 before, 7 after (old one replaced). user: "Works".
      elapsed: none logged (watcher idle-exited after 1 h; wait-fallback showed it: answer->shown not measured) · question emitted 14:36:15.195 ET (shown -> question 2.48 s)
      Not seen: the `running:` line (the new claude TUI cleared the pane scrollback) and a shell after quitting the new claude (worker notes report both from a throwaway tmux server).
- [x] R12 — PASS — RA6 first user message reads literally `fix the $HOME bug` (same item, user: "Works").
- [x] R2 — PASS — RA1 `/run-agent --model opus worker "."` -> Run? shows `claude --agent worker "." --model opus (in /home/jaxon/files/claude-config)`. user: "Works".
      elapsed 2.37 s (answer -> shown) · question emitted 14:36:42.325 ET (shown -> question 2.45 s)
- [x] R3 — PASS — RA2 `worker "." using opus` -> same command. user: "Works".
      elapsed 4.09 s (answer -> shown) · question emitted 14:37:03.594 ET (shown -> question 2.64 s)
- [x] R2 (bad args) — PASS — RA3 `worker . extra words` -> usage line only. user: "Works".
      elapsed 4.64 s (answer -> shown) · question emitted 14:37:33.556 ET (shown -> question 2.65 s)
- [x] R4 — PASS — RA4 `/run-agent planner` asks "What should planner work on?". user: "Works". Empty-answer stop path not exercised.
      elapsed 3.39 s (answer -> shown) · question emitted 14:37:52.020 ET (shown -> question 2.40 s)
- [x] R5 — PASS — RA5 bare `/run-agent` menu: helper, planner, worker, evaluator; built-ins named for Other. user: "Works".
      elapsed 4.24 s (answer -> shown) · question emitted 14:38:53.051 ET (shown -> question 2.54 s)
- [x] R7 — PASS — the Run? confirmation with full command + directory appeared in RA1, RA2, RA6 (user judged RA1/RA2). "No" path not exercised.
- [x] R14, R15 — PASS — SKILL.md 45 lines; README lines 29-30 mention `/run-agent`.

## User said
Works (all six items).
