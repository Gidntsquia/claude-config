# Guard demos

Two cheap live runs that show the worker's usage limits (`hooks/usage-guard/README.md`) stopping a real worker.
Each builds a toy repo in a temp dir, starts one real `claude -p --agent worker` on Sonnet capped at $1, and prints a
short transcript, the guard's log lines and the cost.

```
bash demos/guard/demo1.sh    plan says `run.sh -j 4` over a claude -p suite (inner claude is a fake); the worker is
                             blocked and reruns at -j 2, the command the block ends with. The transcript opens
                             with the count the worker was given at session start and shows the count after
                             the allowed run (`◦` lines).  Measured 15 Nov: 4 turns, $0.03.
bash demos/guard/demo2.sh    plan says 6 Opus subagents at once, then one again; the 4th-6th and the repeat are
                             blocked, all six run as helper on Haiku.  Measured 9 Nov: $0.18, 18K FE tokens.
bash demos/guard/r15.sh      the env run-agent gives a worker, and a subagent asked for on Opus running on Sonnet.
                             Its subagent task carries the time, so a second run the same day is not a repeat.
bash demos/guard/report_writer.sh
                             14 Nov amendment: a worker's `report-writer` subagent stays report-writer on Opus, a
                             `general-purpose` one asked for on Opus runs as helper on Sonnet. The toy repo carries a
                             one-word stand-in for report-writer, so it costs cents.
```

Run them from your own terminal or from any session; a count of 4, 6, 1 and 2 launches is added to the toy projects only.
`show.py <stream.jsonl>` prints the transcript of any `claude -p --output-format stream-json --verbose` run.
