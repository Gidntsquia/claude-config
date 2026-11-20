# Eval — 2026-10-28 — Zero-to-hero install of claude-config, v1.2.1
Verdict: rerun worker
phone path

## Fix next
- R16 fails: the Windows test needs Windows Sandbox (Pro only) and this PC is Windows 10 Home. Amended: it must run on this PC (see Amended).
- Release not made yet: per amendment, tag v1.2.1 and publish as Latest once R16 (amended) passes; no Mac test by a person.
- Not a criterion: `settings.json` has an uncommitted change again (model haiku in the working tree, sonnet committed).

## Criteria
- [x] Amendment (user): Quickstart in write-readme voice, install sentence first — PASS — plans/phone/01-readme-top-p1.png 780x1688, -p2.png 780x1688, -p3.png 780x304 (README intro + Quickstart rendered from the file; local README matches origin/main 5fd9ca3); user: "Works"
- [x] Ask — PASS — previous round user: "Works, but it needs to be written in my style…"; that style fix is now accepted ("Works")
- [x] R1 — PASS — head -20: "## Quickstart 🚀" with the install sentence code block is the first section
- [x] R2–R3 — PASS — INSTALL.md "## 4. Ask four questions" maps each to its flag; `--help` lists all six flags, exit 0
- [x] R5 — PASS — fake HOME seeded planner: exit 3, "clash: agents/planner.md"; with keep → planner-claude-config.md
- [x] R6 — PASS — model haiku and statusLine "echo me" kept, promptCacheTtl 1h added, deny = Bash(rm:*) + repo entries; grep ai-test: 0
- [x] R7–R8 — PASS — "CLAUDE.md identical", import line printed, claude-config.json exists, rerun prints "reusing saved choices"
- [x] R9 — PASS — personal-path grep printed nothing; docker log has no FAIL; CI green
- [x] R10 — PASS — iterm2/ has only claude-tmux.json + claude-colors.itermcolors; plist and september-trip.json in deleted-file log; 0 `/Users/`
- [x] R11, R13 — PASS — `install.sh --check` on this PC: 24 PASS lines, "all checks passed", exit 0
- [x] R12 — PASS — INSTALL.md "## 7. Tour" has 5 numbered steps; demo text 19 lines
- [x] R14 — PASS — `bash test/docker-install.sh` EXIT 0, "all install scenarios passed", 42 PASS lines (plans/eval_r49_docker.log)
- [x] R15 — PASS — install.yml run 40706759082 (5fd9ca3): ubuntu, windows, macos all success
- [ ] R16 — FAIL — files exist (.wsb, .ps1, README) but never run; no Sandbox on Windows 10 Home
- [x] R17 — PASS — plans/HANDOFF.md, 26 lines, with the Mac steps
- [x] R18 — PASS — CHANGELOG first version heading v1.2.1, pyproject 1.2.1, wiki 113cae7 touches both setup pages, pushed
- [x] R19 (first half) — PASS — no v1.2.1 tag, `gh release view` "release not found"; waiting for Mac

## Amended
- R16 replaced: the Windows install test runs on this PC (Windows 10 Home) from a fresh profile; log shows --check PASS and "all checks passed".
- R19 gate replaced: GitHub Actions macos-latest counts as the Mac test; release once all else passes.

## User said
- "Works" (Quickstart style)
- "I have the machine I have. Whatever we need to run must work on this machine"
- "Drop it. The macOS run on GitHub actions is sufficient"
