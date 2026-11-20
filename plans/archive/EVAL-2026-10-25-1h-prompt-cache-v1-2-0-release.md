# Eval — 2026-10-25 — 1-hour prompt cache everywhere, then the v1.2.0 release
Verdict: rerun worker
phone path

## Fix next
- Default model is `haiku` in settings.json and in the v1.2.0 notes/GitHub release; the user wants Opus (amendment below).
- The v1.2.0 release description repeats things and doesn't read as written in the `/write-readme` style (user, amendment below).

## Criteria
- [x] Ask (1h cache only, never 5m) — PASS — plans/phone/01-cache-commit-p1.png 780x1688, -p2.png 780x302; user: "Works"
- [x] R1 — PASS — jq prints 1h, 1h, 1; valid JSON; diff adds the 3 cache keys + model (opus → haiku)
- [x] R2 — PASS — `cacheTtl: 1h` in both files; diff line count 4
- [x] R3 — PASS — '5 minutes' count 0; line 75 names the one-hour cache and settings.json; stat shows 1 line changed
- [x] R4–R6 — PASS — commit body has jq/grep output, `ephemeral_5m_input_tokens: 0`, `subagent events checked: 3, ephemeral_5m: 0, ephemeral_1h: 28070`
- [x] R7 — PASS — no 5m figure above 0 in the body
- [x] R8 — PASS — HEAD~1 touches exactly helper.md, report-checker.md, report-writer.md, settings.json
- [ ] R9 — FAIL — `grep -c 'claude-fable-5-1\|Fable 5.1' RELEASE_NOTES.md` → 0 (Haiku committed); everything else passes: archived R1–R2 headings, R8 hashes match, R9/R10 diffs empty, R11 1.2.0, R12 test lines, R14–R15 remote tag peels to 3b4d7dd, status clean, R16 release Latest/not draft, body equal except gh's trailing blank line, R17 grep empty; promptCacheTtl 1 each; v1.2.0 stat has no agents/ or settings.json
- [x] R10 — PASS — heading 2026-10-25; release commit 2026-10-25 00:18 ET

## Amended
- Default model is Opus in settings.json and the v1.2.0 notes/release (replaces the Fable 5.1 check).
- v1.2.0 notes say each change once (user-judged).
- v1.2.0 notes follow the `/write-readme` style; the worker lists the rules it applied in WORKER_NOTES (user-judged).

## User said
- "Works" (cache commit)
- "Opus" (asked: Haiku as released, Fable 5.1 as planned, or Opus)
- "Also, the release description has some redundant things and it's not clear that it was properly written with my style from the / write-readme skill"
