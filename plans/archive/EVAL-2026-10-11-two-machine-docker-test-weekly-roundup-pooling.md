# Eval — 2026-10-11 — Two-machine Docker test of weekly-roundup cross-machine pooling
Verdict: ship

## Fix next
Nothing failed.

## Criteria
- [x] 1 — PASS — `wsl.exe -u root -- docker run --rm hello-world` -> "Hello from Docker!" (no-op rerun of setup_docker.sh not repeated this round; worker reported "docker OK").
- [x] 2,3 — PASS — `docker history --no-trunc roundup-test | grep -ci credential` -> 0; access-token prefix grep over tests/out -> 0 files; containers have no mounts.
- [x] 4 — PASS — `docker exec machine-a/-b hostname` -> machine-a / machine-b; check.py PASS on devices root@machine-a / root@machine-b.
- [x] 5,6 — PASS — `ls /root/files`: alpha-app (A) only, beta-tool (B) only; tests/expected.json present.
- [x] 7 — PASS (part) — `git diff HEAD -- state.json` empty. Real archive weeks list: not re-read here (needs an interactive Artifact read); worker reports unchanged.
- [x] 8,9 — PASS — S1–S3 a.log/b.log/week.html exist; every log has a claude.ai/artifact URL.
- [x] 10 — PASS — check.py exit 0, 0 FAIL lines (incl. new "pie legend grouped by person" for S1–S3).
- [x] 11 — PASS — judged last round on the S3 page; this round's Data sources view: user: "Works".
- [x] 13,14 — PASS — six throwaway URLs in logs; README line 9 "Run everything: `skills/weekly-roundup/tests/run.sh`", 27 lines.
- [x] Amendment (pie grouped by person, most usage first) — PASS — S3 page pie legend; user: "Works". Timing: elapsed 3.5 s (answer -> shown); question emitted 04:11:09.900 ET (shown -> question 2.58 s).
- [x] Ask — PASS — S3 page, Data sources drawer open; user: "Works". Timing: elapsed 1.87 s (answer -> shown); the helper logs no "question emitted" line for the last item.

## User said
- "Works" (pie grouping)
- "Works" (the Ask)

Throwaway artifacts to delete by hand: S1 CM1UWNoM6L977upRWGhmpM, Ljeh1f423HtmwDRCca6SuX; S2 XkWovaweXiJ3AhPcNwLYKv, 2nwyC996CTxyYBMXjiXxd5; S3 ERL1D1x34zRWARz8uSdT8R, 2ptb3xP2tBT9BMYvkCCu91 (https://claude.ai/artifact/<id>). Containers machine-a/-b still running.
