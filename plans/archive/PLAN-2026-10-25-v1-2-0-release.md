# Spec: v1.2.0 release of claude-config, with the week's skill work leading the notes

## Ask
"Prepare this repo for another release in the standard way. I particularly want to highlight the new skills I've made over the last week."
Answers, verbatim:
- Version: "v1.2.0"
- Highlights: "write-report (new skill)", "run-agent scheduling + handoff", "restore-sessions rebuild"
- Scope: "Files + tag + GitHub release"
- Judging: "Every bullet traces to a commit", "Same shape as v1.1.0", "Tests pass at the tag", "gh release view matches"
- settings.json: "Commit it as part of the release"
- Sections: "Skills, Agents, Settings, Known issues, Agent versions"
- README: "Leave README alone"
- Tests: "No test line"
- Follow-up: "Make sure the description is written in my style -- see the /write-readme skill"
Previous plan (worker.md usage-limit section) shipped per the archived EVAL; nothing carried.

## What to build
Turn the `## Unreleased` section of `CHANGELOG.md` into `## v1.2.0 — 2026-10-24`, written in the v1.1.0 shape (Highlights ✨, then Skills 🧰, Agents, Settings, Known issues, Agent versions 📄), with the three skill items the user chose as the first Highlights. Copy that section's body into `RELEASE_NOTES.md`, bump `pyproject.toml` to 1.2.0, commit everything including the pending `settings.json` change, tag `v1.2.0`, push, and publish the GitHub release as Latest with `RELEASE_NOTES.md` as its body. README is not touched.

## Facts
- Last release: tag `v1.1.0` at 0175fa3 (2026-10-15); GitHub release "v1.1.0", Latest, not prerelease. Release commit pattern: one commit touching CHANGELOG.md + RELEASE_NOTES.md (`git show v1.1.0 --stat`).
- `RELEASE_NOTES.md` at v1.1.0 is the CHANGELOG section body with headings one level up (`## Highlights ✨` not `###`) and no `## vX — date` line.
- Commit range for this release: `v1.1.0..HEAD` = 0175fa3..8206204, 34 commits (`git log v1.1.0..HEAD --oneline`).
- Only new skill folder this week: `skills/write-report/` (added 19ecb18, 2026-10-23). `run-agent` gained scheduling/parsing (ceaafc5, e1c8df5), `--need-tmux` (d9543f3), `--handoff` (4f69387, e37d4cc, 093b600). `restore-sessions`: 86a8b9b, a5b96e4, d622a3b, cd4dd0f, 69fc785, 7017e49. `weekly-roundup`: 8299d8a, 53630c1.
- New agents: `report-writer.md` (5b63ec7, 3bd5401), `report-checker.md` (5b63ec7). Other agent changes: evaluator phone path and slim variant (261ebdc, b9e54b7, 7a8394b), helper git-init fix (e71da2a), planner Skill tool (19ecb18), worker usage-limit section (4f69387…8206204), `docs/agent-style.md` (8206204).
- Settings commits: d5e41ca (deny rules hide main-session agents), a34d662 (allow run-agent.sh Bash call). Pending uncommitted `settings.json` diff: `"model": "opus"` → `"sonnet"`, `autoContinueAtUsageLimit: false` moved from after `permissions` to after `theme` (value unchanged).
- Latest commit per agent file (`git log -1 -- agents/<f>`): planner 19ecb18 (2026-10-23), worker 8206204 (2026-10-24), evaluator 7a8394b (2026-10-23), helper e71da2a (2026-10-23), report-writer 3bd5401 (2026-10-23), report-checker 5b63ec7 (2026-10-23).
- Tests present: `bash skills/run-agent/scripts/test.sh` (142 passed at 8206204 per archived EVAL), `uv run pytest` in `skills/weekly-roundup/` (18 at v1.1.0), `bash agents/evals/report-writer/run.sh planted`.
- `pyproject.toml` line 3: `version = "1.1.0"`.

