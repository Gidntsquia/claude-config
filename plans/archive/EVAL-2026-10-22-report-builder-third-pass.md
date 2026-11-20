# Eval — 2026-10-22 — Report builder third pass: natural-error rate, send-back, worker-on fixed (round 2)
Verdict: rerun worker

## Fix next
1. Worker-on card 4 says "the same token count weighs more from a dearer model"; user circled "a dearer model" as a typo and wants a spell/grammar check on every build.

## Criteria
- [x] R1, R2, R3 send-back — PASS — builds/mcp-sendback unchanged since 07:13 (passed last round); `--check mcp` exit 0, needs_keys_resolve and numbers_match_sources PASS (56 figures).
- [x] R3 gpu — PASS — cases/gpu/expected.json `"expect": "report"`; gpu-on report.md still 10-21 19:03.
- [x] R4, R5 — PASS — natural.json, mechanical.json present; planted.json mtime 2026-10-21 23:05.
- [x] R6 — PASS — `--check checker` exit 0 (61 figures match); numbers.json cites natural, planted, mechanical, cost; ASK.md has the G quote.
- [x] R7 — PASS — INVESTIGATION.md "Writer-made data files"; rule in report-writer.md and check.py:296.
- [ ] R8 — FAIL (user) — rebuilt worker-on (17:12): `--check worker` exit 0, numbers_match_sources PASS (71 figures), report.md, numbers.json, html, cards, NOTES, checker present; user on C first said "Works", then flagged the "dearer model" typo on card 4.
- [x] R9 — PASS — only worker-on rebuilt this round; gpu-on 10-21 19:03, token-on 10-21 21:55. `builds/prev-round/` (16:52) is a copy of the earlier builds, not a new build. The `builds/*.json` at 17:28 were written by this eval's `--check` runs.
- [x] R10 — PASS — A and B were unchanged and already passed ("Works" on both last round). C was shown on the phone as 7 bannered PNGs in chat; user: "Works".
- [x] R11 — PASS — WORKER_NOTES.md has pasted `--check` output per build.
- [x] R12, R13 — PASS — REPORT.md "Cold checker runs"; git log -1 = 53630c1; golden r5 B check.py PASS, r4 A FAIL incl. ai_tells.
- [x] Amendment: no FE-per-token comparison between models — PASS — no "FE per token"/"per cache-write token" pattern in worker-on report.md; user: "Works".

Shown as labeled phone PNGs in chat (EVAL_NOTES), not desktop windows, so there are no evshow timing lines.

## Amended
- Spell/grammar check and plain words added to agents/report-writer.md only; no rebuild or test (replaces the first amendment).

## User said
- "I'm on my phone"
- C: "Works"
- After the verdict: "Actually, there’s a typo in the report. See the image I attached. We should run a spell-checker/grammar checker" (circled "a dearer model", card 4)
- "Just make an update to the agent definition without testing it (for the worker, I mean)"
