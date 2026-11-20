# Eval — 2026-10-15 — Plane theme for statusline.sh, switchable by CLAUDE_STATUSLINE_THEME, squid untouched
Verdict: ship

## Fix next
Nothing blocks shipping.
- Note: the wiki commit d1b4fed (Home.md note + plane-statusline.png) is committed but not pushed to the GitHub wiki (worker notes).
- Note: CLAUDE_STATUSLINE_NF=1 shows no separator glyph in either theme. It was the same before this change (empty SEP since 52646fe).

## Criteria
- [x] The Ask — PASS — terminal window showing the live plane bar (`✈️ claude-config | main | Opus …`) and `--preview plane`; user: "Works". Timing: `elapsed 3.87 s (answer -> shown)`; `question emitted 17:30:18.987 ET (shown -> question 2.64 s)`.
- [x] R2 squid byte-identical — PASS — s1..s300 × 2 inputs × 9 prompts, fresh TMPDIR, old ca4a2ce vs new: `diff -r` empty on 600 files. My first input had a malformed effort field. Rerun with `effort.level` set: 0 diffs in 586 of 600 files before the 500 s timeout.
- [x] R1/R4 plane sweep — PASS — 0 of 600 (and 0 of 586 rerun) plane outputs contain 🦑🦀🐙🐊🦈🫧; ✈️ appears in 554; 586 files differ from squid.
- [x] R5 preview parity — PASS — 25 lines each; bands equal; steps per band identical (1 1 1 2 8 4 4 1×9 4 4 4 4 4 5 5 18 1); counters all `plane-*`, disjoint; Humpty/Red Hood/pigs/beanstalk strings identical.
- [x] R6 `--preview` — PASS — rc 0 with no stdin, both themes printed, 0 files in a fresh TMPDIR.
- [x] R7 install flag — PASS — temp HOME (WSL block skipped via fake /proc/version): plane twice → 1 export line; squid → 0; none → 0; foo → usage line, rc 1.
- [x] R8/R9/R10 docs — PASS — CLAUDE_STATUSLINE_THEME hits: README 1, CHANGELOG 2, wiki/Home.md 1; `## Unreleased` is first heading after title; wiki/plane-statusline.png exists.
- [x] R11 no ZWJ — PASS — `grep -cP '\x{200D}'` = 0.
- [x] R12 NF in both themes — PASS — NF=0 renders `|`; NF=1 renders the same (empty) separator as old ca4a2ce, in both themes.
- [x] bash -n / shellcheck — PASS — `bash -n` ok; shellcheck isn't installed system-wide, and the worker reports only 2 old SC2034 warnings.

## User said
"Works"
