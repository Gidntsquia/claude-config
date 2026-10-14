---
name: weekly-roundup
description: Build or add to the "Weekly Roundup" artifact summarizing projects worked on this week — pulled from git activity under ~/files, pooled across every machine that uses this Claude account, with a per-project deep dive. Use when the user asks for a weekly roundup, weekly recap, or what they worked on this week.
---

# Weekly Roundup

Produces one HTML artifact per run: projects worked on and a deeper look at each project
(picture + one paragraph). Styled like the Pokemon Go Podium artifacts — tight,
data-dense, no filler.

## 0. Pick the week and find its page

The user names the week to build or update: "this week" (the default when they don't say),
"last week", or a date in it. A week runs Sunday 22:00 local to the next Sunday 22:00; its
`weekStart` is that first Sunday's date. Any week can be updated in place, current or past.

Several machines share this Claude account (Jaxon's and Jaxon's brother's). Each week has one
roundup artifact, and every machine's run adds its own data to it: the first run of the week
creates the page, later runs (from any machine, or a rerun from the same one) update it in
place. The pooled raw data lives inside the page in
`<script type="application/json" id="roundup-data">`; `gather_data.py` reads it, swaps in this
machine's fresh data, and writes the merged pool back out. Never rely on this machine's
`state.json` to find the week's page; another machine may have made it.

1. Read the Roundup Archive (`Artifact` action: read, `url` = `archive_url` below). Keep the
   saved file path; step 5 rebuilds from it. Its `weeks-data` block lists every week's `url` by
   `weekStart`.
2. If the chosen week's `weekStart` is listed, this is a **joining run** (and a **rerun** when the
   page's `roundup-data` already has an entry for this machine's hostname). Never publish a new
   artifact for a listed week; always update its artifact in place. Read that artifact: read that artifact and
   keep its saved file path (`<this-week page>`). Take `window_start` and `token_window_start`
   from its `roundup-data` block and use them below, so every machine counts the same window.
   If the page has no `roundup-data` block, it was built before pooling: leave that week as it
   is, tell the user, and stop.
3. Otherwise this is a **first run** for that week: no `--pool-in`.
4. The previous and next weeks' artifacts are the archive entries on either side of the chosen
   `weekStart` (no next week when it is the current week).

## 1. Determine the window and run the data script

The project/commit window and the token window both start at the chosen week's Sunday 22:00 and,
for the current week, run to now (omit `--token-window-end`; `--window-end` is today). For a past
week, pass `--token-window-start` and `--token-window-end` as the Sunday 22:00 boundaries on each
side and `--window-end` as the closing Sunday's date. Never use `last_run` from `state.json` as the window start; it is only a
record of when the skill last ran.

Ask the user for `cap-pct` (% of the chosen week's cap consumed) every run, together with who
the usage belongs to (below). It is account-wide,
and the most recently entered figure always wins: if Jaxon ran at 60% and his brother later
enters 70%, the page uses 70%, and the 70% stays when anyone reruns without entering a new one.
On a joining run, show the pool's stored `cap_pct` and `cap_pct_at` in the question; if the user
keeps it (e.g. a past week whose final figure is already in), omit `--cap-pct` and the script
reuses it. On a first run `--cap-pct` is required. `last_cap_usage_pct` in `state.json` only
prefills the question on a first run; never reuse it silently. The script warns when a new
figure is lower than the stored one (usage only rises within a week); confirm it with the user.

Ask the user **who this machine's usage belongs to** every run, in the same question as
`cap-pct` (one AskUserQuestion with both). Prefill with `person` from `state.json` when it exists
(and, on a joining run, this device's `person` stored in the pool); the answer is passed as
`--person "<answer>"` exactly as typed. The script matches it fuzzily (case, punctuation, extra
words, typos and short forms all ignored) against the pool's people and the account's known
people (`KNOWN_PEOPLE` in `gather_data.py`: Jaxon, Jet), so anything like "jet", "Jett", "jet
Lee" pools into "Jet" and "jaxon.", "jax", "Jaxson" into "Jaxon"; a name that matches nobody
starts a new person. Never normalize the answer yourself. Each person gets their own color
scheme once the week's pool has two or more people (first person seen: `warm`, 12 accents in
reds, oranges, pinks, magentas, golds and browns, hues 300-60°; second: `cool`, 12 accents in
blues, greens, teals, indigos and violets, hues 90-290°; then berry and earth, 6 each). No two
accents of one palette sit within 15° of hue and 10% of lightness of each other, and the warm and
cool hue ranges do not overlap, so two people never share a hue. With one person, projects use
the whole color wheel (the script's `full` palette), as in the early roundups; a second person
joining switches the week to the per-person schemes.

**Stable project colors.** `project_colors.json` (this skill's directory, committed) maps
`<person>|<project key>` to an accent; the key is the project's GitHub remote URL, else its
folder name, and a single-person week uses `solo|<key>`. A mapped project keeps its accent week
after week (while that accent is still in the person's palette). A new project gets the first
accent of its person's palette not yet used this week, else the accent used least in the map,
then the palette cycles (a 13th project reuses one). The map travels in the page's
`roundup-data` (`project_colors`); each run merges the page's map over the local file (the page
wins on conflict), uses it, and writes the merged map back to both. A week that goes from one
person to two gets fresh per-person colors (`solo|` entries stay for later solo weeks).
`--colors-file` overrides the file path (tests only). Store
the answer as `person` in `state.json` (step 6).

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
  --person "<who this machine's usage belongs to>" \
  --plan-cost 100 \
  --pool-out <scratch>/pool.json \
  [--pool-in <this-week page>]   # joining run only
```

(`$SKILL_DIR` is this skill's directory.) `--device` defaults to `<user>@<hostname>`; this
machine's previous entry in the pool (same hostname, the text after `@`) is replaced completely,
other machines' entries are kept. If the hostname is already in the pool under a different
person the script exits with an error naming both people and the hostname: stop, report it to
the user, and do not work around it. On a rerun the output has `rewrite` (`hostname`,
`replaced_collected_at`, `projects`, `fixed`) and the pool's `authored` map passes through.
If `~/files` doesn't exist on this machine, ask the user where their repos live and pass
`--files-dir`. The same project on two machines merges by GitHub remote, else by repo folder
name; shared commits and sessions count once.

It prints JSON for the pooled week: `people` (person, palette name, `color`, `accents`, devices,
sessions, fe_tokens, cost, weekly_pct; in palette order), `pie_slices` (one per project x person
plus Misc per person: label, pct, color; grouped by person, most-used person first, each
person's projects by usage then their Misc; the projects pie, ready to draw), `devices` (label,
person, collected_at), `projects` (name, path, remote_url, commits, screenshot path, token_rows
per model, fe_total, cost_total, weekly_pct, `accent`, `lead_person`, `people` (per-person
fe_tokens, weekly_pct, pct of the project, color), `sessions`), `misc` (with `people`),
`unused_pct`, `implied_cap_fe`, `combined_cost`, `days` (7 entries, Sunday through Saturday of the
week, local calendar days: `date`, `label` "Sun".."Sat", `segments` [{project, person, color,
pct}] largest first, `total_pct`; `pct` is weekly-cap %, the same basis as `weekly_pct`, so a
project x person's days sum to its pie slice and all days sum to 100 - `unused_pct`; colors are
the pie's; the opening Sunday's 22:00-midnight and the closing Sunday up to 22:00 both land in
the Sunday column, since the week runs Sunday 22:00 to Sunday 22:00), `model_breakdown` (per model across all
projects + Misc: model_display, raw_tokens, fe_tokens, cost, usage_pct), `model_effort_breakdown`
(per family x effort: label, color, usage_pct), `unpriced_models`. Use its numbers and colors
directly; do not recompute them.

If a project's `remote_url` is empty, name it without a link. If it has no `screenshot`, omit the
picture. Check each project's README yourself for a deployed-app URL (Vercel/Netlify/Pages/etc;
the script doesn't) and use it as the "Link" instead of the GitHub link when present.

Also list artifacts (`Artifact` action: list) updated in the window; they count as project work
even without a git commit (e.g. the Pokemon Go Podium tools). The script can't see them; add them
manually with a placeholder/zero token row if no matching Claude project directory exists.

### Key features per project

Each project's `sessions` list (id, start, first prompt, device, person, fe_tokens, weekly_pct; subagent
usage is already in its parent session) feeds the drawer's feature breakdown. For each project with
sessions, pick roughly 2-6 key features (what was built or changed this week) and assign every
session belonging to one, judging by first prompts, commit subjects and diffs. Write
`{"<project name>": {"<Feature name>": ["<session id or unique prefix>", ...]}}` to a scratch file
and rerun the script (same arguments) with `--features-file <file>`. On a joining run, start from
the `features` map already in `<scratch>/pool.json` (the script applies it by default) and only
assign this machine's sessions (other machines' sessions have an empty prompt and are already
assigned); add new features or reuse existing names. On a rerun the script has already dropped
every link to this machine's earlier sessions: reassign all of this machine's sessions from
scratch, reusing existing feature names where they fit, and keep other machines' links. A link to
a session no longer in the pool is warned about on stderr and dropped. The file you pass replaces the stored map. Each project then gains `features`: name,
fe_tokens, weekly_pct (same basis as the project's `weekly_pct`; features sum to it), sessions,
`models` (family, color, pct of that feature's tokens) and `people` (person, color, pct of that
feature's tokens). Unassigned sessions land in an
automatic "Other" feature; a session goes to exactly one feature. Fix any `no session matches`
warnings on stderr. Use the rerun's output for everything downstream. A project with no sessions
(artifact-only) gets no drawer.

Read a few actual diffs for the meatiest commits (each project's `commits` list), not just commit
messages, to inform the deep-dive paragraphs. Diffs only exist for repos on this machine.

### Joining run: build on the existing page

Start from `<this-week page>`, not from scratch. Keep every existing card's picture, paragraph,
card-meta and link, and every "Things fixed" entry. Replace all numbers and colors (project
list, pies, person tags, total cost, token tables, drawers, Data sources) with the new output,
which already covers every machine; accents come from the output's `accent` and can change when
another person now leads a project. Add cards (and pie slices, list rows) for projects only
this machine worked on. Add "Things fixed" entries from this machine's transcripts, each with a stable text id
(`data-fixed-id="<slug>"` on the entry).

**Rerun (the output has `rewrite`):** for every project in `rewrite.projects`, rewrite the
deep-dive paragraph, re-pick the picture and card-meta from the current repo state; re-derive
this machine's "Things fixed" entries from transcripts and remove the old ones listed in
`rewrite.fixed`. Cards and entries owned by other hostnames are kept verbatim. Numbers and colors
are always replaced. Never duplicate a card, list row, pie slice, Data sources row or "Things
fixed" text. When embedding, record authorship:
`embed_pool.py --pool ... --html ... --hostname <hostname> --wrote-projects "<names>" --wrote-fixed "<ids>"`
(every card and entry this run wrote or rewrote). In the report to the user say "replaced this
machine's earlier data from <replaced_collected_at>" and list what was rewritten.

## 4. Write the artifact

Follow the `artifact-design` skill, then build one HTML page. When the HTML is final, embed the
pool: `python3 "$SKILL_DIR/embed_pool.py" --pool <scratch>/pool.json --html <page>` (adds or
replaces the `roundup-data` block; rerun it after any later edit that rewrites the page).

- Reuse the Podium visual language: Barlow Condensed headings / Source Sans 3 body (Google
  Fonts), light/dark tokens (`--ground`, `--card`, `--ink`, `--muted`, `--line`, `--blue`,
  `--shadow`), section headers with a trailing `<div class="rule">`, cards with a colored top
  border, tabular-nums for numbers.
- Each project's accent color is the output's `accent` (a shade from the color scheme of the
  person who did most of its usage, `lead_person`; warm for one person, cool for the other,
  distinct per project; the whole color wheel when the pool has one person). Use it for the project's name pill in the top list, the "Link" text in
  that row, and `--accent` on its deep-dive card (top border, title color, token-table header
  rule). Never invent accents.
- **Who did what**: the output's `people` carries each person's `color` and palette. Whenever the
  pool has more than one person, show the split: in the top list a small person tag after each
  project's usage % (`<span class="who" style="--c:<color>">Jet 12%</span>` per `people` entry,
  colored with the person's share color), the projects pie split per `pie_slices` (one slice per
  project x person in that person's colors, legend labels as given, e.g. "alpha-app · Jet",
  "Misc · Jaxon"), a "Usage by person" legend row under the project pie (swatch in `people[].color`,
  name, weekly %), and a person tag on every drawer feature row carrying that feature's `people`
  entries. Deep-dive card-meta ends with "· by <lead_person>" when the project has more than one
  person. With one person in the pool, omit the tags and labels; the person's colors still apply.
- Structure, top to bottom:
  1. Title + eyebrow with the date range covered.
  2. **Projects this week** — numbered list; each row: `<num>. <name pill>` on the left, then a
     `Link` hyperlink (deployed app if any, else GitHub; omit if none) and the project's weekly
     usage % on the right. The pill links to the project's deep-dive card (`#slug` id on the
     card's `div.card`); `Link` goes to the external repo/app. Usage % is the project's FE tokens
     over the week's grand total FE tokens (see Token breakdown). Sort by usage % descending.
     Below the list, a pie chart (CSS `conic-gradient` circle + swatch legend): the output's
     `pie_slices` in order, never re-sorted (grouped by person: the person with the most usage
     first with all their projects in their colors and then their Misc in their gray, then the
     next person's; label and color as given), and a final "Unused" slice
     colored `var(--muted)`, computed against the actual weekly cap usage (see Token breakdown),
     not just 100%. Under its legend, the "Usage by person" row (see above).
     Double-tapping (or double-clicking) a projects-pie slice or its legend label scrolls to that
     project's deep-dive card; a single tap still only selects it. Paste this script verbatim in
     `<script id="pie-jump-js">` right before `desktop-layout-js`. It matches the slice/legend
     `data-name` (minus a trailing " · <person>") to a list row's pill text and jumps to the pill's
     `#slug` card, so Misc, Unused and the model pie do nothing:
     ```js
(function(){var map={};document.querySelectorAll('.proj-btn[href^="#"]').forEach(function(a){map[a.textContent.trim()]=a.getAttribute('href').slice(1)});
function card(n){if(!n)return null;var i=n.lastIndexOf(' · '),id=map[n]||(i>0?map[n.slice(0,i)]:null);return id?document.getElementById(id):null}
var last=null,at=0;
document.querySelectorAll('svg.pie,.piechart-legend').forEach(function(el){el.style.touchAction='manipulation'});
document.querySelectorAll('svg.pie .pie-slice[data-name],.piechart-legend li[data-name]').forEach(function(el){el.addEventListener('click',function(){
var n=el.dataset.name,t=Date.now(),c=card(n);if(!c)return;
if(last===n&&t-at<450){last=null;c.scrollIntoView({behavior:'smooth',block:'start'})}else{last=n;at=t}})})})();
     ```
     Below it, a second pie (same style) titled "Usage by model": one slice per entry of
     `model_effort_breakdown` (all projects + Misc; one entry per model family x effort), sized by
     `usage_pct` (FE-token weighted). Slices sum to 100% of used tokens; no "Unused" slice. Color
     each slice with the entry's `color` exactly as given (one hue per family: Sonnet blue, Fable
     purple, Opus orange, Haiku green; darker = higher effort, low -> max). Slices arrive ordered
     family, then effort, so a family's shades sit together. Legend: rows grouped by family, each
     a swatch + `label` (e.g. "Sonnet · low") + percentage. Versions of a family (Fable 5 / 5.1)
     are merged. Local Qwen models are priced $0 and never appear in this pie, the tables, or the
     cost. If `unpriced_models` is non-empty, they were priced at Sonnet 5 rates as a fallback; add
     them to the price table and tell the user when reporting, not on the page.
     Below that pie, a big total-cost figure (no label), the summed dollar Cost across all
     projects plus Misc, formatted like `$942.02`, with a small caption underneath: "Equivalent
     pay-by-token API price; actually paid $100 / mo" (plan cost hardcoded; update here if it
     changes). The total cost is the last thing in this section, below both pies.
     **Usage by day**, between the "Usage by model" pie and the total cost: a stacked bar chart
     of the output's `days`, drawn by the bundled script, never by hand or by page JS:
     `python3 "$SKILL_DIR/daychart.py" --data <output.json> --part html --names <names.json>`
     prints the `<div class="barchart-wrap">` block (its own `<h2 class="sub">Usage by day</h2>`,
     a y-axis with labels every 5% up to the tallest day rounded up to the next 5%, dashed
     gridlines, 7 columns Sun..Sat, each a stack of segment divs largest at the bottom with
     `title="<project> · <person> · <x.x>%"` (person omitted with one person), and the caption
     "Colors match the projects pie above."; no legend). `--names` is a JSON file mapping the
     output's project names to the names used on the page (`{"helper-agent-building": "Helper
     Agent"}`) so hover titles match the pie. `--part css` prints its CSS: paste it verbatim in
     `<style id="daychart">` right before the `desktop-layout` style. All heights are computed
     by the script; the page does no percentage math.
  3. **Things fixed** — short section between the projects list and the deep dives, only for big,
     non-obvious issues the user hit and resolved that week: things that broke their environment, cost
     real time, or whose fix they'd want to remember (e.g. "leftover Ollama install was crashing
     WSL — had to fully uninstall it"). Find them by reading the window's session transcripts
     (`~/.claude/projects/*/`) for moments outside normal feature work (crashes, broken
     environments, corrupted state, misconfigured tools) where they had to stop and fix something.
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
  5. **Data sources** — last thing before the footer, collapsed so it takes one line: a
     `<details class="drawer sources">` (summary "Data sources", `--accent: var(--muted)`, no
     section header) opening to a small table with one row per entry of the output's `devices`:
     Machine (`device`) / Person (`person`, with a swatch in that person's `color`) / Collected
     (`collected_at`, as e.g. "Oct 9, 2:15 PM") / Sessions / Cost / Weekly %, then one line under
     it: "Weekly cap usage: <p>% (entered <cap_pct_at>)". All other pooled detail stays in the
     invisible `roundup-data` block.

### Desktop layout (screens 1000px and wider; phones unchanged)

The base CSS is a single narrow column (`body` max-width 760px); nothing below applies under
1000px.

- Mark the two main sections `<div class="section projects">` ("Projects this week") and
  `<div class="section dives">` ("Project deep dives"). Children stay in order: in `.projects`,
  `h2`, `.rule`, `ul.plain`, first `.piechart-wrap`, `h2.sub`, second `.piechart-wrap`,
  `.barchart-wrap`, `.total-cost`; in `.dives`, `h2`, `.rule`, then the `.card`s. A "Things fixed" section, if
  present, stays a plain `<div class="section">` in between, its list in 2 columns.
- Body max-width 1680px, padding `36px 48px 72px`. Projects: two equal columns, 64px gap; left is
  the numbered list, right is the project pie then "Usage by model" and its pie, then "Usage by
  day" (`.barchart-wrap`) goes in whichever column leaves the two closest in height (the
  `projects-layout-js` script below measures and moves it: usually the left column, under the
  numbered list, since the pies' legends make the right column longer; grid row 6 of the right
  column is only the no-script fallback); total cost spans both underneath. Deep dives: cards in 2 columns from 1000px, 3 from 1500px, 32px gap; card
  images cropped to a 21:8 banner, body padding `22px 26px 24px`.
- The script below puts each card, in order, into the currently shortest column so columns end at
  similar heights. It wraps the cards in `div.mgrid` > `div.mcol` at run time; do not write those
  in the HTML. It re-flows on resize and font load, not on drawer open. Without it the CSS still
  works as a plain equal-height grid.
- Paste the CSS and script verbatim, unchanged: CSS in `<style id="desktop-layout">` after the
  base styles, script in `<script id="desktop-layout-js">` at the end of `<body>`, then the second script below in `<script id="projects-layout-js">` (it wraps the list, pies and chart in `div.pgrid` > `div.pcol` at run time; do not write those in the HTML). Mobile styles
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
.projects>.barchart-wrap{grid-column:2;grid-row:6;margin-top:22px}
.projects>.total-cost{grid-column:1/-1;grid-row:7;margin-top:26px}
.section:not(.projects):not(.dives)>ul{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));column-gap:64px}
.dives{grid-template-columns:repeat(2,minmax(0,1fr));gap:32px;align-items:stretch}
.dives>.card{margin-bottom:0;display:flex;flex-direction:column}
.dives>.card>.card-body{flex:1;display:flex;flex-direction:column}
.dives>.card>.card-body>table.tokbreak{margin-top:auto}
.projects.pg{display:block}
.pgrid{display:flex;gap:64px;align-items:flex-start}
.pcol{flex:1 1 0;min-width:0}
.projects.pg>.total-cost{margin-top:26px}
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

```js
(function(){var s=document.querySelector('.projects');if(!s)return;var ul=s.querySelector('ul.plain'),ch=s.querySelector('.barchart-wrap'),tc=s.querySelector('.total-cost');if(!ul||!ch||!tc)return;var mid=[].slice.call(s.children).filter(function(c){return c!==ul&&c!==ch&&/piechart-wrap|sub/.test(c.className)});var g=null;
function undo(){if(!g)return;s.insertBefore(ul,tc);mid.forEach(function(c){s.insertBefore(c,tc)});s.insertBefore(ch,tc);g.remove();g=null;s.classList.remove('pg')}
function lay(){undo();if(innerWidth<1000)return;s.classList.add('pg');g=document.createElement('div');g.className='pgrid';var L=document.createElement('div'),R=document.createElement('div');L.className=R.className='pcol';g.appendChild(L);g.appendChild(R);s.insertBefore(g,tc);L.appendChild(ul);mid.forEach(function(c){R.appendChild(c)});
R.appendChild(ch);var a=Math.abs(L.offsetHeight-R.offsetHeight);L.appendChild(ch);var b=Math.abs(L.offsetHeight-R.offsetHeight);if(a<b)R.appendChild(ch)}
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
  `gather_data.py`. Keep that table current when Anthropic pricing changes. A model priced by
  prompt length (Haiku 5.5: higher rates over 100,000 prompt tokens) has a `long_over` entry;
  each request over it is tallied under `<model>@long` and priced at that entry's rates, and
  both tiers show as one row on the page.
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
- Test and scratch folders belong to the project they test, not their own card: demo apps built
  to try an agent, replays of agent runs, sample projects. Fold them with `MOVED_FROM`
  (`"<parent repo>": ["<folder>"]`, or `"<folder>/<subfolder>"` to fold one subfolder when a
  scratch folder serves several projects) and assign their sessions to a feature of the parent.
  Check every small project's first prompts before writing a card for it; ask the user when the
  parent isn't clear. Current folds: first-project and tip-calculator -> helper-agent-building;
  replay/ worker replays -> worker-building, evaluator replays -> evaluator-building.
- Favicon: 🗓️. Title: "Weekly Roundup — <date range>" (e.g. "Weekly Roundup — Sep 6-11, 2026"),
  matching the eyebrow so artifacts are distinguishable in the list.
- Publish with `Artifact`. Joining run: pass the chosen week's artifact URL as `url` to update it in
  place (already read in step 0). First run: publish a new artifact.
- Artifacts start private. After publishing, remind the user to share it (claude.ai Share button →
  public link); the tool has no publish-time flag for this.

## Prev/next week navigation

- The previous week's artifact comes from the archive (step 0); read it (`Artifact` action:
  read) before building the new page. On a joining run the nav row already exists; keep it and
  skip the republish steps below.
- Add a "← Previous week" link to that URL near the title/eyebrow. Add "Next week →" only when
  the archive has a later week (a first run for a past week); for the current week omit it
  entirely (no placeholder self-link).
- In the same `.weeknav` row add a "Dashboard" link to the Roundup Archive (`archive_url` in
  `state.json`), always.
- After publishing, republish the previous week's artifact with its "Next week →" pointing at the
  new URL (adding the link if it had none), and, for a past week, the next week's artifact with
  its "← Previous week" pointing at it.
- The very first roundup (no earlier archive week) has no previous week: omit or gray out the
  "← Previous week" link.

## Output checklist (verify before publishing)

Every artifact, including one-off or backfilled reports, must satisfy all of these and read
identically to a normal week: no report-type-specific notes, disclaimers, or wording.

- Footer text is exactly `Generated by the weekly-roundup skill`, no variants.
- No extra paragraphs, notes, or CSS classes beyond this file (no `.backfill-note` etc.). If
  something is unusual (missing data), ask the user rather than adding a visible element.
- Card `card-title` is a plain `<a href="...">` with no `target`/`rel`; same-tab links throughout.
- Card `card-meta` is a short line `<category> &middot; <stack/notes>` (e.g. "Node.js tool ·
  evolutionary search"), never a raw repo URL or domain.
- Token table Model column uses friendly names (`Sonnet 5`, `Fable 5.1`, `Opus 5`), never API
  slugs.
- Who did what is visible when the pool has more than one person: person tags in the list and
  drawers, pie slices per project x person from `pie_slices`, the "Usage by person" row, and the
  Person column in Data sources; every person color comes from the script (warm vs cool schemes
  from two people on; one full-range palette for a single person).
- Project pie = `pie_slices` + Unused summing to 100%, against the weekly cap %. Pie and legend
  keep `pie_slices` order: one person's slices together (most-used person first), then the next. `p` is
  the real figure the user gave (100% for a week that hit the cap); never call it assumed or
  estimated on the page.
- "Usage by model" pie sits above the total cost, which is last in the projects section; it is
  split by effort, uses the script's `color` values, sums to 100%, has no Unused slice.
- `pie-jump-js` is present verbatim: double-tapping a project slice or legend label lands on its
  deep-dive card.
- "Usage by day" (`daychart.py` output, unedited) sits between the "Usage by model" pie and the
  total cost: 7 labeled columns, 5% gridlines, segment colors equal to the pie's, the caption.
- Each card with `features` has the collapsed drawer (name + weekly % + by-model pie per
  feature; feature %s sum to the project's weekly %).
- Title includes the date range, matching the eyebrow.
- Fonts, color tokens and section structure match section 4 exactly: no substituted fonts,
  invented tokens, or reordered/renamed sections.
- Desktop layout exactly as above: `section projects` / `section dives` classes, the
  `desktop-layout` style and `desktop-layout-js` script verbatim. Only classes beyond the base
  ones: `projects`, `dives`, `sources`, `who`, `people`, the `daychart.py` classes
  (`barchart-wrap`, `bc`, `bc-y`, `bc-plot`, `bc-grid`, `bc-col`, `bc-bar`, `bc-seg`, `bc-x`,
  `bc-cap`), and script-created `mgrid`, `mcol`, `pgrid`, `pcol`, `pg`.
- The collapsed "Data sources" drawer is present, lists every entry of `devices` with its
  person, and shows the cap % used.
- Rendered check (headless browser if available): at 1440px and 1920px content spans at least 80%
  of the window; `document.documentElement.scrollWidth <= innerWidth` at 360, 768, 1024, 1440,
  1920 and 2560px in light and dark; at 390px the page is a single column.

- The page has exactly one `<script type="application/json" id="roundup-data">` block, written
  by `embed_pool.py` from this run's `pool.json`, and the output's `devices` lists every machine
  that was in the pool before this run plus this one. On a rerun the `devices` count equals the
  count before the run, and the page has one list row, one pie slice per person, one card per
  project and one Data sources row per machine.

Re-read this checklist against the finished HTML immediately before publishing.

## 5. Add this week to the Roundup Archive

**Roundup Archive** (`https://claude.ai/code/artifact/61e892af-ab44-48cb-9c9b-74ee690c6dad`,
`archive_url` in `state.json`) is a gallery of every week: a thumbnail donut per week that expands
to the full pie + legend on hover. Above the gallery, a "Usage by day" chart runs continuously
across every archive week: 7 columns per week, oldest left, the week label (e.g. "Oct 4–11")
under each week, a thin rule between weeks, the same y-scale throughout, scrolled to the newest
week on load. Weeks stored without `days` show as 7 empty columns with a faint "no daily data"
marker. `build_archive.py` draws it with `daychart.py`. Its weeks are written into the page itself (no `db`), so
anyone with the public link sees every week. The data lives in `archive_weeks.json` next to this
file; `archive_template.html` is the page.

