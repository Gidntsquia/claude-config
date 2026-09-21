---
name: weekly-roundup
description: Build a "Weekly Roundup" artifact summarizing projects Jaxon worked on in the past week — pulled from git activity under ~/files, with a per-project deep dive. Use when Jaxon asks for a weekly roundup, weekly recap, or asks what he worked on this week.
---

# Weekly Roundup

Produces one HTML artifact per run: projects worked on and a deeper look at each project
(picture + one paragraph). Styled like Jaxon's Pokemon Go Podium artifacts — tight,
data-dense, no filler.

## 1. Determine the window and run the data script

The project/commit window and the token window both start at the beginning of the current Claude
usage week (most recent Sunday 10pm local) and run to now. For a past or just-ended week
(including backfills), pass `--token-window-start` and `--token-window-end` as the Sunday 22:00
boundaries on each side. Never use `last_run` from `state.json` as the window start; it is only a
record of when the skill last ran.

Ask Jaxon for `cap-pct` (% of weekly cap consumed so far) fresh every run. `last_cap_usage_pct` in
`state.json` only prefills your question; never reuse it silently.

`plan-cost` ($/mo, flat-rate plan) is hardcoded at `100` below; update it here if the plan changes.

Run the bundled script once for all deterministic data-gathering (git, remotes/screenshots, jsonl
token tallies, pricing, FE normalization, weekly-cap math):

```
python3 "$SKILL_DIR/gather_data.py" \
  --window-start <project window start, YYYY-MM-DD> \
  --window-end <today, YYYY-MM-DD> \
  --token-window-start <most recent Sunday 22:00 local, ISO datetime> \
  --token-window-end <next Sunday 22:00 local, ISO datetime; omit for the current, unfinished week> \
  --cap-pct <p> \
  --plan-cost 100
```

(`$SKILL_DIR` is this skill's directory.) It prints JSON: `projects` (name, path, remote_url,
commits, screenshot path, token_rows per model, fe_total, cost_total, weekly_pct, `sessions`), `misc`,
`unused_pct`, `implied_cap_fe`, `combined_cost`, `model_breakdown` (per model across all
projects + Misc: model_display, raw_tokens, fe_tokens, cost, usage_pct), `model_effort_breakdown`
(per family x effort: label, color, usage_pct), `unpriced_models`. Use its numbers directly; do not
recompute them.

If a project's `remote_url` is empty, name it without a link. If it has no `screenshot`, omit the
picture. Check each project's README yourself for a deployed-app URL (Vercel/Netlify/Pages/etc;
the script doesn't) and use it as the "Link" instead of the GitHub link when present.

Also list artifacts (`Artifact` action: list) updated in the window; they count as project work
even without a git commit (e.g. the Pokemon Go Podium tools). The script can't see them; add them
manually with a placeholder/zero token row if no matching Claude project directory exists.

### Key features per project

