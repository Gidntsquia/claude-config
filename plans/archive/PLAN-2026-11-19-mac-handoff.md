# Spec: Mac handoff — everything the Mac needs to keep working on claude-config, on GitHub before this PC goes out of reach

## Ask
"I want to continue working on this repository, but I'm going on vacation and won't have access to this machine. Evaluate the state of this repo and configure a plan for setting things up where I can work on it from my Mac"
- Mac work: "Full planner/worker/evaluator rounds", "Mac-specific testing and fixes", "I'll promote to 1.3 on my Mac. I want to make sure my Mac has all the files it needs to do that"
- Files for the promotion: "Yes, text files only" [the 720 KB of plans text, the wiki's AI-Tells.md and the memory notes; the other 64 MB of eval logs and screenshots stay on this PC]
- Carry over: "Unpushed git odds and ends" [branch `pr2`, the wiki's unpublished AI-Tells.md, the ignored archive/ folder]
- Where: "Put it in the public repo in a branch. No one uses my claude config yet, so it won't cause any issues for any users"; reading confirmed: "Yes, one public side branch"
- Sibling folders: "Actually, leave those sibling folders out."; reading confirmed: "Yes, all siblings stay here"
- Mac state: "Not reachable until the trip"
- Proof: "Nothing left behind report", "Rehearsal here, checklist there"
- Carried from the 2026-11-18 eval (verdict ship), for the Mac: "Fine for now as the beta release. We will need a closer look when we do the full release"

## What to build
"I want to continue working on this repository, but I'm going on vacation and won't have access to this machine. Evaluate the state of this repo and configure a plan for setting things up where I can work on it from my Mac": one public side branch and a checklist, so that "my Mac has all the files it needs" for full rounds, Mac testing and the v1.3 promotion, with no trip back to this PC.

## Done when
1. `git ls-remote origin mac-handoff` shows the branch, and it holds the plans text, archive/, AI-Tells.md, the memory notes, MAC-SETUP.md and LEFT-BEHIND.md (R1–R6).
2. The user opens LEFT-BEHIND.md and sees every local-only item with a GitHub location or a "stays on this PC" reason; no row is blank (R7–R9).
3. `plans/mac-rehearsal.log` shows a scratch-home clone, built from GitHub alone by following MAC-SETUP.md, ending `all checks passed` and `315 passed, 0 failed`, with every handoff file in place (R10–R12).
4. On the Mac, the user follows MAC-SETUP.md top to bottom without needing anything from this PC (R13–R18).

## Facts
Research ran after round 1, because round-2 options rested on what exists only on this PC; tier repo, two researchers. Details: `plans/research/mac-handoff.md`.
- main is clean and pushed; every tag is on origin; `pr2` is contained in origin/main: "Repo state".
- The repo is public, so the branch is readable by anyone; the secret scan of plans/, archive/ and AI-Tells.md matched 0 files: "Repo state", "Local-only material inside the clone".
- The 720 KB plans text set and the 64 MB that stays: "Local-only material inside the clone".
- Memory is 4 files in a folder named after the clone's absolute path: "Home folder (~/.claude)".
- Home settings.json differs from the repo copy in `model`, `modelSettings` and 2 allow rules: same heading.
- Mac tools, install.sh macOS branches, no macOS CLAUDE.local.md: "What the Mac needs".
- Promotion open item, missing v1.3.0 tag, CI trigger: "Promotion to the full release".
- Sibling folder states: "Sibling folders".

## Requirements
Parts from: "Evaluate the state of this repo and configure a plan for setting things up where I can work on it from my Mac"

A. State of this repo, moved off the PC: serves done-check 1
1. (user, "one public side branch") A branch `mac-handoff` exists on origin with no shared history with main (assumed); main, its tags and `.gitignore` are unchanged, and the branch is never merged.
2. (user, "text files only") The branch holds `plans/` with EVAL_NOTES.md, WORKER_NOTES.md, RELEASE_TRACE.md, HANDOFF.md, NOTE-run-agent-watchdog.md, STATUS-v1-3-1386430343.md, research/ and archive/; no eval log, screenshot or eval folder.
3. (default) On the branch, `plans/PLAN.md` and `plans/EVAL.md` are copies of `archive/PLAN-2026-11-19-v1-3-release-as-pre-release.md` and `archive/EVAL-2026-11-19-v1-3-release-as-pre-release.md`, so the Mac planner carries over the v1.3 release; this handoff plan sits in `plans/archive/`.
4. (user, "Unpushed git odds and ends") The branch holds the ignored `archive/` folder as `archive/` and the wiki clone's untracked file as `wiki/AI-Tells.md`; the wiki repo itself gets no commit.
5. (user) The branch holds the 4 memory files under `memory/`.
6. (default) Before the push, each branch file is matched against the patterns in the research file's secret scan; a matching file is left off the branch and listed in LEFT-BEHIND.md with the reason "matched a secret pattern".

B. Nothing-left-behind report: serves done-check 2
7. (user, "Nothing left behind report") `LEFT-BEHIND.md`, on the branch and in `plans/`, has one row per local-only item named in the research file's "Repo state", "Local-only material inside the clone", "Sibling folders" and "Home folder" headings: item, size, and one status.
8. (default) Status reads `on GitHub: <branch or repo and path>` or `stays on this PC: <reason>`; reasons quote the user where one exists ("text files only", "all siblings stay here"), else read "not asked for". `pr2` reads `on GitHub: contained in origin/main`.
9. (user, "all siblings stay here") Nothing outside claude-config is pushed, committed or copied; each sibling row shows its count of commits not on a remote, and assistant-agent's row adds "no remote".

C. Rehearsal on this PC: serves done-check 3
10. (user, "Rehearsal here, checklist there") In a scratch home on this PC, a fresh clone from GitHub is set up by running MAC-SETUP.md's steps in order, skipping only steps marked "Mac only"; this PC's real `~/.claude` is not changed.
11. (default) `plans/mac-rehearsal.log` records each step's command and exit code, the last line of `./install.sh --check`, the test.sh summary line, and a listing showing each handoff file at its destination.
12. (default) A step that fails in rehearsal is fixed in MAC-SETUP.md and the rehearsal rerun from a new scratch home; a failure caused by tracked code is listed under "Known before you start" in MAC-SETUP.md with its error text, and tracked code stays unchanged.

D. Setting things up on the Mac: serves done-check 4
13. (default) `MAC-SETUP.md` on the branch is a numbered checklist of copy-paste commands, each followed by the line the user should see; it opens with how to read it before cloning: its GitHub URL on the `mac-handoff` branch.
14. (default) Step group "Tools": Homebrew installs of git, python, tmux, gh and uv, Claude Code 2.1.296 or newer, `gh auth login`; iTerm2 and the JetBrainsMono Nerd Font marked optional and "Mac only".
15. (default) Step group "Install": clone to `~/files/claude-config` (assumed), then `./install.sh --projects ~/files --terminal --default-profile --statusline squid --settings replace`, then `./install.sh --check` expecting `all checks passed`, then `bash skills/run-agent/scripts/test.sh` expecting `315 passed, 0 failed`.
16. (user, "all the files it needs") Step group "Handoff files": commands that fetch `mac-handoff` and copy `plans/` and `archive/` into the clone, clone the wiki into `wiki/` and add AI-Tells.md, and copy `memory/` into `~/.claude/projects/<clone path with every non-alphanumeric character replaced by "-">/memory/`.
17. (default) Step group "This PC's settings": the `model`, `modelSettings` and 2 extra allow rules from this PC's home settings.json, by value, with the command that adds them; and a `~/.claude/CLAUDE.local.md` holding the two macOS "open" lines from `wsl/CLAUDE.local.md`.
18. (user, "I'll promote to 1.3 on my Mac", "Mac-specific testing and fixes") A closing section "What is open" lists: the `touch` wording at RELEASE_NOTES.md:34 against style.md:26 with the user's quote; no v1.3.0 tag exists and UPDATING.md skips pre-releases; CI runs only on a published release; the Mac-only checks (iTerm2 profile, a scheduled run-agent job); and `claude --agent planner` as the next command.

## Constraints
- Stack: what the repo uses — bash, git, gh, python3; Markdown for both documents. No new dependency.
- main, tags, releases, the wiki repo and every folder outside claude-config are unchanged; `plans/` stays git-ignored on main.
- The branch is public: nothing from `~/.claude` beyond the memory files and the settings values in R17, no credentials, no session history.
- Clock times in US Eastern.

## Acceptance criteria
- [ ] Done 1 / R1–R5: `git ls-tree -r --name-only origin/mac-handoff` lists the named files and no eval output; `git merge-base main origin/mac-handoff` prints nothing; `git status` on main is clean outside plans/.
- [ ] R6: the secret-pattern grep over a checkout of the branch prints 0 files.
- [ ] Done 2 / R7–R9: every item in the four research headings has a row in LEFT-BEHIND.md with a non-empty status; sibling folders show the same unpushed counts as before.
- [ ] Done 3 / R10–R12: `plans/mac-rehearsal.log` ends with `all checks passed`, `315 passed, 0 failed` and the destination listing; the real `~/.claude/claude-config.json` is unmodified.
- [ ] Done 4 / R13–R18: MAC-SETUP.md opens from its GitHub URL in a browser; each step has a command and an expected line; "What is open" carries the five items.
