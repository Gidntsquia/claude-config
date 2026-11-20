# Spec: v1.3 release as pre-release v1.3.0-beta.1 — release docs, wiki, tag and GitHub pre-release, on one planner and one run-agent

## Ask
"Every part of the v1.3 plan in plans/PLAN.md has shipped (Parts A-D and the report loop). Plan the v1.3 release, requirement R21: CHANGELOG, RELEASE_NOTES, README feature lines, UPDATING.md 1.2.1 to 1.3, the wiki Workflow and Cheat Sheet pages, the tag and the GitHub release."
R21 in that plan (now `plans/archive/PLAN-2026-11-18-v1-3-agents-that-run-unsupervised.md`): "v1.3: CHANGELOG, RELEASE_NOTES, README feature lines, UPDATING.md 1.2.1 → 1.3, wiki Workflow and Cheat Sheet pages, tag and GitHub release, after Parts A–D each have an EVAL.md verdict ship. The release worker runs from this repo."
- Release notes lead: "Equal highlights, no lead"
- How the release is judged: "Update a 1.2.1 install", "Notes match the commits", "I read the pages myself", "CI green on the tag", "Use the style in the write-readme skill to write the release notes"
- Notes style reading: "Yes, layout kept, wording by the style"
- Uncommitted files: "We should remove all stale variants , and then we should commit everything. The assistant agent should be included in the release. For now, I want this to be a pre-release that we test in more detail before promoting to a full release"
- Variants: "We should fold whatever’s newest into the base. So option 3, and also option 2" [Fold fix10 into planner first; Also remove run-agent-dev]; reading confirmed: "Yes, both as read"
- Publish: "Pre-release first"
- Assistant: "Copy it all into this repo"
- run-agent MCP registration: "Both" [install.sh registers it, and UPDATING.md prints the command]
- Plan order: "Yes, lead with the release"

## What to build
"Every part of the v1.3 plan in plans/PLAN.md has shipped (Parts A-D and the report loop). Plan the v1.3 release, requirement R21: CHANGELOG, RELEASE_NOTES, README feature lines, UPDATING.md 1.2.1 to 1.3, the wiki Workflow and Cheat Sheet pages, the tag and the GitHub release.", "v1.3: CHANGELOG, RELEASE_NOTES, README feature lines, UPDATING.md 1.2.1 → 1.3, wiki Workflow and Cheat Sheet pages, tag and GitHub release": the release ships as "a pre-release that we test in more detail before promoting to a full release".

## Done when
1. `gh release view v1.3.0-beta.1` shows a pre-release whose body is RELEASE_NOTES.md, and its `install` run is green on all three systems (R1–R6, R16–R19).
2. A scratch clone at v1.2.1, updated by following UPDATING.md with the tag v1.3.0-beta.1, ends `./install.sh --check` with `all checks passed` (R9–R11, R22).
3. The user reads RELEASE_NOTES, the README features and the two wiki pages and finds every line true of the tagged tree (R3–R8, R12–R15).
4. `ls agents skills` at the tag shows one planner, one run-agent and a working assistant (R20–R24).

## Facts
Research ran after round 1, because round-2 options rested on the tree's state; tier repo, two researchers.
- Tree state, variants and uncommitted diffs: `plans/research/v1-3-release.md`, "Tree state".
- assistant.md is a symlink into `~/files/assistant-agent`, where its MCP server and guard hook live: same file, "Assistant".
- What install.sh does and does not do for a 1.2.1 user: same file, "Update path 1.2.1 to 1.3".
- Release pattern, CI trigger (`release: published` only), wiki clone and the four `Verdict: ship` lines: same file, "Releases, CI, wiki".
- write-readme style rules: same file, "Notes style".
- Stale lines by file and line number: same file, "Workflow page gaps", "Cheat Sheet gaps", "Other stale lines".
- Unverified: `--settings merge` adding hook entries under a user's existing `hooks` key — install.sh:107-262 was read but no merge was run; both outcomes built: requirement 11.
- Carried from the archived EVAL: R10 `bash skills/run-agent/scripts/test.sh` was still running when judged (11-14 run: 313 passed, 0 failed).

