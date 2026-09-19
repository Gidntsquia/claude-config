---
name: weekly-roundup
description: Build a "Weekly Roundup" artifact summarizing projects Jaxon worked on in the past week — pulled from git activity under ~/files, with a per-project deep dive. Use when Jaxon asks for a weekly roundup, weekly recap, or asks what he worked on this week.
---

# Weekly Roundup

Produces one HTML artifact per run: projects worked on and a deeper look at each project
(picture + one paragraph). Styled like Jaxon's Pokemon Go Podium artifacts — tight,
data-dense, no filler.

## 1. Determine the window and run the data script

Both the project/commit window and the token-breakdown window always start at the beginning of
the current Claude usage week — the most recent Sunday at 10pm (local time) — up to now. This
resets every week on that boundary; do not use `last_run` from `state.json` as the window start.
`state.json`'s `last_run` is kept only as a record of when the skill last ran, not as an input to
the window.

Ask Jaxon for `cap-pct` (% of weekly cap consumed so far) fresh every run — never reuse
`last_cap_usage_pct` from `state.json` silently; it only exists to prefill your question with
last week's value.

`plan-cost` (flat-rate plan cost, $/mo) is hardcoded at `100` below — update that value
directly in this file if the plan cost changes.

Then run the bundled script once to do all the deterministic data-gathering (git scanning,
remote/screenshot lookup, jsonl token tallying, pricing, FE-token normalization, weekly-cap
math) in a single process instead of many ad hoc tool calls:

```
python3 "$SKILL_DIR/gather_data.py" \
  --window-start <project window start, YYYY-MM-DD> \
  --window-end <today, YYYY-MM-DD> \
  --token-window-start <most recent Sunday 22:00 local, ISO datetime> \
  --cap-pct <p> \
  --plan-cost 100
```

(`$SKILL_DIR` is this skill's directory.) It prints JSON: `projects` (name, path, remote_url,
commits, screenshot path, token_rows per model, fe_total, cost_total, weekly_pct), `misc`,
`unused_pct`, `implied_cap_fe`, `combined_cost`. This replaces step 2 and the "Token
breakdown" math below — use its numbers directly rather than recomputing them.

If a project's `remote_url` is empty, no GitHub link exists — name it without a link. If a
project has no `screenshot`, omit the picture. Check the README of each project for a
deployed-app URL (Vercel/Netlify/Pages/etc) yourself — the script doesn't do this — and use
that as the "Link" instead of the GitHub link when present.

Also check `Artifact` list (action: list) for artifacts updated in the window — these count as
project work too (e.g. the Pokemon Go Podium tools) even without a git commit, since some of
Jaxon's project iteration happens purely in artifacts. The script won't see these; add them
manually with a placeholder/zero token row if no matching Claude project directory exists.