Each project's `sessions` list (id, start, first prompt, fe_tokens, weekly_pct; subagent usage is
already in its parent session) feeds the drawer's feature breakdown. For each project with
sessions, pick roughly 2-6 key features (what was built or changed this week) and assign every
session belonging to one, judging by first prompts, commit subjects and diffs. Write
`{"<project name>": {"<Feature name>": ["<session id or unique prefix>", ...]}}` to a scratch file
and rerun the script with `--features-file <file>`. Each project then gains `features`: name,
fe_tokens, weekly_pct (same basis as the project's `weekly_pct`; features sum to it), sessions,
and `models` (family, color, pct of that feature's tokens). Unassigned sessions land in an
automatic "Other" feature; a session goes to exactly one feature. Fix any `no session matches`
warnings on stderr. Use the rerun's output for everything downstream. A project with no sessions
(artifact-only) gets no drawer.

Read a few actual diffs for the meatiest commits (each project's `commits` list), not just commit
messages, to inform the deep-dive paragraphs.

## 4. Write the artifact

Follow the `artifact-design` skill, then build one HTML page:

- Reuse the Podium visual language: Barlow Condensed headings / Source Sans 3 body (Google
  Fonts), light/dark tokens (`--ground`, `--card`, `--ink`, `--muted`, `--line`, `--blue`,
  `--shadow`), section headers with a trailing `<div class="rule">`, cards with a colored top
  border, tabular-nums for numbers.
- Give each project a distinct accent color (visually distinct hues, not `--blue`). Use it for the
  project's name pill in the top list, the "Link" text in that row, and `--accent` on its deep-dive
  card (top border, title color, token-table header rule).
- Structure, top to bottom:
  1. Title + eyebrow with the date range covered.
  2. **Projects this week** — numbered list; each row: `<num>. <name pill>` on the left, then a
     `Link` hyperlink (deployed app if any, else GitHub; omit if none) and the project's weekly
     usage % on the right. The pill links to the project's deep-dive card (`#slug` id on the
     card's `div.card`); `Link` goes to the external repo/app. Usage % is the project's FE tokens
     over the week's grand total FE tokens (see Token breakdown). Sort by usage % descending.
     Below the list, a pie chart (CSS `conic-gradient` circle + swatch legend): one slice per
     project, a "Misc" slice (neutral gray, e.g. `#9aa2b1`) for untracked-project usage, and a
     final "Unused" slice colored `var(--muted)`, computed against the actual weekly cap usage
     (see Token breakdown), not just 100%.
     Below it, a second pie (same style) titled "Usage by model": one slice per entry of
     `model_effort_breakdown` (all projects + Misc; one entry per model family x effort), sized by
     `usage_pct` (FE-token weighted). Slices sum to 100% of used tokens; no "Unused" slice. Color
     each slice with the entry's `color` exactly as given (one hue per family: Sonnet blue, Fable
     purple, Opus orange, Haiku green; darker = higher effort, low -> max). Slices arrive ordered
     family, then effort, so a family's shades sit together. Legend: rows grouped by family, each
     a swatch + `label` (e.g. "Sonnet · low") + percentage. Versions of a family (Fable 5 / 5.1)
     are merged. Local Qwen models are priced $0 and never appear in this pie, the tables, or the
     cost. If `unpriced_models` is non-empty, they were priced at Sonnet 5 rates as a fallback; add
     them to the price table and tell Jaxon when reporting, not on the page.
     Below that pie, a big total-cost figure (no label), the summed dollar Cost across all
     projects plus Misc, formatted like `$942.02`, with a small caption underneath: "Equivalent
     pay-by-token API price; actually paid $100 / mo" (plan cost hardcoded; update here if it
     changes). The total cost is the last thing in this section, below both pies.
  3. **Things fixed** — short section between the projects list and the deep dives, only for big,
     non-obvious issues Jaxon hit and resolved that week: things that broke his environment, cost
     real time, or whose fix he'd want to remember (e.g. "leftover Ollama install was crashing
     WSL — had to fully uninstall it"). Find them by reading the window's session transcripts
     (`~/.claude/projects/*/`) for moments outside normal feature work (crashes, broken
     environments, corrupted state, misconfigured tools) where he had to stop and fix something.
     Skip ordinary "wrote a bug, fixed it". If nothing qualifies, omit the section entirely.
     Format: a plain `<ul>` under the section header (no card styling), one entry per issue: bold
     one-line problem statement, then one or two plain sentences on the fix, in the write-readme
     skill's voice (direct, first person where natural, no hedging, no "not X but Y" contrasts, no
     closing reassurance clauses).
  4. **Project deep dives** — one card per project: representative picture (if found), a tight
     3-5 sentence paragraph on what the app does *as of this report* (for a reader with zero
     context), and a token table with columns Model / Raw tokens / FE tokens / Weekly % (one row
     per model used on the project that week, tabular-nums, sorted by FE tokens descending). Below
     the table, a collapsed `<details class="drawer">` (summary "Usage breakdown by feature",
     styled with the card's `--accent`) opening to one row per entry of the project's `features`
     (already sorted, "Other" last): feature name, its `weekly_pct` (share of the whole week's
     usage; sums to the project's weekly %), and a small pie (same style) of that feature's usage
     by model, one slice per `models` entry using its `color` and `pct` (versions merged). Omit
     the drawer when the project has no `features`.

### Desktop layout (screens 1000px and wider; phones unchanged)

The base CSS is a single narrow column (`body` max-width 760px); nothing below applies under
1000px.

- Mark the two main sections `<div class="section projects">` ("Projects this week") and
  `<div class="section dives">` ("Project deep dives"). Children stay in order: in `.projects`,
  `h2`, `.rule`, `ul.plain`, first `.piechart-wrap`, `h2.sub`, second `.piechart-wrap`,
  `.total-cost`; in `.dives`, `h2`, `.rule`, then the `.card`s. A "Things fixed" section, if
  present, stays a plain `<div class="section">` in between, its list in 2 columns.
- Body max-width 1680px, padding `36px 48px 72px`. Projects: two equal columns, 64px gap; left is
  the numbered list, right is the project pie then "Usage by model" and its pie; total cost spans
  both underneath. Deep dives: cards in 2 columns from 1000px, 3 from 1500px, 32px gap; card
  images cropped to a 21:8 banner, body padding `22px 26px 24px`.
- The script below puts each card, in order, into the currently shortest column so columns end at
  similar heights. It wraps the cards in `div.mgrid` > `div.mcol` at run time; do not write those
  in the HTML. It re-flows on resize and font load, not on drawer open. Without it the CSS still
  works as a plain equal-height grid.
- Paste the CSS and script verbatim, unchanged: CSS in `<style id="desktop-layout">` after the
  base styles, script in `<script id="desktop-layout-js">` at the end of `<body>`. Mobile styles
  stay outside the media query and are never changed.

```css
@media(min-width:1000px){
body{max-width:1680px;padding:36px 48px 72px}
header{margin-bottom:34px}
.projects,.dives{display:grid}
.projects>h2,.projects>.rule,.dives>h2,.dives>.rule{grid-column:1/-1}
.projects{grid-template-columns:repeat(2,minmax(0,1fr));column-gap:64px;align-items:start}
.projects>ul.plain{grid-column:1;grid-row:3/span 4}
.projects>.piechart-wrap{grid-column:2;grid-row:3;margin-top:0}
.projects>h2.sub{grid-column:2;grid-row:4;margin-top:14px}
.projects>h2.sub~.piechart-wrap{grid-row:5}
.projects>.total-cost{grid-column:1/-1;grid-row:7;margin-top:26px}
.section:not(.projects):not(.dives)>ul{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));column-gap:64px}
.dives{grid-template-columns:repeat(2,minmax(0,1fr));gap:32px;align-items:stretch}
.dives>.card{margin-bottom:0;display:flex;flex-direction:column}
.dives>.card>.card-body{flex:1;display:flex;flex-direction:column}
.dives>.card>.card-body>table.tokbreak{margin-top:auto}
.mgrid{grid-column:1/-1;display:flex;gap:32px;align-items:flex-start}
.mcol{flex:1 1 0;min-width:0;display:flex;flex-direction:column;gap:32px}
.mcol>.card{margin-bottom:0}
.card img{aspect-ratio:21/8;object-fit:cover}
.card-body{padding:22px 26px 24px}
}
```

```js
(function(){var s=document.querySelector('.dives');if(!s)return;var cards=[].slice.call(s.querySelectorAll('.card'));var g=null;
function lay(){var n=innerWidth>=1500?3:innerWidth>=1000?2:1;
if(g){cards.forEach(function(c){s.appendChild(c)});g.remove();g=null}
if(n<2)return;
g=document.createElement('div');g.className='mgrid';var cols=[];
for(var i=0;i<n;i++){var d=document.createElement('div');d.className='mcol';g.appendChild(d);cols.push(d)}
s.appendChild(g);
cards.forEach(function(c){var m=cols[0];cols.forEach(function(k){if(k.offsetHeight<m.offsetHeight)m=k});m.appendChild(c)})}
var t;addEventListener('resize',function(){clearTimeout(t);t=setTimeout(lay,60)});
addEventListener('load',lay);if(document.fonts&&document.fonts.ready)document.fonts.ready.then(lay);lay()})();
```

## Token breakdown

`gather_data.py` computes all of this; per project it gives `token_rows` (model, raw_tokens,
fe_tokens, cost), `fe_total`, `cost_total`, `weekly_pct`, plus top-level `misc` and `unused_pct`.
Use as-is. Method, for reference:

- **Raw tokens** = input + output + cache-read + cache-creation (5m/1h), per model, deduped by
  message id from the jsonl files under `~/.claude/projects/<slug>/`.
- **Cost** = raw tokens priced per model (input/output; cache-read at 0.1x input, 0.025x on Fable
  5.1; cache-write at 1.25x or 2.0x input for 5m/1h) using the price table at the top of
  `gather_data.py`. Keep that table current when Anthropic pricing changes.
- **FE tokens** ("Fable-equivalent") = cost normalized to Fable's $10/M input rate, making usage
  across models comparable.
- **Misc** = FE tokens from every Claude Code project directory active in the window that isn't
  mapped to a tracked project. Legend/pie entry only, no card.
- **Weekly cap**: the `--cap-pct` you pass is `p`; implied cap = `combined_fe / (p/100)`, each
  row's `weekly_pct` = its FE tokens over the implied cap, so project shares + Misc +
  `unused_pct` (`100 - p`) sum to 100%.
- A repo may map to several Claude Code project directories (renamed/moved repos, sandbox
  copies); the script sums them. Repos moved since an earlier week (backfills) need an entry in
  `MOVED_FROM` in `gather_data.py`, or their old-path usage lands in Misc.
- Favicon: 🗓️. Title: "Weekly Roundup — <date range>" (e.g. "Weekly Roundup — Sep 6-11, 2026"),
  matching the eyebrow so artifacts are distinguishable in the list.
- Publish with `Artifact`. If `state.json` has `last_artifact_url`, pass it as `url` to update in
  place (read it first per the Artifact tool's update flow) rather than creating a new artifact.
- Artifacts start private. After publishing, remind Jaxon to share it (claude.ai Share button →
  public link); the tool has no publish-time flag for this.

## Prev/next week navigation

- `state.json`'s `last_artifact_url` (before you overwrite it this run) is the previous week's
  artifact; read it (`Artifact` action: read) before building the new page.
- Add a "← Previous week" link to that URL near the title/eyebrow. The new artifact is always the
  current week, so omit the "Next week →" side entirely (no placeholder self-link).
- In the same `.weeknav` row add a "Dashboard" link to the Roundup Archive (`archive_url` in
  `state.json`), always.
- After publishing, republish the previous week's artifact with its "Next week →" pointing at the
  new URL (adding the link if it had none).
- The very first roundup (no `last_artifact_url`) has no previous week: omit or gray out the
  "← Previous week" link.

## Output checklist (verify before publishing)

Every artifact, including one-off or backfilled reports, must satisfy all of these and read
identically to a normal week: no report-type-specific notes, disclaimers, or wording.

- Footer text is exactly `Generated by the weekly-roundup skill`, no variants.
- No extra paragraphs, notes, or CSS classes beyond this file (no `.backfill-note` etc.). If
  something is unusual (missing data), ask Jaxon rather than adding a visible element.
- Card `card-title` is a plain `<a href="...">` with no `target`/`rel`; same-tab links throughout.
- Card `card-meta` is a short line `<category> &middot; <stack/notes>` (e.g. "Node.js tool ·
  evolutionary search"), never a raw repo URL or domain.
- Token table Model column uses friendly names (`Sonnet 5`, `Fable 5.1`, `Opus 5`), never API
  slugs.
- Project pie = project shares + Misc + Unused summing to 100%, against the weekly cap %. `p` is
  the real figure Jaxon gave (100% for a week that hit the cap); never call it assumed or
  estimated on the page.
- "Usage by model" pie sits above the total cost, which is last in the projects section; it is
  split by effort, uses the script's `color` values, sums to 100%, has no Unused slice.
- Each card with `features` has the collapsed drawer (name + weekly % + by-model pie per
  feature; feature %s sum to the project's weekly %).
- Title includes the date range, matching the eyebrow.
- Fonts, color tokens and section structure match section 4 exactly: no substituted fonts,
  invented tokens, or reordered/renamed sections.
- Desktop layout exactly as above: `section projects` / `section dives` classes, the
  `desktop-layout` style and `desktop-layout-js` script verbatim. Only classes beyond the base
  ones: `projects`, `dives`, and script-created `mgrid`, `mcol`.
- Rendered check (headless browser if available): at 1440px and 1920px content spans at least 80%
  of the window; `document.documentElement.scrollWidth <= innerWidth` at 360, 768, 1024, 1440,
  1920 and 2560px in light and dark; at 390px the page is a single column.

Re-read this checklist against the finished HTML immediately before publishing.

## 5. Add this week to the Roundup Archive

**Roundup Archive** (`https://claude.ai/code/artifact/61e892af-ab44-48cb-9c9b-74ee690c6dad`,
`archive_url` in `state.json`) is a gallery of every week: a thumbnail donut per week that expands
to the full pie + legend on hover. It reads its own `db` at load, so adding a week is a database
write, never a republish of its HTML.

After publishing this week's roundup, write one document to its `weeks` collection via `Artifact`
(`action: "write_db"`, `db_op: "set"`, `url: archive_url`, `collection: "weeks"`,
`doc_id: "<window-start, YYYY-MM-DD>"`):

```
{
  "weekStart": "<window-start, YYYY-MM-DD>",
  "label": "<eyebrow date range, e.g. 'Sep 6–11, 2026'>",
  "url": "<this week's roundup artifact URL>",
  "projectCount": <number of projects in the Projects list>,
  "totalCost": <the total-cost number, as a plain float>,
  "slices": [
    {"name": "<project name>", "pct": <weekly %>, "color": "<project's accent color>"},
    ...one entry per project, in the same order as the pie chart...,
    {"name": "Misc (other sessions)", "pct": <misc %>, "color": "#9aa2b1"},
    {"name": "Unused", "pct": <unused %>, "color": "#666f7d"}
  ]
}
```

Omit the "Unused" slice if `unused_pct` is 0.

## 6. Update state

Write `state.json`: `{"last_run": "<today's date>", "last_artifact_url": "<published url>",
"archive_url": "https://claude.ai/code/artifact/61e892af-ab44-48cb-9c9b-74ee690c6dad",
"last_cap_usage_pct": <p>}`.

## Notes

- If zero repos had activity in the window, still publish a short artifact saying so.
- Keep tool calls modest: commit logs, diffs of significant commits, and README/screenshot lookups
  are enough; don't read entire repos.