## Requirements
Parts from: "CHANGELOG, RELEASE_NOTES, README feature lines, UPDATING.md 1.2.1 to 1.3, the wiki Workflow and Cheat Sheet pages, the tag and the GitHub release"

A. CHANGELOG: serves done-check 1
1. (default) `## Unreleased` is empty; a new `## v1.3.0-beta.1 — <tag date>` section repeats RELEASE_NOTES one heading level down, as `## v1.2.1` does, then keeps today's Unreleased entries verbatim under `### Full log`.
2. (default) The usage-guard entry's "(install.sh users: add them from `hooks/usage-guard/README.md`)" is replaced by "install.sh installs it"; entries naming `run-agent-dev` or `promote.sh` gain "(folded into `skills/run-agent` and install.sh in this release)".

B. RELEASE_NOTES: serves done-checks 1 and 3
3. (user, "Equal highlights, no lead") `# v1.3.0-beta.1 — <tag date>`, then Highlights with one bullet each of equal length for: unsupervised agents, run-agent, usage-guard, report-writer, defer-artifact, assistant.
4. (user, "layout kept, wording by the style") Sections follow v1.2.1's layout (Highlights, per-area sections, Known issues, Agent versions); every sentence obeys `skills/write-readme/references/style.md`, with none of its banned phrasings.
5. (user, "Notes match the commits") `plans/RELEASE_TRACE.md` has one row per notes bullet: the bullet's first words, its CHANGELOG entry, a commit sha in `v1.2.1..v1.3.0-beta.1`. A bullet with no row is removed.
6. (default) Known issues says this is a pre-release under test; Agent versions lists each of the eight agent files with its last commit sha and date at the tag.

C. README feature lines: serves done-check 3
7. (default) Line 7's counts read eight agents and seven skills. Planner bullet names research by `researcher` subagents; worker bullet names never ending on a question, self-scheduling and the usage-limit handoff; evaluator bullet names hidden opens.
8. (default) New Features bullets, one each: assistant; usage-guard with the `guard` command; the three-line next step every agent ends with. The `/run-agent` bullet gains `clean`. README stays within 60–90 lines; `claude --agent assistant` joins the command block.

D. UPDATING.md 1.2.1 to 1.3: serves done-check 2
9. (user, "Both") Step 8 gains a `1.2.1 → 1.3` line: `claude update` to 2.1.296 or newer, `uv` installed, `./install.sh`, and the exact `claude mcp add --transport stdio --scope user run-agent -- …` command for when install.sh printed that `claude` was not on PATH.
10. (default) The same line says the pre-release is installed by setting `$TAG` to `v1.3.0-beta.1` by hand, because step 3 skips pre-releases, and gives the `--settings keep` step for `CLAUDE_CODE_PLUGIN_DIRS`.
11. (default) After `--settings merge` into a settings.json that already has a `hooks` key, `--check` passes every hook line. If merge already adds them: one test case in `test/` proves it; else: merge is changed to add each missing entry.

E. Wiki Workflow and Cheat Sheet: serves done-check 3
12. (default) Workflow's three "How it ends" parts and its opening quote the three next-step lines; the `/exit`-then-type text is replaced; command blocks gain `evaluator "phone"` and `/run-agent`.
13. (default) Workflow's planner section describes research through `researcher` and `plans/research/`; worker section describes `## Waiting`, the usage-limit handoff, usage-guard and blockers; evaluator section describes hidden opens, the ready question and the no-flash lines.
14. (default) Cheat Sheet's code block gains: `/run-agent` with a time phrase, `confirm`, `window`, a `+` group; `run-agent jobs|cancel|clean`; `guard status|allow 2h|usage`; `claude --agent assistant`; `evaluator "phone"`. The `/exit` tip names `/run-agent` as the handoff.
15. (default) Both pages follow the style file; `helper-mcp/stamp-wiki` is rerun; `git -C wiki push` leaves the wiki clone 0 ahead of its origin.

