# Eval — 2026-10-30 — v1.3 master plan, Part D (run-agent) 429 amendments
Verdict: rerun worker
no-flash: PASS (4 window(s) hidden before first paint, max exposure 0 ms, 648 zlog samples over 64.7 s, 4 run window(s) never on-screen before their show)

## Fix next
- Parts A, B, C, the report loop and R21 (release) are still not built (R1–R15, R21 unjudged). The Part D run-agent amendments now pass.

## Criteria
- [x] Window-relative time schedules with the usage API at 429 — PASS — terminal `evstep1295116553` ran `--step 'worker fable low two hours before the window force'` with `RUN_AGENT_USAGE_FILE=status:429` → `scheduled #1: claude --agent worker "." --model fable --effort low … at 12:48 AM ET (two hours before window 2:48 AM, estimated from session activity, in 34m)`. user: "Yes, but this isn't very convincing for me. Nevertheless, it's hard to show it working anyways-- I'll try it by hand"
      `opened evstep1295116553 HWND=24119016 (hidden: 24119016 234 234 evstep1295116553 (create 234 234))`
      Shown by `wait` fallback (no answer line, so no `elapsed` line): `show-start 00:16:24.561`, `shown-at 00:16:26.689`; `question emitted 00:16:32.010 ET (shown -> question 5.32 s)`
- [x] A sound typed `/run-agent` shows no usage-lookup error — PASS — terminal `evhook1295116553`: the `--hook` block reason for `worker "." dry` at 429 reads `command / dir / run at: now / usage reset: 2:48 AM ET (estimated from session activity) / dry run: nothing scheduled, nothing replaced`, with no HTTPError/429 text. user: "Works"
      `opened evhook1295116553 HWND=8849428 (hidden: 8849428 203 203 evhook1295116553 (create 203 203))`
      `elapsed 2.08 s (answer -> shown)`; `question emitted 00:17:16.069 ET (shown -> question 5.85 s)`
- [x] R20 — PASS — fresh test.sh: 246 passed, 0 failed, exit 0 (plans/eval_r55/test.log); `git status --porcelain skills/run-agent` empty.
- [ ] R1–R15, R21 — not graded — Parts A–C, the report loop and the release are not built yet.

Notes: the first show attempt (titles evstep239603910/evhook239603910, hidden 187/188 ms) hit a WSL interop timeout (`UtilAcceptVsock: accept4 failed 110`), `rc 1`, `elapsed 10.98 s`; both windows were closed while still cloaked, then reopened with new titles. `win.sh me` found 3 candidate windows; the user picked "tmux 1" (HWND 2164524). The demos used a scratch RUN_AGENT_HOME; both test jobs were cancelled.

## User said
"tmux 1"
"Yes, but this isn't very convincing for me. Nevertheless, it's hard to show it working anyways-- I'll try it by hand"
"Works"
