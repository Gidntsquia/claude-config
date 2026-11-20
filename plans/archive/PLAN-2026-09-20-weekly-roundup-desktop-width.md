# Spec: Weekly-roundup artifacts use desktop width well, each project in its own distinct space
Drafted 2026-09-20.

## Ask
> I want to improve the UI design of the artifacts that the / weekly-roundup skill generates. I
> like the overall look of the UI. But, on desktop, there is a lot of dead space on the left and
> right sides. I want to fix this without making things feel cramped and also allowing each
> project to feel like it has it's own distinct space.

Answers (2026-09-20):
- Which pages get the new layout? "Eventually all roundups (future and past), but only after
  we've confirmed that I like it"
- How should deep-dive cards use the extra width? "Worker proposes, I pick" (worker builds 2-3
  desktop variants from real roundup data, screenshots them, user chooses before the skill changes)
- Top sections (project list, pie charts, token table) on desktop: "Rearrange allowed"
- Must mobile stay exactly as today? "Yes, unchanged"

## What to build
Today a roundup page is one narrow centered column; on a desktop monitor most of the screen to
the left and right is empty ground. The page should instead make good use of a desktop window,
still feel roomy (not cramped), and give each project a clearly separate space of its own. The
existing look (fonts, color tokens, per-project accent colors, cards with colored top border,
section order and content) is liked and stays.

This runs in two stages with a user gate between them. First: 2-3 desktop layout variants built
from a real roundup's content, shown to the user as screenshots; the user picks (or asks for
changes). Only after the user confirms: the skill's instructions are changed so every future
roundup comes out in the chosen layout, and the already-published roundups are republished in it.

## Facts (verified 2026-09-20)
- The skill lives in this repo at `skills/weekly-roundup/` (`SKILL.md`, `gather_data.py`,
  `state.json`); `~/.claude/skills/weekly-roundup` is a symlink to it (`readlink -f`).
- There is no HTML template file. The page is written fresh each run by the model following
  `SKILL.md` section "4. Write the artifact" and the "Output checklist" (read both).
- `SKILL.md` says nothing about page width, columns, or breakpoints (grep for
  width/max-/@media/grid: no hits). The checklist forbids "CSS classes beyond what's specified
  in this file" and requires fonts, tokens and section structure to match section 4.
- A real generated page (Sep 13-16, 8 project cards) is at
  `/tmp/claude-1000/-home-jaxon-files-ai-sandbox/4e0846e3-fce2-4a5b-b6d0-691f6bc226a0/scratchpad/roundup.html`.
  Its body rule is `padding:28px 16px 60px; max-width:760px; margin:0 auto` (grep). /tmp may be
  cleared; copy it early.
- Latest published roundup: `last_artifact_url` in `state.json`
  (`https://claude.ai/artifact/TyQ8ijmPtu5EEe7BVfJdAL`). Each roundup has a "← Previous week"
  link, so all past weeks are reachable by walking that chain; the Roundup Archive artifact's
  `weeks` collection also lists each week's `url` (SKILL.md "Roundup Archive"). Pages are read
  and republished with the `Artifact` tool (read, then update by `url`).
- `SKILL.md` and `gather_data.py` have uncommitted user changes (`git status`).
- Screenshots on this machine: WSL2; Chrome is at
  `/mnt/c/Program Files/Google/Chrome/Application/chrome.exe`, Edge at
  `/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe` (both exist; headless
  screenshot not tried).
- Not verified: how many past roundups exist; how the artifact viewer frames the page on
  claude.ai (its own margins, if any).

## Requirements
1. Variants stage: produce 2-3 clearly different desktop layouts as standalone HTML files built
   from the real roundup page's full content (all sections, all project cards, drawers), not
   placeholder text. For each, give the user screenshots at 1920x1080 and 1440x900 (full page),
   plus one 390px-wide screenshot, next to the same screenshots of the current page. Then stop
   and ask the user to pick or request changes. Nothing is published and `SKILL.md` is not
   edited before the user confirms.