Read a few actual diffs for the meatiest commits (from each project's `commits` list) rather
than trusting commit messages alone — this is what informs the deep-dive paragraphs next.

## 4. Write the artifact

Follow the `artifact-design` skill's guidance, then build one HTML page:

- Reuse the visual language from Jaxon's Podium artifacts: Barlow Condensed for headings /
  Source Sans 3 for body (Google Fonts), light/dark tokens (`--ground`, `--card`, `--ink`,
  `--muted`, `--line`, `--blue`, `--shadow`), section headers with a trailing `<div class="rule">`
  line, cards with a colored top border, tabular-nums where numbers appear.
- Assign each project a distinct accent color (pick visually distinct hues, avoid reusing
  `--blue`). Use that color for: the project's name rendered as a pill/button in the top list,
  the "Link" text in that row, and as `--accent` on its deep-dive card (top border, title color,
  token-table header rule).
- Structure, top to bottom:
  1. Title + eyebrow with the date range covered.
  2. **Projects this week** — numbered list, each row: `<num>. <name pill>` on the left, then
     a `Link` hyperlink (deployed app if one exists, else GitHub — omit if no link) and the
     project's weekly usage % on the right. The name pill is itself a link to that project's
     deep-dive card (`#slug` anchor id on the card's `div.card`) — separate from the `Link`
     hyperlink, which goes to the external repo/deployed app. Compute usage % as each project's
     FE-token total over the week's grand total FE tokens (see token breakdown below), so the
     column sums to 100%. Sort by usage % descending.
     Below the list, add a pie chart (CSS `conic-gradient` circle + a swatch legend) with a
     slice per project, a "Misc" slice (neutral gray, e.g. `#9aa2b1`) for untracked-project
     usage, and a final "Unused" slice colored `var(--muted)` — see Token breakdown below for
     how these percentages are computed against the actual weekly cap usage, not just 100%.
     Below the pie chart, show a big total-cost number (no label, just the figure): sum the
     dollar Cost (see Token breakdown) across all projects plus Misc, formatted like `$942.02`,
     with a small caption
     underneath reading "Equivalent pay-by-token API price; actually paid $100 / mo" (hardcoded
     plan cost — update in this file if it changes).
  3. **Things fixed** — a short section between the projects list and the deep dives, only for
     big, non-obvious issues Jaxon ran into and resolved during the week — not routine bugs fixed
     in the normal course of coding. Think: things that broke his environment, cost him real time,
     or he'd want to remember the fix for next time (e.g. "leftover Ollama install was crashing
     WSL — had to fully uninstall it"). Find these by reading through the week's session
     transcripts (`~/.claude/projects/*/`, filtered to the window) for moments where something
     went wrong outside normal feature work — crashes, broken environments, corrupted state,
     misconfigured tools — and Jaxon had to stop and fix it. Skip anything that's just "wrote a
     bug, fixed the bug" as part of normal development. If nothing rises to that bar, omit the
     section entirely — don't pad it with minor fixes.
     Format as a plain list, one entry per issue: bold one-line problem statement, then one or two
     plain sentences on the fix, in the write-readme skill's voice (direct, first person where
     natural, no hedging, no "not X but Y" contrasts, no closing reassurance clauses). No card
     styling needed — a simple `<ul>` under the section header is enough.
  4. **Project deep dives** — one card per project: representative picture (if found), a
     tight paragraph (3-5 sentences) on what the app does *as of this report* (written for
     someone with zero context on the project), and a token breakdown table with columns
     Model / Raw tokens / FE tokens / Weekly % (one row per model used on that project this
     week, tabular-nums, sorted by FE tokens descending).

## Token breakdown

All of this is computed by `gather_data.py` (step 1) — its output already gives you, per
project: `token_rows` (model, raw_tokens, fe_tokens, cost), `fe_total`, `cost_total`, and
`weekly_pct`, plus top-level `misc` and `unused_pct`. Use those numbers as-is rather than
recomputing them by hand. For reference, the script's method:

- **Raw tokens** = input + output + cache-read + cache-creation (5m/1h) tokens, per model,
  deduped by message id from the jsonl files under `~/.claude/projects/<slug>/`.
- **Cost** = raw tokens priced per-model (input/output/cache-read at 0.1x input/cache-write at
  1.25x or 2.0x input for 5m/1h) using the price table at the top of `gather_data.py` — keep
  that table current when Anthropic pricing changes.
- **FE tokens** ("Fable-equivalent") = cost normalized to Fable's $10/M input rate, so usage
  across different models becomes comparable in one unit.
- **Misc** = FE tokens from every Claude Code project directory active in the window that
  isn't mapped to a tracked project (ad hoc sessions, one-off scratch work, etc) — a legend/pie
  entry only, no deep-dive card.
- **Weekly cap** — the `--cap-pct` you pass in is `p`; the script derives the implied cap as
  `combined_fe / (p/100)` and each row's `weekly_pct` as that row's FE tokens over the implied
  cap, so project shares + Misc + `unused_pct` (`100 - p`) sum to 100%.
- A project's repo may map to more than one Claude Code project directory (renamed/moved
  repos, or a sandbox copy) — the script sums across all matching directories for that project.
- Favicon: 🗓️. Title: "Weekly Roundup — <date range>" (e.g. "Weekly Roundup — Sep 6-11, 2026")
  — the date range appears in both the title and the eyebrow, so each artifact is
  distinguishable in the artifacts list.
- Publish with `Artifact`. If `state.json` has `last_artifact_url`, pass that as `url` to update
  the same artifact in place rather than creating a new one each week — read it first per the
  Artifact tool's update flow.
- Artifacts start private. After publishing, remind Jaxon to share the artifact (claude.ai Share
  button → public link) so it's public — the Artifact tool has no publish-time flag for this.

