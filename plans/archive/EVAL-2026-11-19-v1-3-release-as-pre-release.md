# Eval — 2026-11-18 — v1.3 release as pre-release v1.3.0-beta.1 (shipped as v1.3.0-beta.4)
Verdict: ship
phone path

## Fix next
Nothing blocks this beta. Before the full release, reread the notes against the style file. RELEASE_NOTES.md:34 "`test.sh` can no longer touch a live tmux pane." uses "touch", a word style.md:26 flags (the user accepted it for the beta).

## Criteria
- [x] Done 1 / R16–R18 — PASS — `gh release view v1.3.0-beta.4`: isPrerelease true; the body equals RELEASE_NOTES.md apart from the trailing newline gh adds. v1.2.1 is Latest and beta.1–4 are Pre-release. Install run 44362499305 (release): ubuntu, macos and windows all success. No v1.3 or v1.3.0 tag. Each beta.1–3 failure was fixed and re-released as the next beta, as R18 says.
- [x] Done 2 / R9–R11, R22 — PASS — scratch HOME, clone at v1.2.1, install rc=0, merge rc=0, TAG install rc=0, `--check` rc=0 with `PASS assistant agent`, `PASS run-agent MCP server registered` and `all checks passed`; describe v1.3.0-beta.4. The scheduled job #1 was cancelled and upd-home deleted.
- [x] Done 3 / R3–R8, R12–R15 — PASS — user: "Works" on all four: Report A release notes, plans/phone/01-release-notes-1..5.png 780x1688 (the Ask asked here: "Works"), Report B README Features 02-readme-features-1..3.png 780x1688, Report C wiki Workflow 03-wiki-workflow-1..12.png 780x1688, Report D Cheat Sheet 04-wiki-cheat-sheet-1..2.png 780x1688. The wiki pages match origin/master. Banned-phrase grep: one hit, "touch" at RELEASE_NOTES.md:34 ("doesn't" and "IMPORTANT:" are allowed by style.md:17-18). Conflict, Report E 05-style-conflict.png 780x1688: user: "Fine for now as the beta release. We will need a closer look when we do the full release"
- [x] R5 — PASS — plans/RELEASE_TRACE.md: 31 shas, all in v1.2.1..v1.3.0-beta.4 (bad=0).
- [x] R1–R2 — PASS — `## Unreleased` has 0 entries; `grep -c "add them from"` = 0.
- [x] Done 4 / R20–R25 — PASS — planner-fix/run-agent-dev in ls-files: 0. agents/assistant.md is not a symlink. Porcelain is clean outside plans/. HEAD = tag b616b19. The tag has one planner.md, assistant.md and skills/run-agent, with no run-agent-dev.
- [x] R19 — PASS — `test.sh` on b616b19: `315 passed, 0 failed`.

Evidence: plans/eval_r56_checks.log. PNGs were made with Playwright through phone-shot.sh and carry a banner per EVAL_NOTES. The md render shows the wiki's `<!-- Last synced -->` comment as text; GitHub hides it.

## User said
- Report E: "Fine for now as the beta release. We will need a closer look when we do the full release"
