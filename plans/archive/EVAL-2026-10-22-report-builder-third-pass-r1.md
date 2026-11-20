# Eval — 2026-10-22 — Report builder third pass: natural-error rate, send-back, worker-on fixed
Verdict: rerun worker

## Fix next
1. Worker-on report (card 3, "Where do the extra Opus tokens go?") says Opus pays 0.8 FE vs 0.4 FE per cache-write token and 2.0 vs 1.0 per output token; user: FE is the same across models by definition, so the comparison is wrong.

## Criteria
- [x] R1, R2, R3 send-back — PASS — builds/mcp-sendback has NEEDS-DATA.md, needs-data.json, NOTES.md `## Send-back`, no report.md; runs.jsonl row send_back: true, rule "n_below_two, ci_includes_zero", last line "send-back: needs data"; `--check mcp` exit 0; cases/mcp/data mtimes all 2026-10-21. Checked the worker's run, not a fresh one. Its final text says the build made a report.html, and the writer deleted it.
- [x] R3 gpu — PASS — cases/gpu/expected.json `"expect": "report"`; no new gpu build dir.
- [x] R4, R5 — PASS — natural.json 16 rows across 4 builds (verdict, fe_checker, wall_s, check_py_caught); mechanical.json per build; planted.json mtime 2026-10-21 23:05.
- [x] R6 — PASS — checker-on numbers.json cites natural (18), planted (5), mechanical (3), cost (16); `--check checker` exit 0; ASK.md has the G quote.
- [x] R7 — PASS — INVESTIGATION.md "Writer-made data files" (cause, 43 keys, dir mismatch, rule 2); "writer-made" rule in report-writer.md:37 and check.py:17/245/296.
- [ ] R8 — FAIL (user) — `--check worker` exit 0, numbers_match_sources PASS, outputs present; user on C: "The FE token comparison is simply wrong; a FE token is equivalent between opus and sonnet by definition".
- [x] R9 — PASS — new dirs only mcp-sendback(-view), checker-on, worker-on (+ checker-cold subdirs); gpu-on/token-on report.md from 10-21.
- [x] R10 — PASS — three sets shown on the phone as bannered PNGs in chat. A: "Works. Let’s keep the checker for the time being". B: first answer "The report was written even though it asks for a send-back; this is a waste of resources since it will have to rewrite the report anyways once the new data comes in". The user had taken the card heading "Report" (the MCP task with that name) for a written report. After that was explained, the answer was "Works". C: see R8.
- [x] R11 — PASS — WORKER_NOTES.md has pasted `--check` output per build.
- [x] R12, R13 — PASS — REPORT.md has "Cold checker runs"; git log -1 = 53630c1; golden r5 B PASS, r4 A FAIL incl. ai_tells.

## Amended
- Worker-on report must not compare FE per token between models (user words on C).

## User said
- A: "Works. Let’s keep the checker for the time being"
- B: "The report was written even though it asks for a send-back; this is a waste of resources since it will have to rewrite the report anyways once the new data comes in"; "You sent me pictures titles “report B.” In those pictures, there is a section called “report”"; then "Works"
- C: "The FE token comparison is simply wrong; a FE token is equivalent between opus and sonnet by definition"
