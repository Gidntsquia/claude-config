Launch: `bun install && bun run dev` (or `bun run build`; `bun test` for math tests).
All criteria R1-R15 met; checked headless in Chromium (focus, 18% pressed, $50/20%, $23.45/18%, custom 12, $1,481.47, empty, -5, 150, Reset, no overflow at 375px). Reload (R9) holds by design (no persistence), not separately reloaded. 1440px layout and dark mode not viewed by eye.
For the evaluator: shadcn components hand-written in shadcn style (no CLI run); components.json included.

## Rerun fixes (EVAL 2026-10-11)
- Preset highlight: selected preset now uses Button variant "default" (not outline + override classes); removed `transition-colors` (screenshots mid-fade showed 18% dark/20% grey). Headless: $50 @20% → only 20% aria-pressed, 18% white; Custom 12 → no preset pressed, Tip $6.00.
- 375px: Tip/Total cells min-w-0, text-2xl (sm:text-3xl), break-all. Total "$1,719.00" right edge 334 vs card 359 (padding kept).
- R3 second half: after 20% click Custom is "" and Tip $10.00 (observed). R8 second half: Custom 150 → red border (aria-invalid), "Enter 100 or less", $0.00/$0.00 (viewed screenshot).
- Verified with headless Chromium on port 5190 (stopped afterwards). Not viewed by eye on screen.