## Requirements
1. (user) `CHANGELOG.md`: the `## Unreleased` heading becomes `## v1.2.0 — 2026-10-24` and a fresh empty `## Unreleased` heading is not added. One intro sentence under it in the v1.1.0 style (what the release is, "Everything since v1.1.0 (2026-10-15) is here").
2. (user) Section order inside v1.2.0: `### Highlights ✨`, `### Skills 🧰`, `### Agents` (emoji: default 🤖), `### Settings` (default ⚙️), `### Known issues`, `### Agent versions 📄`.
3. (user) Highlights: the first three bullets are in this order: the write-report skill (`/write-report` plus the report-writer and report-checker agents, one sentence on what a report is); `/run-agent` scheduling and the worker's usage-limit handoff (`at 9pm` / `in 2h` / `after window`, loose phone typing, worker relaunches itself); the restore-sessions rebuild (one session per project, keeps models, every window, 60-min window, skips `/exit`). Each bullet opens with the skill name in plain text or backticks, no bold lead-in (write-readme: "Bullets don't need parallel structure or a bolded lead-in"). Default: no separate bullet for the report-writer/checker agents; they live inside the write-report highlight and the Agents section.
4. (default) `### Skills 🧰` has one plain bullet per skill touched since v1.1.0: write-report, run-agent, restore-sessions, weekly-roundup. Each bullet is built from the existing Unreleased bullets and the Facts commits; nothing from the Unreleased section is dropped, only moved and condensed. The run-agent bullet names `--parse`, `jobs`, `cancel`, `dry`, `--need-tmux`, `--handoff`; the weekly-roundup bullet names Sonnet 5.5 cache-read pricing and the Oct 11–18 archive week.
5. (default) `### Agents` has bullets for: report-writer (model Fable, what it produces, `plans/DATA_REQUEST.md` fallback), report-checker (model Opus, cold answer + findings, loops), worker (usage-limit handoff section, three-line note, WIP commit, `docs/agent-style.md`), evaluator (phone path `claude --agent evaluator "phone"`, window-control rules moved in, slim variant), helper (git-init fix for the MCP approval dialog), planner (has the Skill tool and calls for report-writer reports). Each is traceable to a commit in Facts.
6. (default) `### Settings` lists: default model Sonnet (the pending diff, committed here), `autoContinueAtUsageLimit: false` and why, deny rules hiding main-session-only agents from the Agent tool, the allowed `run-agent.sh` Bash call, plane status-line theme (`CLAUDE_STATUSLINE_THEME=plane`, `--preview`, `install.sh --theme plane`), `UPDATING.md` added.
7. (user) `### Known issues` contains no test-run line. It says `- None known.` unless R12 finds a failure, in which case that failure is named in one line.
8. (default) `### Agent versions 📄` lists all six agent files with the hash and date from Facts as `- planner.md at 19ecb18 (2026-10-23)` (the v1.1.0 shape with "at" in place of the em-dash, because the style allows em-dashes only in the README's Documentation list and the `## v1.2.0 — 2026-10-24` heading, which keeps the v1.1.0 form).
9. (default) Every bullet in the v1.2.0 section describes something present in `v1.1.0..HEAD` or the pending settings diff. Every feature in the existing Unreleased text is still named (internals may be cut per R17). No bullet claims a feature the diff does not contain.
10. (user) `RELEASE_NOTES.md` is overwritten with the v1.2.0 section body: headings promoted one level (`## Highlights ✨`), no version heading, text otherwise identical to the CHANGELOG section.
11. (default) `pyproject.toml` version becomes `1.2.0`; `uv.lock` is regenerated only if `uv lock` changes it.
12. (user, judging) Before committing, the worker runs `bash skills/run-agent/scripts/test.sh` and `uv run pytest` in `skills/weekly-roundup/`; both must pass (0 failed). Results go in the commit message body, not in the CHANGELOG.
13. (user) README.md, wiki/, docs/, agents/, skills/ are not modified.
14. (user) One release commit on `main` containing CHANGELOG.md, RELEASE_NOTES.md, pyproject.toml (and uv.lock if changed) and the pending `settings.json` change; message `Release v1.2.0` with a short body; attribution lines per the session's rules.
15. (user) Annotated tag `v1.2.0` on that commit, pushed with the commit (`git push origin main v1.2.0`).
16. (user) `gh release create v1.2.0 --title v1.2.0 --notes-file RELEASE_NOTES.md --latest` on `Gidntsquia/claude-config`; not a draft, not a prerelease.
17. (user) Voice: the notes (CHANGELOG section, RELEASE_NOTES.md, GitHub release body, commit body) follow `skills/write-readme/references/style.md`. The worker reads that file before writing. Rules that bind here: plain direct language, neutral register, contractions fine; each bullet says what the software does in one or two plain sentences, one idea per bullet; features are things a user notices, so parameters, thresholds and test counts go out (the old Unreleased bullets hold many; keep the user-visible behavior and drop the internals such as "129 checks", `check.py first_once`, axis_min detail); no "not X, but Y" or "X, not Y" contrasts; no "actually", "really", "exactly", "at all", "simply", "just" as emphasis; no colon taglines opening a bullet; no triads or arrows; no asides that perform personality; no closing reassurance clauses; no em-dashes in prose; code-block comments start with a capital letter; at most one `IMPORTANT:` line, only for a real gotcha. `docs/ai-tells.md` also applies. Where this conflicts with R4–R6 detail, the style wins and the term may be dropped from the bullet if it is an internal.
18. (default) The worker's final message gives the GitHub release URL and the RELEASE_NOTES.md path so the user can read the notes on a phone.

## Constraints
- Stack: this repo's existing tooling only (bash, git, gh, uv). No new dependencies.
- Dates in ET; 2026-10-24 is the release date.
- Edits only the files named in R14; all other files untouched (R13).
- `plans/` is gitignored and never committed.

## Acceptance criteria
- [ ] R1–R2: `grep -n '^## \|^### ' CHANGELOG.md | head -12` shows `## v1.2.0 — 2026-10-24` then the six `###` headings in order, with no `## Unreleased` above it.
- [ ] R3: the first three bullets under Highlights start with the three bolded phrases, in order.
- [ ] R4–R6: Skills has four bullets, Agents six, Settings six; each user-visible term from R4–R6 appears (`grep -c` per term ≥1).
- [ ] R7: Known issues section is `- None known.` or one named failure; `grep -ci 'passed\|tests' ` within that section is 0.
- [ ] R8: six `- <file>.md at <hash> (<date>)` lines matching `git log -1 --format=%h -- agents/<file>`.
- [ ] R9: every bullet of the old Unreleased text (`git show HEAD:CHANGELOG.md`) has its feature named in the new section (internals may be cut per R17); `diff <(git show HEAD:CHANGELOG.md | sed -n '/^## v1.1.0/,$p') <(sed -n '/^## v1.1.0/,$p' CHANGELOG.md)` is empty.
- [ ] R10: `diff <(sed -n '/^## v1.2.0/,/^## v1.1.0/p' CHANGELOG.md | sed '1d;$d' | sed 's/^###/##/') RELEASE_NOTES.md` is empty.
- [ ] R11: `grep '^version' pyproject.toml` → `1.2.0`.
- [ ] R12: commit body quotes `N passed, 0 failed` from test.sh and pytest's `N passed`.
- [ ] R13: `git show --stat v1.2.0` lists only CHANGELOG.md, RELEASE_NOTES.md, pyproject.toml, settings.json (and uv.lock if changed).
- [ ] R14–R15: `git tag -l v1.2.0` non-empty; `git ls-remote --tags origin v1.2.0` matches `git rev-parse v1.2.0^{}`; `git status` clean.
- [ ] R16: `gh release view v1.2.0 --json isDraft,isPrerelease,tagName,body` → false, false, v1.2.0, body equals RELEASE_NOTES.md; `gh release list` marks v1.2.0 Latest.
- [ ] R17: `sed -n '/^## v1.2.0/,/^## v1.1.0/p' CHANGELOG.md | sed 1d | grep -nE ' — |\*\*|actually|really|exactly|at all|simply|\bjust\b|nitty|spits'` finds nothing; read the section once against the rejected-sentence table in `style.md` and rewrite any match.
- [ ] R18: final message contains `https://github.com/Gidntsquia/claude-config/releases/tag/v1.2.0`.
