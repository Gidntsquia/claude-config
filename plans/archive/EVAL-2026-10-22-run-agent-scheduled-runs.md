# Eval — 2026-10-22 — /run-agent scheduled runs and forgiving argument parsing
Verdict: ship

## Fix next
Nothing.

## Criteria
- [x] Ask — PASS — terminal showing the parse of the Haiku-failed phrases, `at 9pm`/`in 2h`/`after window until 7am`, a dry run and `--jobs`; user: "Works". `elapsed 2.53 s (answer -> shown)`; `question emitted 18:59:58.739 ET (shown -> question 4.50 s)`.
- [x] R1-R2 — PASS — `model=fable effort = medium, force`, `—model`, `-model`, `fable low effort` all give agent worker, `--model fable --effort medium|low`, unsure [] (force 1 on the first).
- [x] R3 — PASS — `worker fabel low` -> corrections `fabel -> fable`; `worker zzqx` -> unsure `zzqx`; SKILL.md:51 asks once, best reading first, Yes / It is part of the prompt / Drop it.
- [x] R4 — PASS — live 6:58 PM ET: `at 9pm` -> 1792717200 = Thu 9:00 PM EDT, at_text `at 9pm`; `in 1h30` = now+5400 s; `after window` = resets_at in test.sh (frozen clock suite passes).
- [x] R5 — PASS — test.sh "sched: until *" pass (skipped line printed and logged, no job).
- [x] R6 — PASS — missing usage file: at_error `usage API: FileNotFoundError ...; open any claude session to refresh the token`; scheduling exits 2.
- [x] R7-R8 — PASS — test.sh scheduling suite: fired into pane, `fired in new window`, `fired in new session` ('worker repo'), all PASS.
- [x] R9 — PASS — `--jobs` -> `no scheduled runs`; SKILL.md:14-18 name `S --jobs` / `S --cancel` for "what is scheduled" / "cancel"; test.sh jobs/cancel cases pass.
- [x] R10 — PASS — `--dry-run` printed command, dir, `run at: 7:08 PM ET`, `usage reset: 8:20 PM ET`; `--jobs` still `no scheduled runs`; `dry` parse -> dry 1.
- [x] R11 — PASS — SKILL.md:69-74 gives the `Schedule: ... at 2:40 AM ET (after window, in 3h 12m) (in ...)?` text, `(read: ...)` suffix, "Yes, schedule it" / "No".
- [x] R13 — PASS — SKILL.md (88 lines) steps call `S --parse`; no flag-mapping instructions found beyond the forms table.
- [x] R14 — PASS — `bash skills/run-agent/scripts/test.sh` -> `129 passed, 0 failed`; logged strings (curly quotes, em/single dash, `opus+medium effort`, `claude --agent evaluator`) present.
- [x] R15 — PASS — transcript 23c47eeb-...jsonl (6:39 PM ET) is claude-haiku-5-5 and shows `--model fable --effort low` and `9:00 PM ET (at 9pm, in 2h 21m)`; cited in WORKER_NOTES.md.
- [x] R16 — PASS — README:49, SKILL.md description/argument-hint, CHANGELOG:5 mention times and jobs/cancel.

## User said
"Works"
