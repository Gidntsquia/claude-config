# Eval — 2026-10-24 — worker.md's usage-limit section rewritten to Anthropic's guidance, with docs/agent-style.md
Verdict: ship
phone path

## Fix next
Nothing blocks shipping. The R3 check expected `claude --agent worker` in agents/README.md, but that file only has the generic `claude --agent <name>` (line 3), and R7 said not to touch it. The plan's premise was off, not the work.

## Criteria
- [x] R1 — PASS — section at worker.md:110: one-sentence intro, `1.` and `2.` one sentence each, one fenced `run-agent.sh --handoff` line, closing line; `drop a flag` → 0; "same prompt, `--model` and `--effort`" → 1.
- [x] R2 — PASS — the banned-word grep over the section finds nothing (rc=1); closing line: "From here the handoff is the only work; running subagents finish on their own and are listed under In progress."
- [x] R3 — PASS (on intent) — line 3 is the trimmed description; worker.md 0, README.md 1; agents/README.md has `claude --agent <name>` on line 3 rather than the literal `claude --agent worker` (see Fix next).
- [x] R4 — PASS — `Usage limit reached` appears once (line 112, inside the section at line 110); the Start sentence is kept in lines 9–16 and ends "the error it gave."
- [x] R5 — PASS — docs/agent-style.md: 31 lines, 9 rules each with an indented `>` quote and an https link, `audit` → 0.
- [x] R6 — PASS — README.md:71 and CHANGELOG.md:5.
- [x] R7/R9 — PASS — HEAD 8206204 touches only CHANGELOG.md, README.md, agents/worker.md, docs/agent-style.md; settings.json is still modified and uncommitted (2+/2−); test.sh → `142 passed, 0 failed`.
- [x] R8 — PASS — the emphasis-word grep has no hits in lines 1–16 or 110+ (hits at 31–108 are out of scope).
- [x] Judging (user) + Ask — PASS — plans/phone/01-a1.png 780x1688, 02-a2.png 780x1688, 03-a3.png 780x1688 (each Gap row before/now, then the whole section); user: "Works".
- [x] Docs page (user, R5) — PASS — plans/phone/04-b1.png 780x1688, 05-b2.png 780x1688, 06-b3.png 780x1688; user: "Works".

## User said
"Works" (Report A), "Works" (Report B).
