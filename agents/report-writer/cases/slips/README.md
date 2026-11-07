# cases/slips

The 2026-11-06 19:53 ET base-context report (`~/files/base-context-cleanup/plans/audit-report/report/`, session
`9702e65f`, launched from the project root so the project's AGENTS.md was in the writer's context). Copied as shipped:
`report.md`, `numbers.json`, `outline.md`, `NOTES.md`, plus `report.html`, `cards/measure.json` and
`checker/findings.json` so `check.py` can run. It passed the 30 checks of its day; it must FAIL the four slip checks:

- `doubled_unit`: "{a_unused_n} listings" (unit `listings`, prints "7 listings listings") and "{fe_rate}
  Fable-equivalent tokens (FE)" (unit `FE`, spelled out after the figure).
- `split_sliver`: the 🔭 `::split` segment `unused` ({a_unused}, 1.5% of {A_total}) is never named as small or by its figure.
- `machinery_aside`: "… but the audit counts it anyway" and "The audit counts sessions only for …", with no settling key.
- `opening_subject`: the scene names the machine Jaxon-PC and the borrowed session [[44904a3d]].

    D=~/files/base-context-cleanup/plans/audit-report
    python3 -I ~/.claude/agents/evals/report-writer/check.py ~/.claude/agents/report-writer/cases/slips \
      --data $D --mode phone --prose | grep -E "doubled_unit|split_sliver|machinery_aside|opening_subject|check.py"

The data is the audit's own data dir (`context-audit.json`), which this fixture does not copy.
