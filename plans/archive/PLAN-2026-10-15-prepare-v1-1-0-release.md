# Spec: Prepare claude-config for the v1.1.0 full release of all four agents

## Ask
"I want to make a new full release with the current versions of all the agents. Help me prepare the repo for that"

Round 1: version = "v1.1.0"; repo changes = "README: four agents", "CHANGELOG.md", "Release notes draft file", "pyproject.toml version", "We need to add support for base Windows runs (my brother uses base Windows and not WSL--he made a fix on his end with Claude, but he wasn't able to push the change or even make a pull request. I want to add him [dotcomstar] as a contributor to this repository so he can make changes to it in the future)"; notes content = "Per-agent sections like the beta", "Skills section", "Settings and context-trim section", "Highlight the biggest changes of this release: Helper agent added, /run-agent added, and overall improvements to Helper / Worker / Evaluator"; right result = "Clean-clone install passes", "Skill tests pass", "Notes match the diff", "Release page looks right".
Round 2: PR #2 = "Merge all of it"; Windows = "Only the PR #2 fixes"; collaborator = "Full admin rights. Everything"; stop point = "Tag and draft release".

## What to build
Bring the repo to a state where v1.1.0 can be published as the Latest (non-pre-release) GitHub release of claude-config: merge dotcomstar's PR #2 (weekly-roundup Windows fixes plus his Oct 4-11 usage), invite dotcomstar as an admin collaborator, fix the README so it describes four agents, add a CHANGELOG.md and a release-notes draft, set the pyproject version, verify a clean-clone install and the skill tests, then push the `v1.1.0` tag and create the GitHub release as a draft from the notes file. The user presses Publish.

## Facts
- Verified (`git tag`, `gh release list`): tags `v1.0.0` (release, Latest, 2026-10-09), `v1.1.0-beta.1` (pre-release, 2026-10-12, at b19fa96), `pre-trim-2026-10-08`. HEAD 05994d9 is 13 commits past the beta, 41 past v1.0.0.
- Verified (`gh release view v1.1.0-beta.1`): the beta notes have a lead paragraph, 4 summary bullets, sections Helper 🧭 / Worker 🔧 / Evaluator ⚡ / Planner 📝, and "Agent versions 📄" (`planner.md — 2edf13f (2026-10-08)` etc.).
- Verified (`gh api .../pulls`, `gh pr view 2`): PR #2 "weekly-roundup: Windows fixes; add Jet's usage to Oct 4-11" by dotcomstar (Jet Lee), open, head `dotcomstar:roundup-jet-oct4`, one commit 0b2cdaa, files: `skills/weekly-roundup/{archive_weeks.json,build_archive.py,embed_pool.py,gather_data.py,state.json}`. Body says 8 tests pass and `test_shared_project_keeps_other_machine` fails on unmodified main too. Mergeable state was UNKNOWN at check time (not yet computed).
- Verified (`gh api .../collaborators`): only Gidntsquia today; dotcomstar's fork `dotcomstar/claude-config` is 10 behind main, 0 ahead on its `main`.
- Verified: README.md says "three agents" (intro) and its Quickstart lists planner/worker/evaluator only; wiki pages already say four agents and `claude --agent helper`. `pyproject.toml` line 3: `version = "0"`. No CHANGELOG, no RELEASE_NOTES, no `.github/`.
- Verified: `install.sh` handles macOS (`uname` Darwin) and WSL (`/proc/version`); no plain-Windows branch. Per the user, no installer change this release.
- Verified: `skills/run-agent/scripts/test.sh` exists (24 passed last eval); weekly-roundup tests run with `uv run pytest` (`skills/weekly-roundup/tests/`).
- Unverified: GitHub's collaborator API accepts `permission=admin` for a personal repo (`PUT /repos/{owner}/{repo}/collaborators/{username}` with `{"permission":"admin"}`); the invite must be accepted by dotcomstar.

