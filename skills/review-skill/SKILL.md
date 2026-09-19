---
name: review-skill
description: Six-pass audit of a skill (SKILL.md): correctness (does it achieve its stated goal), edge cases, error handling, best practices, token usage efficiency, and concision. Use when asked to review, audit, or harden a SKILL.md before trusting it to run unattended. Not for hooks, cron scripts, other tooling, or a git diff — use /code-review for the latter.
argument-hint: <skill name or path to SKILL.md>
---

# Review — six-pass audit for self-authored skills

Scope: skills only — say so if asked about hooks, cron scripts, config, or app code; point git-diff requests to `/code-review`.

Resolve `$ARGUMENTS` to a SKILL.md path before reading anything: if empty, ask which skill; if it contains a `/`, treat it as a path — use it directly if it ends in `SKILL.md`, else look for `SKILL.md` inside it as a directory; if neither exists, say so and ask for the right one. Otherwise treat it as a name — including plugin-qualified (`plugin:skill`) or directory-scoped (`path:skill`) forms — and resolve it by globbing for `SKILL.md` under `~/.claude/skills/`, any `.claude/skills/` directory at any depth in the project, and (for `plugin:skill`) that plugin's skills directory, matching on containing-directory name or frontmatter `name:`; the skill listing already in context can confirm a name is valid but carries no path, so it never substitutes for globbing. Infer silently on one match; ask only on zero or multiple matches, including when the relevant plugin directory can't be found. Read the file in full, surfacing any read failure instead of retrying silently; if it has no frontmatter or opening paragraph, flag that under Pass 4 and skip Pass 1's goal-trace. Then run these six passes in order:

## Pass 1 — Correctness
Trace whether following the instructions literally achieves the skill's stated goal (frontmatter `description` + opening paragraph). Flag: steps that don't advance the goal, missing steps, wrong ordering, unstated assumptions about state or environment, and any dependency — script, `references/*.md`, template — that doesn't exist in the skill's directory (check existence only; no need to read the dependency's full contents).

## Pass 2 — Edge cases
Check for unhandled boundary/unusual-state conditions: empty or missing input, zero or many matches where one is assumed, stale or partial data, concurrent or repeated invocation, malformed arguments. Flag conditions that can't actually trigger, or that trigger too broadly or narrowly.

## Pass 3 — Error handling
For each external call or action, check the failure path: missing file, denied permission, tool error, empty result, timeout, or (quick check only) a nonexistent tool field/flag/env var. It should surface the failure or ask the user, not guess silently. Any irreversible or broad-blast-radius action needs an explicit confirmation step.

## Pass 4 — Best practices
Check authoring conventions: frontmatter `name`/`description` are accurate and specific enough to trigger correctly without over-triggering; `argument-hint` is present if the skill takes arguments; scope is a single responsibility not duplicated by another installed skill or command. Flag instructions a fresh agent (no memory of this conversation) could reasonably misread.

## Pass 5 — Token usage efficiency
Flag anything that burns context needlessly at runtime: full-file reads or broad searches where targeted ones would do, subagent or parallel fan-out for work one pass could handle, dumping raw tool output instead of summarizing it, or re-fetching the same data twice.

## Pass 6 — Concision
Treat every word as guilty until proven necessary. Delete: anything a competent agent would already infer, restated obviousness, hedge words, filler transitions, throat-clearing, and extra examples once one disambiguates. For every sentence that survives, ask "what breaks if this is shorter?" — if nothing breaks, cut it further; prefer fragments and colon-separated lists over full sentences. Do this for every line, not just the obviously bloated ones. Report exact before/after word and line counts. Getting the "after" number means actually drafting the tightened version in scratch — don't estimate it. That scratch draft is working material, not output: report only the counts and the specific cuts, never the full rewritten file.

## Output

Report findings as a numbered list, most severe first, tagged with pass (1–6) and file:line. **Wait for approval before editing** — this skill reports, it doesn't auto-fix.