## Prev/next week navigation

Every artifact links to the previous week's roundup and the next one, so the whole history is
click-through-able in both directions:

- `state.json`'s `last_artifact_url` (before you overwrite it this run) is the *previous week's*
  artifact — read it (`Artifact` action: read) before building the new page.
- In the new artifact, add a "← Previous week" link pointing at that URL, near the title/eyebrow.
  The new artifact is always the current week, so it never has a "Next week →" link — hide/omit
  that side entirely (don't even self-link it as a placeholder).
- Also add a "Dashboard" link in the same `.weeknav` row, pointing at the Roundup Archive
  (`archive_url` in `state.json`) — every roundup links to it, regardless of prev/next state.
- After publishing the new artifact, go back and republish the previous week's artifact, changing
  its nav so "Next week →" now points at the new artifact's URL (adding that link if the previous
  artifact didn't have one yet, e.g. it was the first roundup).
- The very first roundup (no `last_artifact_url` in `state.json`) has no previous week — omit or
  gray out the "← Previous week" link too.

## Output checklist (verify before publishing)

Every artifact this skill produces — including one-off or backfilled reports — must satisfy all
of these, regardless of run type. A backfilled or historical week reads identically to a normal
one: no report-type-specific notes, disclaimers, or wording anywhere in the page.

- Footer text is exactly `Generated by the weekly-roundup skill` — no variants (e.g. no
  "backfilled report", no run-type annotations).
- No extra paragraphs, notes, or CSS classes beyond what's specified in this file (e.g. no
  `.backfill-note` or similar ad hoc elements) — if something about the run is unusual (assumed
  cap %, missing data), that goes in the caption text already specified (weekly-cap caption,
  total-cost caption) or is asked of Jaxon, never bolted on as a new visible element.
- Card `card-title` is a plain `<a href="...">` with no `target`/`rel` attributes — same-tab
  links throughout.
- Card `card-meta` is a short descriptive line in the form `<category> &middot; <stack/notes>`
  (e.g. "Node.js tool · evolutionary search"), never a raw repo URL or domain.
- Token table Model column uses friendly display names (`Sonnet 5`, `Fable 5.1`, `Opus 5`, etc),
  never raw API model slugs (`claude-sonnet-5`, `claude-fable-5`).
- Pie chart slices are project shares + Misc + Unused, summing to 100%, computed against the
  weekly cap % as described above — even when `p` is assumed (e.g. 100% for an already-closed
  historical week), state that assumption in the total-cost caption, not as a separate note.
- Title includes the date range (e.g. "Weekly Roundup — Sep 6-11, 2026"), matching the eyebrow.
- Fonts, color tokens, and section structure match section 4 exactly — no substituted fonts,
  invented color tokens, or reordered/renamed sections.

Re-read this checklist against the finished HTML immediately before publishing.

## 5. Add this week to the Roundup Archive

A separate artifact, **Roundup Archive** (`https://claude.ai/code/artifact/61e892af-ab44-48cb-9c9b-74ee690c6dad`,
`archive_url` in `state.json`), is a gallery of every week: a thumbnail donut per week that expands to the
full pie chart + legend on hover. It reads its own artifact database (`db` capability) at load, so adding
a week is a database write, not a republish of that page's HTML.

After publishing this week's roundup, write one document to the archive's `weeks` collection via `Artifact`
(`action: "write_db"`, `db_op: "set"`, `url: archive_url`, `collection: "weeks"`, `doc_id: "<window-start,
YYYY-MM-DD>"`), with this shape:

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

Omit the "Unused" slice entirely if `unused_pct` is 0. This is the only step that touches the archive —
never republish the archive's HTML file itself for a routine run; it only needs a new `db` document.

## 6. Update state

Write `state.json`: `{"last_run": "<today's date>", "last_artifact_url": "<published url>",
"archive_url": "https://claude.ai/code/artifact/61e892af-ab44-48cb-9c9b-74ee690c6dad",
"last_cap_usage_pct": <p>}`.

## Notes

- If zero repos had activity in the window, still publish a short artifact saying so rather
  than skipping — Jaxon should see confirmation the roundup ran.
- Keep total tool calls modest: this is a weekly job, not a deep audit. Don't read entire repos
  — commit logs, diffs of the significant commits, and README/screenshot lookups are enough.
