# Eval — 2026-10-24 — Worker hands off at the usage limit
Verdict: replan

## Fix next
- worker.md "At the usage limit" (line 111, 23 lines) still has "lots of added fluff" per the user.
- User wants agent definitions checked against researched best practices (big: planner).
- No-tmux run's note heading lacked the time: `## Stopped at usage limit — 2026-10-24 (ET, see commit time)` (plans/eval_r44/n.log).
- Working tree has uncommitted settings.json edits (`model` opus → haiku, `autoContinueAtUsageLimit` moved); not from this eval.

## Criteria
- [ ] Amendment (user): tighter section — FAIL — VS Code on the 23-line section copy; user: "No, lots of added fluff still. Also, I want you to research best practices for agent defintions. I'm not sure we're following them currently"
      `elapsed 5.43 s (answer -> shown)` / `question emitted 00:53:27.791 ET (shown -> question 5.20 s)`
- [x] R1 — PASS — `## At the usage limit` at worker.md:111, pointer at :15, names `[Usage limit reached;`, steps 1–4 in order.
- [x] R2 — PASS — run t (tmux, haiku): `#1 claude --agent worker "." --model haiku ... at 12:55 AM ET (after window, in 1m)`.
- [x] R2 timing — PASS (partial) — jobs.log `2026-10-24 12:55 AM ET #1 fired`; post-fire pane/`S --jobs` still running when written: `cat plans/eval_r44/t2.log`.
- [ ] R3 — BLOCKED/partial — run n note has Done / In progress / Next / Uncommitted / Relaunch but no time in the heading; run t note pending: `grep -A7 "== t notes" plans/eval_r44/t.log`.
- [x] R4 — PASS — run n: `WIP: stopped at usage limit — R3 pytest run pending`.
- [ ] R6 — BLOCKED/partial — no-tmux: `Relaunch: not scheduled — not in tmux; run /run-agent worker after window to schedule it by hand`, no job added; empty-usage run e still running: `cat plans/eval_r44/e.log`.
- [ ] R5, R8 — BLOCKED — t run's final message and relaunch pickup: `cat plans/eval_r44/t.log plans/eval_r44/t2.log`.
- [x] R7 — PASS — committed HEAD has `false`; CHANGELOG:5 names the trade-off.
- [x] R9 — PASS — worker.md:131 subagent rule.
- [x] R10 — PASS — no diff to planner/evaluator/helper/report-writer since 4f69387~1; test.sh `133 passed, 0 failed`.
- [x] R11 — PASS — CHANGELOG.md:5, agents/README.md:6, wiki/Glossary-and-FAQ.md:52.

## User said
- "No, lots of added fluff still. Also, I want you to research best practices for agent defintions. I'm not sure we're following them currently"
