# Eval — 2026-10-09 — Move stale agent definitions and backups into the local archive/
Verdict: ship

## Fix next
Nothing.

## Criteria
- [x] R1-R3 — PASS — three new names in archive/; cmp against 9c3f5dc~1 shows no difference for all three; run-loop .sh is executable.
- [x] R4 — PASS — backups/ absent; `git ls-files backups` empty.
- [x] R5 — PASS — README.txt 5 lines, first 2 unchanged, 3 new cp lines ending in the stated targets. user: "Works"
- [x] R6 — PASS — grep finds no run-loop/evaluator-new; diff of 9c3f5dc is 4 removed lines only.
- [x] R7, R9, R10, R13 — PASS — `git show --stat 9c3f5dc` lists only the 4 expected paths (evaluator.md was changed later by separate commit 00d7b32, not by this work).
- [x] R8 — PASS — ~/.claude/agents lists exactly the four; `claude --agent evaluator-new` → "not found", rc=1; `--agent evaluator` replied OK. user: "Works"
- [x] R11 — PASS — status shows only ` M settings.json`; message ends with Co-Authored-By and Claude-Session lines.
- [x] R12 — PASS — main is now level with origin, but origin includes later commit 00d7b32, so the push came after the worker's run, not from it.
- [x] Ask — PASS — user: "Works"

## User said
"Works" (Ask), "Works" (live agents list), "Works" (restore lines).