## Requirements
1. (user) PR #2 is merged into main in full (code and data files), keeping dotcomstar as the commit author (merge or rebase, not a squash under another author). If it does not merge cleanly, the conflicts are resolved in favor of his Windows fixes and the pooled Oct 4-11 data; the notes credit him.
2. (user) dotcomstar is invited as a collaborator with admin permission. `gh api repos/Gidntsquia/claude-config/collaborators/dotcomstar` (or `/invitations`) shows the pending invitation with permission `admin`. The final message tells the user that Jet must accept the emailed invite.
3. (user) README.md: the intro says four agents; the Quickstart block adds `claude --agent helper      # Guides a beginner through the three agents above` (wording in that spirit); Features gets one helper bullet (asks where you are, answers only from agent files, wiki and docs). The Quickstart's "IMPORTANT" note, `/run-agent` paragraph and `/restore-sessions` bullet stay. (default) README says nothing new about plain Windows except, in the weekly-roundup bullet, that it runs on Windows too.
4. (user) `CHANGELOG.md` at the repo root, newest first: `## v1.1.0 — 2026-10-15`, `## v1.1.0-beta.1 — 2026-10-12`, `## v1.0.0 — 2026-10-09`. The two older entries carry their published release bodies' content (reworded freely, same facts); v1.1.0 carries the same content as the notes draft. Each entry uses the beta's per-agent headings where they apply.
5. (user) `RELEASE_NOTES.md` at the repo root is the exact body for the v1.1.0 release, in this order: one lead paragraph; a "Highlights" list naming the three biggest changes in the user's words: Helper agent added, /run-agent added, overall improvements to Helper / Worker / Evaluator; sections Helper 🧭, Worker 🔧, Evaluator ⚡, Planner 📝 with 1-3 plain-English user-facing bullets each covering v1.0.0..v1.1.0; a Skills section (run-agent: `/run-agent <agent>` swaps the tmux pane, `in <dir>`, force words, session naming; restore-sessions; weekly-roundup: usage-by-day chart, per-person palettes, cross-machine pooling, Windows fixes by @dotcomstar); a Settings and context trimming section (default model sonnet, dangerous-mode prompt skipped, Workflow deny, skillOverrides, claude.ai MCP off, `pre-trim-2026-10-08` as the way back); "Agent versions 📄" with `<agent>.md — <short hash> (<date>)` for planner, worker, evaluator, helper taken from `git log -1 -- agents/<agent>.md` at the tagged commit; the same trailing "🤖 Generated with Claude Code" line the beta used. (default) The file ends with no session link.
6. (user) Notes match the diff: every bullet in RELEASE_NOTES.md corresponds to at least one commit in `git log v1.0.0..v1.1.0`; every commit in that range that changes `agents/`, `skills/`, `settings.json`, `install.sh` or `README.md` is covered by some bullet (several commits per bullet is fine). WORKER_NOTES.md lists the bullet→commit mapping.
7. (user) `pyproject.toml` `version = "1.1.0"`; `uv lock` still succeeds (uv.lock updated if it changes).
8. (user) Clean-clone install: `git clone <repo> <tmp>` and `HOME=<tmp-home> ./install.sh` in a fresh temp HOME on this WSL box exits 0 and leaves `<tmp-home>/.claude/{agents,CLAUDE.md,settings.json,statusline.sh,skills/*}` as symlinks; `ls <tmp-home>/.claude/agents` shows planner.md, worker.md, evaluator.md, helper.md. The WSL branch may be short-circuited for the temp HOME if it would touch Windows Terminal settings; say so in WORKER_NOTES.md. The real `~/.claude` is not touched.
9. (user) Tests at the tagged commit: `skills/run-agent/scripts/test.sh` prints `N passed, 0 failed`; `uv run pytest skills/weekly-roundup/tests` runs and its result is recorded. The known failure `test_shared_project_keeps_other_machine` (fails on main before PR #2 per its body) is either fixed in this release or listed under "Known issues" in RELEASE_NOTES.md and CHANGELOG.md; (default) list it, do not fix it unless the fix is a one-line double count.
10. (user) All of the above is committed on main and pushed. Then the annotated tag `v1.1.0` is created on the final commit (message `v1.1.0`) and pushed, and `gh release create v1.1.0 --draft --title v1.1.0 --notes-file RELEASE_NOTES.md` creates a draft release (not pre-release). `gh release view v1.1.0` shows Draft; `v1.1.0-beta.1` stays listed as pre-release; `v1.0.0` stays Latest until the user publishes.
11. (default) Nothing in `plans/`, `archive/`, `wiki/`, `CLAUDE.local.md` or any credential/session file is committed (`.gitignore` already excludes them); `git status` is clean after the tag.
12. (default) The final message gives: the draft release URL, the one command/click to publish, the collaborator invite status, and the pytest result.

## Constraints
- Stack as in the repo: bash (`set -euo pipefail`), Markdown, `gh` CLI, Python managed by uv. No new dependencies, no `.github/` workflows, no installer change for plain Windows this release.
- Commits end with the attribution lines the session provides. Keep dotcomstar's authorship on his commit.
- Never force-push, never move or delete existing tags or releases, never publish (non-draft) the release.

## Acceptance criteria
- [ ] R1: `gh pr view 2 --json state,mergedAt` shows MERGED; `git log --format=%an -1 -- skills/weekly-roundup/embed_pool.py` on main names dotcomstar/Jet Lee.
- [ ] R2: `gh api repos/Gidntsquia/claude-config/invitations --jq '.[]|.invitee.login+" "+.permissions'` prints `dotcomstar admin` (or collaborators list shows him with admin if already accepted).
- [ ] R3: `grep -c "claude --agent helper" README.md` ≥ 1; `grep -n "three agents" README.md` prints nothing.
- [ ] R4: `grep -n "^## v" CHANGELOG.md` prints v1.1.0, v1.1.0-beta.1, v1.0.0 in that order.
- [ ] R5: RELEASE_NOTES.md contains, in order, "Highlights", "Helper", "Worker", "Evaluator", "Planner", "Skills", "Settings", "Agent versions"; each agent-versions line's hash equals `git log -1 --format=%h v1.1.0 -- agents/<name>.md`.
- [ ] R6: WORKER_NOTES.md has the bullet→commit table; spot-check three commits from `git log --oneline v1.0.0..v1.1.0 -- agents skills settings.json` each appear in it.
- [ ] R7: `grep version pyproject.toml` prints `version = "1.1.0"`; `uv lock --check` (or `uv lock` with no diff) succeeds.
- [ ] R8: the clean-clone install transcript in WORKER_NOTES.md shows exit 0 and the four agent symlinks.
- [ ] R9: `bash skills/run-agent/scripts/test.sh` ends `... 0 failed`; pytest output recorded; known failure listed under Known issues or fixed.
- [ ] R10: `git tag -l v1.1.0` prints the tag; `git ls-remote --tags origin v1.1.0` finds it; `gh release view v1.1.0 --json isDraft,isPrerelease` prints `true,false`; `gh release list` still shows v1.0.0 as Latest and the beta as Pre-release.
- [ ] R11: `git status --porcelain` is empty; `git ls-files plans archive wiki CLAUDE.local.md` prints nothing (except `examples/first-project/plans/`).
- [ ] R12: the worker's final message contains the draft URL and the publish command.

## Amendments
- 2026-10-15 "The "overall improvements" section shouldn't say the helper-- we just introduced the helper, so we didn't make improvements to it in this release. I thought we had improved the planner a little bit in this release"
  - [ ] The release notes' "overall improvements" highlight (RELEASE_NOTES.md and the v1.1.0 draft release page) names Worker, Evaluator and Planner, and does not call Helper improved; Helper appears only as newly added. (user)
    Replaces: Ask round 1 "overall improvements to Helper / Worker / Evaluator"
- 2026-10-15 "Write access is enough for dotcomstar at this time"
  - [ ] dotcomstar is a collaborator (or has a pending invitation) with write (push) permission; `gh api repos/Gidntsquia/claude-config/collaborators --jq '.[]|.login+" "+.role_name'` prints `dotcomstar write`.
    Replaces: R2 (admin) and Ask round 2 collaborator = "Full admin rights. Everything"
- 2026-10-15 "Works, ready to ship. I want the worker to publish"
  - [ ] The v1.1.0 release is published: `gh release view v1.1.0 --json isDraft,isPrerelease` prints `false,false`, and `gh release list` shows v1.1.0 as Latest (beta still Pre-release).
    Replaces: R10 draft half and Ask round 2 stop point "Tag and draft release"
