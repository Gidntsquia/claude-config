# Eval — 2026-10-11 — Tip calculator web page (round 2)
Verdict: ship

## Fix next
Nothing. All criteria pass.

## Criteria
- [x] R1–R2 load — PASS — headless: focus=bill, only 18% aria-pressed (user passed it in round 1)
- [x] R5–R6 $50 @20% — PASS — user: "Works: only 20% is highlighted (the page is in dark mode, so the selected button is the light one and the other three are dark), Tip $10.00, Total $60.00, no submit button." Timing: `elapsed 21.9 s (answer -> shown)` / `question emitted 13:14:10.037 ET (shown -> question 366.05 s)`. The watcher was late, so I showed the item by hand and asked right after `shown:`. The history times it from the late watcher show.
- [x] R5 $23.45 @18% — PASS — user "Works" in round 1. The math code has not changed, and `bun test` passes.
- [x] R3 custom 12 → no preset highlighted, Tip $6.00 — PASS — user: "Works". Timing: `elapsed 0.95 s (answer -> shown)` (the watcher showed it again; I had already shown it by hand). There is no question-emitted line in the history.
- [x] R3 then 20% → Custom empty, 20% only, Tip $10.00 — PASS — user: "Works". Shown by hand with `win.sh show`, so the history has no lines for it.
- [x] R4 $1,481.47 — PASS — user "Works" in round 1 (formatting unchanged)
- [x] R7 empty bill → $0.00 — PASS — user "Works" in round 1
- [x] R8 Custom 150 → red border, hint, $0.00 — PASS — user: "Works". Shown by hand, so the history has no lines for it. The bill -5 half passed in round 1.
- [x] R9 reload → defaults — PASS — headless: after reload, bill "" and only 18% pressed
- [x] R10 Reset — PASS — headless: bill "", custom "", only 18% pressed
- [x] R12 375px — PASS — user: "Works" (Total $1,456.78 inside the card padding). Headless: total right edge 334 vs card 359, scrollWidth 375 = viewport. Shown by hand, so the history has no lines for it.
- [x] R14 keyboard — PASS — headless: order Bill>15%>18%>20%>25%>Custom>Reset, 0 unlabeled controls, 4 presets with aria-pressed
- [x] R15 build — PASS — `bun run build` exit 0 (dist/ built), `bun test` 2 pass / 0 fail, dev server served the app on port 5745
- [x] Ask — PASS — user: "Works" (live app, freshly loaded). Shown by hand, so the history has no lines for it.

Notes: the watcher did not fire within 8 s after "Yes". The saved terminal HWND 6030722 no longer existed, so my terminal was not moved and could not be restored. Items 2–6 were shown by hand with `win.sh show` (each printed `shown:`) and asked straight away. I did not read any captures. All states were live in Firefox: a harness page loaded the app in an iframe and set the state with a script.

## User said
- "Works: only 20% is highlighted (the page is in dark mode, so the selected button is the light one and the other three are dark), Tip $10.00, Total $60.00, no submit button."
- "Works" (×5)