After publishing the roundup, write the chosen week to a scratch JSON file, then run
`python3 "$SKILL_DIR/build_archive.py" --base <archive file read in step 0> --add <file> --out
<scratch>/archive.html` (it takes the weeks from the published archive, since other machines
update it too, inserts or replaces this week by `weekStart` (the added week must carry `days`; older entries are
kept as they are), saves them to
`archive_weeks.json` and builds the page) and republish the page with `Artifact`
(`url: archive_url`; omit `capabilities`).
Commit `archive_weeks.json` in `~/files/claude-config` if this machine has that repo. Never give the archive a `db`: a `db` page
is organization-only, so public viewers would not see the weeks.

```
{
  "weekStart": "<window-start, YYYY-MM-DD>",
  "label": "<eyebrow date range, e.g. 'Sep 6–11, 2026'>",
  "url": "<the chosen week's roundup artifact URL>",
  "projectCount": <number of projects in the Projects list>,
  "totalCost": <the total-cost number, as a plain float>,
  "slices": [
    {"name": "<slice label>", "pct": <weekly %>, "color": "<slice color>"},
    ...one entry per `pie_slices` entry, same order and colors as the pie chart
       (e.g. "alpha-app · Jet", then "Misc · Jet")...,
    {"name": "Unused", "pct": <unused %>, "color": "#666f7d"}
  ],
  "days": <the output's `days`, with each segment's `project` swapped for the page's display
           name (as passed to daychart.py --names)>
}
```

Omit the "Unused" slice if `unused_pct` is 0. Slices must sum to 100: when cap usage is over
100%, divide every weekly % by `p/100`.

## 6. Update state

Write `state.json` (when the chosen week is a past week, keep the existing `last_artifact_url` and
`last_cap_usage_pct`): `{"last_run": "<today's date>", "last_artifact_url": "<published url>",
"archive_url": "https://claude.ai/code/artifact/61e892af-ab44-48cb-9c9b-74ee690c6dad",
"last_cap_usage_pct": <p>, "person": "<the person the user named this run, as the output's
devices entry spells it>"}`.

## Notes

- When reporting, list the machines in the output's `devices` with their `person` and `collected_at`. A
  machine whose data is days old makes the Unused slice look bigger than it is (its newer usage
  is in the cap % but not in the pool); say so.

- If zero repos had activity in the window, still publish a short artifact saying so.
- Keep tool calls modest: commit logs, diffs of significant commits, and README/screenshot lookups
  are enough; don't read entire repos.