F. Tag and GitHub release: serves done-check 1
16. (user, "Pre-release first") Tag `v1.3.0-beta.1` (assumed, after `v1.1.0-beta.1`) on the commit holding groups A–D and G; main and the tag are pushed; `git status --porcelain` is empty.
17. (user) `gh release create v1.3.0-beta.1 --prerelease --title v1.3.0-beta.1 --notes-file RELEASE_NOTES.md`; v1.2.1 stays Latest; no `v1.3` or `v1.3.0` tag is made.
18. (user, "CI green on the tag") The `install` run the publish starts ends success on Ubuntu, macOS and Windows. On a failure the fix is committed and released the same way as `v1.3.0-beta.2`.
19. (carried) `bash skills/run-agent/scripts/test.sh` ends with 0 failed on the tagged commit.

G. What the tag contains: serves done-check 4
20. (user, "fold whatever’s newest into the base") Where planner.md and planner-fix10.md differ, the text with the later `git blame` date lands in planner.md, uncommitted lines counting as newest and planner-fix10 winning ties; `name`, description and run line stay `planner`.
21. (user) planner-fix10.md and planner-fix32.md are deleted; researcher.md's description names `planner`; no tracked file contains `planner-fix`.
22. (user, "also option 2") Each `skills/run-agent-dev` file with a later last commit than its `skills/run-agent` twin replaces it; then `skills/run-agent-dev` and `bin/run-agent-dev` are deleted. install.sh registers the run-agent MCP server and `--check` has a PASS/FAIL line for it.
23. (user, "Copy it all into this repo") `agents/assistant.md` is a regular file; its MCP server and guard hook are copied to `assistant/mcp/` and `assistant/hooks/` (assumed) with frontmatter paths that resolve from the clone; `phone-shot.sh` is in `wsl/local-tools/`.
24. (user) install.sh links assistant and `--check` has a line for it; in a fresh clone, `claude --agent assistant` lists its seven `mcp__assistant__*` tools.
25. (user, "commit everything") worker.md, evaluator.md, settings.json and the report-writer ledger are committed as they are, apart from the edits above.
also, built after the above: `agents/USAGE.txt` lists assistant and researcher and the `/run-agent` handoff; `wiki/Glossary-and-FAQ.md:52` names the schedule tool and `--handoff`.

## Constraints
Stack as the repo has it: markdown, bash (`install.sh`, `run-agent.sh`), Python 3 stdlib plus `uv run --script` for MCP servers, `gh`, git; the wiki is its own clone under `wiki/`. No new runtimes. Nothing under `plans/` is committed. No force-push; no tag is moved or deleted.

## Acceptance criteria
- [ ] Done 1 / R16–R18: `gh release view v1.3.0-beta.1 --json isPrerelease,body` is true with the notes text; `gh release list` shows v1.2.1 Latest; `gh run list` shows `install` success for the release.
- [ ] Done 2 / R9–R11, R22: in a scratch HOME, clone at v1.2.1, install, follow UPDATING.md with `$TAG=v1.3.0-beta.1`; `./install.sh --check` ends `all checks passed` and has run-agent MCP and assistant lines.
- [ ] Done 3 / R3–R8, R12–R15: the user reads RELEASE_NOTES.md, README Features, wiki Workflow and Cheat Sheet opened one at a time; a grep for the style file's banned phrasings over the four is empty.
- [ ] R5: every Highlights and section bullet has a row in `plans/RELEASE_TRACE.md` whose sha is in `git log v1.2.1..v1.3.0-beta.1`.
- [ ] R1–R2: `CHANGELOG.md` `## Unreleased` has no entries; `grep -c "add them from" CHANGELOG.md` is 0.
- [ ] Done 4 / R20–R25: `git ls-files | grep -c -e planner-fix -e run-agent-dev` is 0; `test -L agents/assistant.md` fails; `git status --porcelain` is empty.
- [ ] R19: `test.sh` tail shows 0 failed.