2. In every variant, at 1440px and 1920px viewport widths, the content spans most of the window;
   the large empty bands left and right of the content are gone.
3. Not cramped: body text lines stay a comfortable reading length (no full-width paragraphs on a
   1920px screen), and spacing between and inside cards is at least as generous as today.
4. Each project has its own distinct space: a viewer can tell at a glance where one project ends
   and the next begins, its accent color still marks it, and its picture, paragraph, token table
   and usage drawer stay together inside that space. Opening one project's drawer must not
   distort or misalign neighbouring projects in a confusing way.
5. Top sections (project list, pie charts, token table, total cost) may be rearranged on desktop,
   e.g. side by side. All content, wording, in-page anchors (`#slug`), prev/next week links and
   checklist rules stay intact; "Usage by model" pie still comes before the total cost, which is
   still last in the projects section.
6. At narrow widths (phone, 390px) the page looks the same as today: single column, same order,
   same spacing. Light and dark modes both work in the new layout.
7. Works for any project count the skill can produce, including 1 project, an odd number, and
   8+; no orphaned half-empty rows that look broken, no horizontal scrollbar at any width from
   360px to 2560px.
8. After user confirmation: `SKILL.md` describes the chosen layout precisely enough (widths,
   breakpoints, column behaviour, any new class names, checklist items) that a fresh run of
   `/weekly-roundup` reproduces it without seeing the mockup. The checklist is updated so the
   new layout elements are allowed and required.
9. After user confirmation: every already-published roundup (latest and all earlier weeks) is
   republished in place at its existing URL with the chosen layout, content and prev/next links
   unchanged. The Roundup Archive page's own HTML is left alone.

## Constraints
- Keep the look: Barlow Condensed / Source Sans 3, existing color tokens, accent colors, card
  style, section headers with rule line, section names and order. No new fonts or color tokens.
- Mobile unchanged ("Yes, unchanged").
- No change to `gather_data.py` behaviour or to the data shown.
- Do not discard or overwrite the user's uncommitted edits in `SKILL.md` / `gather_data.py`;
  add to them. Commit only if the user asks.
- Plain, direct wording in anything shown to the user; no jargon.
- Self-contained HTML/CSS as today (artifact pages; Google Fonts is the only external resource).

## Acceptance criteria
- [ ] Variant files exist and open locally; each contains all 8 project cards and every section
      of the source page (compare card ids and section headings with the source via grep).
- [ ] Screenshots of current page and each variant at 1920x1080, 1440x900 and 390px wide are
      shown to the user, and work stops for their pick before any publish or `SKILL.md` edit.
- [ ] (user) At desktop widths the dead space on the left and right is gone.
- [ ] (user) The page does not feel cramped.
- [ ] (user) Each project feels like it has its own distinct space.
- [ ] (user) The overall look is still the one they like.
- [ ] Measured in a browser at 1920px and 1440px: content width is at least ~80% of the viewport
      (today: 760px = 40% / 53%), and no paragraph line box is wider than ~80 characters.
      Fails on today's page.
- [ ] The 390px screenshot of the chosen layout matches the 390px screenshot of the current page
      (side-by-side or pixel diff; differences limited to nothing visible).
- [ ] No horizontal scroll at 360, 768, 1024, 1440, 1920, 2560px
      (`document.documentElement.scrollWidth <= innerWidth`), in light and dark mode.
- [ ] Chosen layout rendered with 1, 3 and 9 project cards shows no broken-looking rows
      (screenshots shown to the user).
- [ ] Opening a usage drawer on one card at 1440px leaves other cards readable and aligned
      (before/after screenshot).
- [ ] After confirmation: a fresh `/weekly-roundup` run (or a fresh agent given only `SKILL.md`
      and the gathered data) produces a page that passes the width, mobile and overflow checks
      above, and still passes the full Output checklist.
- [ ] After confirmation: every past roundup URL (walk "← Previous week" from the latest) shows
      the new layout at desktop width, with text, numbers and prev/next links identical to
      before (diff of extracted text before vs after is empty).
- [ ] `git diff` shows the user's earlier uncommitted changes still present.
