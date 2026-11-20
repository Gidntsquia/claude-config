# Eval — 2026-09-21 — Weekly-roundup artifacts use desktop width well, each project in its own distinct space
Verdict: ship

## Fix next
- Nothing sent back. One check is still open: no real `/weekly-roundup` run has been done with the
  new SKILL.md. Look at the next roundup at desktop width and at 390px when it is generated.

## Criteria
- [x] Variant files exist with all cards/sections — PASS — variant-A/B/C.html present; user already picked A.
- [x] Screenshots shown, work stopped for pick — PASS — shots/ has current + A/B/C at 1920/1440/390; user picked A.
- [x] (user) Dead space gone — PASS — user: "Works" (live claude.ai pages, maximised).
- [x] (user) Not cramped — PASS — user: "Works".
- [x] (user) Each project has its own space — PASS — user: "Works" (incl. drawer open).
- [x] (user) Look kept — PASS — user: "Works".
- [x] Width >= ~80%, lines <= ~80 chars — PASS by user — content 100% of 1440 and 87.5% of 1920.
      Lines measured ~100 chars at 1440 (604px paragraphs), ~75 at 1920; over the ~80 limit at 1440.
      User was told the number and answered "Works".
- [x] 390px matches current — PASS — final.html vs current.html at 390px, images hidden: same size
      (390x9277), pixel diff empty.
- [x] No horizontal scroll — PASS — scrollWidth == viewport at 1440 and 1920 in my run; worker's
      page.py covers 360-2560 light+dark (not rerun).
- [x] 1, 3, 9 cards no broken rows — PASS — rendered with the masonry script at 1440; 1 card leaves
      the right half empty, 3 leaves a gap bottom-right; user shown both: "Works".
- [x] Drawer open at 1440 — PASS — only cards below it in the same column move down (485px);
      other column unchanged; widths unchanged.
- [ ] Fresh run reproduces layout — NOT CHECKED — final.css and final.js are verbatim in SKILL.md
      under "Desktop layout"; no real `/weekly-roundup` run done by worker or by me.
- [x] Past roundups republished, content identical — PASS (partly) — user viewed latest and
      first-week live pages and walked "Previous week": "Works". Text diff is the worker's
      transform.py assert; not rerun.
- [x] User's earlier uncommitted changes still present — PASS — gather_data.py diff intact
      (+96/-5); SKILL.md still has `--token-window-end`.

## User said
- Dead space: "Works"
- Not cramped (told ~100 chars per line at 1440px): "Works"
- Own distinct space / drawers: "Works"
- Look kept and 1-card / 3-card layouts: "Works"
