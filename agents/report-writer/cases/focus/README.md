# cases/focus

Golden r5/B (report folder and its `outline.md`) with one section added to `report.md` that has no outline row:
"🧭 How did the certain feed do on its own?", a tour of an arm the ask did not name, placed before the ending.
`check.py --prose` must FAIL `outline_match` on it (and `unasked_once`, since the certain feed is in `## Left out`).

    G=~/files/agent-eval-experiment/report-writer/cases/gpu
    python3 -I ~/.claude/agents/evals/report-writer/check.py ~/.claude/agents/report-writer/cases/focus \
      --data $G/data --traps $G/TRAPS.md --mode phone --prose | grep -E "outline|unasked|focus|check.py"

The data is the gpu case's (`cases/gpu/data` in agent-eval-experiment), as for the golden.
