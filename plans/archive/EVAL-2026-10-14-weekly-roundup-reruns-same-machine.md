# Eval — 2026-10-11 — weekly-roundup reruns from the same machine replace that machine's data
Verdict: ship

## Fix next
Nothing.

## Criteria
- [x] 1, 2, 14: PASS. `uv run pytest skills/weekly-roundup/tests` -> 9 passed, rc=0 (plans/eval_pytest.log).
- [x] 3: PASS. test_same_hostname_different_person_errors is among the 9 that passed.
- [x] 4: PASS. test_shared_project_keeps_other_machine passed.
- [x] 5: PASS. Feature-link drop and dangling-warn tests passed.
- [x] 6: PASS. S4 `roundup-data` has authored = {"projects": {"alpha-app": "machine-a"}, "fixed": {"alpha-app-pre-week-commit-window": "machine-a"}}. a-2.log has `replaced_collected_at": "2026-10-11T21:43` from the `rewrite` output.
- [x] 7, 10: PASS. `grep -n rewrite SKILL.md` matches lines 94, 154, 157 and 168.
- [x] 9, 12: PASS. check.py: 85 PASS, 0 FAIL, rc=0. S4 has 1 device, 1 `roundup-data` block and 1 Things-fixed entry, and its archive lists the week once. (This is the worker's existing out/S4 run from 17:41-17:50 ET. Docker was not rerun.)
- [x] 11: PASS. tests/test_gather_data.py exists. Its only network or Docker mention is the docstring "no Claude, no Docker, no network".
- [x] 13: PASS. a-2.log: "replaced this machine's earlier data from 2026-10-11T21:43 and rewrote everything the script flagged".
- [x] Ask (S4 week page in Firefox, Things fixed and the alpha-app card after two runs): PASS. user: "Works".
  "elapsed 11.89 s (answer -> shown)". The history logged no "question emitted" line for this item. The only one is "question emitted 23:11:18.878 ET (readiness question)".

## User said
"Works"
