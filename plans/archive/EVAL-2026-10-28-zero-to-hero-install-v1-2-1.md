# Eval — 2026-10-28 — Zero-to-hero install of claude-config, v1.2.1
Verdict: rerun worker
phone path

## Fix next
- Release not made: `git tag -l v1.2.1` is empty and `gh release view v1.2.1` says "release not found". The worker's tag/push/`gh release create` was blocked by the auto-mode classifier ("Create Public Surface"), so it needs the user's go-ahead (or the user runs it).
- Not a criterion: `settings.json` (model haiku) and `skills/weekly-roundup/state.json` are still uncommitted.

## Criteria
- [x] Amendment: Windows test runs on this PC (Win 10 Home), fresh empty profile — PASS — plans/eval_r16_windows_fresh.log (12:03–12:09 ET today): "fresh profile: ...\Temp\cc-fresh-5cffee99 (empty: True)", Claude Code 2.1.312 installed into it, fresh clone, scenarios a and b each "all checks passed" with PASS lines, "== result: PASSED". Rerun live in a terminal at the user's request: plans/phone/03-term-claude-installed.png 780x1688 (empty profile cc-fresh-256dc2bd, Claude Code 2.1.312 installed), user: "Works"; plans/phone/04-term-result-p1.png 780x1688, -p2.png 780x1436 (scenario b PASS lines, "all install scenarios passed", "== result: PASSED"), user: "Works".
- [ ] Amendment: release v1.2.1 as Latest, no Mac gate — FAIL — no tag, no release (see Fix next). Mac evidence ready: install.yml run 40723214353 (b2c201c): ubuntu, windows, macos all success.
- [x] Amendment (user): Quickstart in write-readme voice — PASS — previous round, user: "Works"
- [x] Ask — PASS — 04-term-result, "does this do what you wanted: install works from scratch on this PC?", user: "Works"
- [x] R15 — PASS — latest install.yml run 40723214353 green on all three OSes
- [x] R1–R14, R17, R18 — PASS — unchanged since last round (plans/archive/EVAL-2026-10-28-r16amend-before.md); last commit only adds the Windows test
- [ ] R19 (amended) — FAIL — same as the release amendment

First picture (log as text, plans/phone/01-windows-test-log-p1..p5.png) was rejected; terminal shots replaced it.

## User said
- (launch prompt) "phone"
- "I want to see pictures of it working"
- On the log picture: "It’s not clear from the images. I want images of actual terminals"
- "Works" (03-term-claude-installed), "Works" (04-term-result)
