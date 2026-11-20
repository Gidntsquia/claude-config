# Left behind: every local-only item on the PC, and where it is now

Written 2026-11-19, about 11 PM ET. Each row is something that existed only on the Windows PC (WSL) when the Mac handoff was made. The status says where it is on GitHub, or why it stays on the PC. Quoted reasons are your own words from the planning session; "not asked for" means nobody asked to carry it.

Setup steps for the Mac: [MAC-SETUP.md](https://github.com/Gidntsquia/claude-config/blob/mac-handoff/MAC-SETUP.md).

## Repo state

| Item | Size | Status |
|---|---|---|
| `main` at 659e035 (it was 44b2598 when the handoff started; another session pushed 2 commits at 10:41 and 10:49 PM ET) | 413 tracked files | on GitHub: Gidntsquia/claude-config, branch `main` (local and origin are the same commit) |
| 10 local tags (pre-trim-2026-10-08, v1.2.1, v1.3.0-beta.1 to beta.4 among them) | 10 tags | on GitHub: Gidntsquia/claude-config, all 10 tags are on origin |
| Branch `pr2` (0b2cdaa) | 1 branch | on GitHub: contained in origin/main |
| Stashes, extra worktrees | none exist | stays on this PC: nothing to carry |
| Install workflow run 44362499305 (v1.3.0-beta.4, green on ubuntu, macos, windows) | 1 run | on GitHub: Gidntsquia/claude-config, Actions tab |

## Local-only material inside the clone

| Item | Size | Status |
|---|---|---|
| `plans/` text for the next round: EVAL_NOTES.md, WORKER_NOTES.md, RELEASE_TRACE.md, HANDOFF.md, NOTE-run-agent-watchdog.md, STATUS-v1-3-1386430343.md | 6 files | on GitHub: branch `mac-handoff`, `plans/` |
| `plans/research/` (mac-handoff.md, v1-3-release.md) | 2 files | on GitHub: branch `mac-handoff`, `plans/research/` |
| `plans/archive/` (old plans, evaluations and notes) | 78 files | on GitHub: branch `mac-handoff`, `plans/archive/` |
| `plans/PLAN.md` (this Mac handoff plan) | 1 file | on GitHub: branch `mac-handoff`, `plans/archive/PLAN-2026-11-19-mac-handoff.md` |
| The v1.3 pre-release plan and its evaluation | 2 files | on GitHub: branch `mac-handoff`, `plans/PLAN.md` and `plans/EVAL.md` (copies of the two `2026-11-19-v1-3-release-as-pre-release` files in `plans/archive/`) |
| `plans/` eval output: `phone/` 17 MB, `eval_r37_view/` 10 MB, `eval_r38_view/` 9.1 MB, `eval_r24/` 7.2 MB, `eval_r24b/` 7.1 MB, `eval_r40_view/`, `eval_r39_view/`, `eval_r36_view/` about 3 MB each, the other `eval_*` folders, logs and scripts, and 4 loose notes (eval-r42-worker-1udi.md, eval_r47_relbody.md, eval_r54_resume_2187618452.md, run-agent-scheduled-job-silent-failure.md) | 64 MB | stays on this PC: "text files only" (the eval logs and screenshots were named as the part that stays) |
| `plans/mac-rehearsal.log` (the rehearsal of MAC-SETUP.md) | 1 file | stays on this PC: not asked for (its result is quoted in MAC-SETUP.md) |
| `archive/` (old prompt versions and README.txt) | 48 KB, 6 files | on GitHub: branch `mac-handoff`, `archive/` |
| `wiki/` clone of Gidntsquia/claude-config.wiki.git | even with origin/master | on GitHub: Gidntsquia/claude-config.wiki, branch `master` |
| `wiki/AI-Tells.md` (untracked in the wiki clone, never published) | 8 KB | on GitHub: branch `mac-handoff`, `wiki/AI-Tells.md` (the wiki repo got no commit) |
| `.claude/settings.local.json` (only `permissions.allow`) | 93 bytes | stays on this PC: not asked for (Claude Code rebuilds it as you approve commands) |
| Files matched by the secret scan | 0 files | stays on this PC: nothing matched, so nothing was held back |

## Sibling folders

| Item | Size | Status |
|---|---|---|
| `~/files/agent-eval-experiment` (remote Gidntsquia/agent-eval-experiment) | 4.1 GB; 16 commits not on a remote; 1 modified and 11 untracked files | stays on this PC: "all siblings stay here" |
| `~/files/assistant-agent` | 34 MB; 77 commits not on a remote | stays on this PC: "all siblings stay here"; no remote (its files were copied into `assistant/` on `main` for v1.3) |
| `~/files/ai-sandbox` | 40 MB; git repo with 0 commits, so 0 commits not on a remote; no remote | stays on this PC: "all siblings stay here" |
| `~/files/base-context-cleanup` | 77 MB; 6 commits not on a remote; no remote | stays on this PC: "all siblings stay here" |
| `~/files/curling_simulator` | 177 MB; 20 commits not on a remote; no remote | stays on this PC: "all siblings stay here" |
| `~/files/slay-the-spire-advisor` | 22 GB; not a git repo, so 0 commits | stays on this PC: "all siblings stay here" |
| `~/files/token-experiment` | 2.8 GB; not a git repo, so 0 commits | stays on this PC: "all siblings stay here" |

## Home folder (~/.claude)

| Item | Size | Status |
|---|---|---|
| Memory notes for this project (MEMORY.md and 3 notes) | 4 files, 2,791 bytes | on GitHub: branch `mac-handoff`, `memory/` |
| `settings.json`: `model`, `modelSettings` and the 2 extra allow rules | 3 values | on GitHub: branch `mac-handoff`, MAC-SETUP.md step 13 (written out by value) |
| `settings.json`: everything else (same keys as the repo copy; `env` adds CLAUDE_CODE_PLUGIN_DIRS) | 12 KB | on GitHub: Gidntsquia/claude-config, `settings.json` on `main` (install.sh sets CLAUDE_CODE_PLUGIN_DIRS on the Mac) |
| `claude-config.json` (install choices: projects, terminal, default profile, statusline squid, settings replace) | 4 KB | on GitHub: branch `mac-handoff`, MAC-SETUP.md step 7 (the same choices as install flags; the Mac writes its own file) |
| `~/.claude.json` user-scope `run-agent` MCP server | 1 entry | stays on this PC: not asked for (install.sh registers it on the Mac, step 7) |
| `CLAUDE.local.md` (the WSL version) | 1 file | on GitHub: Gidntsquia/claude-config, `wsl/CLAUDE.local.md` on `main`; the Mac version is MAC-SETUP.md step 14 |
| `agent-archive/` | 80 KB | stays on this PC: not asked for |
| `feedback` | 4 KB | stays on this PC: not asked for |
| `jobs/` | 8 KB | stays on this PC: not asked for |
| `pre-migration-backup-20260828-184708/` | 20 KB | stays on this PC: not asked for |
| `run-agent/` (job state and logs; no job is waiting) | 476 KB | stays on this PC: not asked for (per machine; the Mac makes its own) |
| `skills-archive/` | 56 KB | stays on this PC: not asked for |
| `ssh/` | 4 KB | stays on this PC: not asked for (nothing from `~/.claude` beyond memory and the step 13 values goes on a public branch) |
| `state/` | 8 KB | stays on this PC: not asked for |
| `skills/synced/` | 4.8 MB | stays on this PC: not asked for |
| `skills/.test-speedup-backup-2026-08-26/` | 44 KB | stays on this PC: not asked for |
| `local-tools/evshow.state` | 412 MB | stays on this PC: not asked for |
| Claude Code's own runtime state: `history.jsonl` 1.8 MB, `projects/` 6.8 GB, `sessions/` 500 KB | 6.8 GB | stays on this PC: not asked for (session history is kept off the public branch) |
| Usage-guard state (`~/.cache/claude-guard/`) | per machine | stays on this PC: not asked for (made on first use; nothing to copy) |
