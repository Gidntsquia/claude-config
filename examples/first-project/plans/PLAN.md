# Spec: Tip calculator web page (bill + tip percent -> tip and total)

## Ask
"A tip calculator web page: type a bill amount and a tip percent, see the tip and the total. Build it with React, TypeScript, Vite, Tailwind and shadcn/ui, using Bun."

User's answers:
- Tip input: "Preset buttons + custom field" (15 / 18 / 20 / 25% buttons plus a number field for any other percent)
- Split between people: "No split"
- Correctness check: "Match a hand calculation to the cent" and "Live update, no submit button"
- Look: "Single centered card"
- Bad/empty input: "Show $0.00 and a quiet hint"
- Default tip on load: "18%"
- Persistence: "No, fresh each load"
- Extras: not answered (defaults below)

## What to build
A single-page web app with one centered card. The user types a bill amount, picks a tip percent with a preset button or types a custom percent, and sees the tip amount and total update instantly as they type. No submit button, no splitting, no persistence. Blank or invalid input shows $0.00 and a quiet inline hint. Rounding is half-up to the cent.

## Facts
- No external data, APIs or devices. Nothing to verify.
- Repo is empty apart from `.gitignore` (already contains `plans/`).

## Requirements
1. (user) Bill field: a text/number input labeled "Bill", accepts a decimal dollar amount, empty and focused on load.
2. (user) Tip presets: four buttons 15%, 18%, 20%, 25%. Clicking one selects it (visibly highlighted) and sets the percent. 18% is selected on load.
3. (user) Custom percent: a number input labeled "Custom %" next to the presets. Typing in it deselects the presets and uses the typed value. Clicking a preset clears the custom field.
4. (user) Results: "Tip" and "Total" shown large below the inputs, formatted as `$1,234.56` (two decimals, thousands separators).
5. (user) Math: tip = bill × percent / 100, rounded half-up to the cent; total = bill + tip. Examples: $50 at 20% → tip $10.00, total $60.00; $23.45 at 18% → tip $4.22, total $27.67.
6. (user) Live update: results recompute on every keystroke or button click; no submit button exists.
7. (user) Empty bill or empty percent → tip and total show $0.00, no error shown.
8. (user) Invalid input (negative, non-numeric, percent above 100 for custom): the field gets a red border and a one-line hint beneath it (e.g. "Enter a positive amount"); results show $0.00.
9. (user) Nothing is persisted; a reload returns to defaults (empty bill, 18%).
10. (default) A "Reset" button clears the bill and custom percent and reselects 18%.
11. (default) No currency selection, no copy button, no split.
12. (user) Layout: one shadcn `Card` centered horizontally and vertically on the page, max width about 420px, full width on phones. Inputs on top, results beneath.
13. (default) Light theme, follows system dark mode via Tailwind `dark:` classes. Page title "Tip Calculator".
14. (default) Keyboard accessible: all inputs and buttons have labels, tab order top to bottom, presets are real `<button>` elements with `aria-pressed`.
15. (default) Runs as a static site: `bun run dev` serves it locally, `bun run build` produces a deployable `dist/`.

## Constraints
- Stack (user): React + TypeScript + Vite + Tailwind + shadcn/ui, with Bun as the package manager and runner.
- No backend, no database, no network calls.
- Money math must avoid floating-point drift (compute in cents or round explicitly after each step).

## Acceptance criteria
- [ ] R1–R2: Load the page; bill field is empty and focused; the 18% button is highlighted.
- [ ] R5–R6: Type 50, click 20%: Tip shows $10.00 and Total $60.00 with no submit click.
- [ ] R5: Type 23.45, click 18%: Tip $4.22, Total $27.67.
- [ ] R3: Type 12 in Custom %: presets unhighlight; $50 bill gives Tip $6.00. Click 20%: custom field clears, Tip $10.00.
- [ ] R4: Bill 1234.56 at 20%: Total shows $1,481.47.
- [ ] R7: Clear the bill: Tip and Total show $0.00, no red border.
- [ ] R8: Type -5 in bill: red border, hint text under field, results $0.00. Type 150 in Custom %: same treatment.
- [ ] R9: Enter values, reload: bill empty, 18% selected.
- [ ] R10: Enter values, click Reset: bill empty, custom empty, 18% selected.
- [ ] R12: At 375px and 1440px widths the card is centered and nothing overflows.
- [ ] R14: Tab through the page; every control reachable; presets report pressed state to a screen reader.
- [ ] R15: `bun install && bun run build` succeeds; `bun run dev` serves the page.
