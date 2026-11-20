# Spec: 1-hour prompt cache everywhere (report-writer, report-checker, all sessions), then the v1.2.0 release

## Ask
"Update the plan to have this beforehand: I want to make the report writer subagent always use a 1 hr cache instead of a 5 minute one, and the same thing for the report-checker. I never want the 5 minute cache used for any reason anywhere"
Answers, verbatim:
- Where set: "settings.json, both buckets", "Frontmatter on report-writer and report-checker", "ENABLE_PROMPT_CACHING_1H=1 in settings env"
- Proof: "Main session: `claude -p` JSON", "Subagent: transcript check", "Test only, no live run"
- Commit: "Own commit before the release commit"
- Helper text: "Update helper.md too"
The v1.2.0 release ask and answers are carried over unchanged from `plans/archive/PLAN-2026-10-25-v1-2-0-release.md` (release: "Prepare this repo for another release in the standard way. I particularly want to highlight the new skills I've made over the last week."; version v1.2.0; highlights write-report, run-agent scheduling + handoff, restore-sessions rebuild; files + tag + GitHub release; sections Skills, Agents, Settings, Known issues, Agent versions; README alone; no test line; notes in the write-readme style).

## What to build
Two commits on `main`. First, a cache commit: `settings.json` gets `promptCacheTtl: "1h"`, `subagentPromptCacheTtl: "1h"` and `env.ENABLE_PROMPT_CACHING_1H: "1"`; `agents/report-writer.md` and `agents/report-checker.md` get `experimental: {cacheTtl: 1h}` in their frontmatter; `agents/helper.md` line 75 says the cache lasts about an hour in this setup; a static check proves the keys are there, and two live checks (`claude -p` JSON, and the planted eval's subagent transcripts) show every cache write as `ephemeral_1h_input_tokens` and never `ephemeral_5m_input_tokens`. Second, the v1.2.0 release exactly as the archived plan describes, with the cache change added to the notes.

## Facts
- Claude Code here is 2.1.310 (`claude --version`); the TTL settings need ≥2.1.242, frontmatter `cacheTtl` ≥2.1.248. Verified at https://code.claude.com/docs/en/prompt-caching and /en/sub-agents on 2026-10-25.
- TTL is chosen per request bucket. Main conversation: `promptCacheTtl` setting or `CLAUDE_CODE_PROMPT_CACHE_TTL`. Everything else (subagents, forks, compaction, titles): `subagentPromptCacheTtl` or `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL`. Values `5m`/`1h`; anything else ignored. Defaults: subscription within plan usage → main 1h, everything else 5m; on usage credits, API key or cloud → 5m for both.
- Precedence, first match wins: `FORCE_PROMPT_CACHING_5M=1` → bucket env var → bucket setting → subagent frontmatter `experimental.cacheTtl` (its `1h` is ignored while a subscription is on usage credits) → `ENABLE_PROMPT_CACHING_1H=1` → bucket default. So the two settings are what make "never 5m" hold on usage credits; the frontmatter and env var are redundancy.
- Frontmatter shape: `experimental:\n  cacheTtl: 1h` (a map, not top-level `cacheTtl`).
- Proof fields: `claude -p "hello" --output-format json` → `usage.cache_creation.ephemeral_1h_input_tokens` / `ephemeral_5m_input_tokens`. Subagent transcripts: `~/.claude/projects/<project>/<session>/subagents/agent-*.jsonl`, assistant events carry `message.usage.cache_creation` with the same two fields (`agents/report-writer/checker_usage.py` already reads these files).
- `settings.json` currently has an `env` block (`ENABLE_CLAUDEAI_MCP_SERVERS`), `model: "claude-fable-5-1"` (uncommitted change from `opus`), and no cache keys. The release plan's Settings facts said the pending diff was `opus → sonnet`; the working tree now says `claude-fable-5-1`; the release notes name whatever is committed.
- `agents/helper.md:75` reads "(about an hour on a subscription, 5 minutes on an API key)".
- `bash agents/evals/report-writer/run.sh planted <fixture>` runs the report-checker through the harness in `~/files/agent-eval-experiment/report-writer/` (fixtures there); it spawns the checker as a subagent, so its transcript lands under `subagents/`.
- Everything in the archived plan's Facts (commit ranges, agent hashes, tests, v1.1.0 shape) still holds; agent hashes for report-writer, report-checker and helper will change after the cache commit and must be re-read with `git log -1 --format=%h -- agents/<f>`.

## Requirements
Cache change (commit 1):
1. (user) `settings.json` top level gains `"promptCacheTtl": "1h"` and `"subagentPromptCacheTtl": "1h"`; `env` gains `"ENABLE_PROMPT_CACHING_1H": "1"`. No other key changes except the already-pending `model` value, which is committed as is. File stays valid JSON with the existing 2-space style.
2. (user) `agents/report-writer.md` and `agents/report-checker.md` frontmatter each gain
   `experimental:` / `  cacheTtl: 1h` (two lines, map form), placed after `color:`. Nothing else in either file changes.
3. (user) `agents/helper.md` line 75: the parenthetical becomes words meaning the cache stays warm about an hour here because `settings.json` asks for the one-hour cache on every request, and the API's five-minute default is turned off. One sentence, plain, in the file's existing voice; nothing else in helper.md changes. `wiki/` is a separate repo and is not touched (default).
4. (user) Static check: a script `skills/run-agent/scripts/`-style is not added; instead the worker runs and records in the commit body: `jq -r '.promptCacheTtl, .subagentPromptCacheTtl, .env.ENABLE_PROMPT_CACHING_1H' settings.json` → `1h`, `1h`, `1`; and `grep -A1 '^experimental:' agents/report-writer.md agents/report-checker.md` → `cacheTtl: 1h` in both. (default: inline commands, no new test file, because the release notes carry no test line and `test.sh` covers run-agent only.)
5. (user) Live check, main bucket: after the settings edit, `claude -p "hello" --output-format json` from this repo; `usage.cache_creation.ephemeral_5m_input_tokens` is 0 and `ephemeral_1h_input_tokens` > 0. Result quoted in the commit body.
6. (user) Live check, subagent bucket: `bash agents/evals/report-writer/run.sh planted <fixture>` (default fixture: the one the archived EVALs used, listed by `ls ~/files/agent-eval-experiment/report-writer/fixtures`), then for every `subagents/agent-*.jsonl` modified since the run started, every assistant event's `message.usage.cache_creation.ephemeral_5m_input_tokens` is 0. Report the count of events checked and the sum of `ephemeral_1h_input_tokens` in the commit body. If no `cache_creation` object appears at all, say so and treat it as a failure to investigate, not a pass.
7. (default) If check 5 or 6 shows any `ephemeral_5m` write, the worker does not commit; it checks for `FORCE_PROMPT_CACHING_5M` or `CLAUDE_CODE_*_PROMPT_CACHE_TTL` in the environment and `~/.claude/settings.local.json`, fixes what is in this repo, and reruns. If the cause is outside the repo (shell env, managed settings), it names it in `plans/WORKER_NOTES.md` and stops.
8. (user) One commit touching only `settings.json`, `agents/report-writer.md`, `agents/report-checker.md`, `agents/helper.md`; subject `Report-writer, report-checker and every session use the 1h prompt cache`; body quotes R4–R6 results; attribution lines per the session's rules. Not pushed on its own; it goes up with the release push.
Release (commit 2), unchanged from the archived plan except where noted:
9. (user) Every requirement R1–R18 of `plans/archive/PLAN-2026-10-25-v1-2-0-release.md` applies, with these edits:
   - R6 Settings gains a bullet: the one-hour prompt cache is requested on every request (main sessions and subagents) and the five-minute cache is never used; names `promptCacheTtl`, `subagentPromptCacheTtl`. The default-model bullet names the model actually committed (`claude-fable-5-1`).
   - R5 Agents: the report-writer and report-checker bullets each end with a sentence that they ask for the one-hour cache themselves; the helper bullet adds the cache wording fix.
   - R8 Agent versions: hashes read after commit 1.
   - R13: `agents/` is unmodified by the release commit (commit 1 is where it changes); README.md, wiki/, docs/, skills/ untouched throughout.
   - R14: `settings.json` is no longer in the release commit (it is in commit 1); the release commit touches CHANGELOG.md, RELEASE_NOTES.md, pyproject.toml (uv.lock if changed).
   - R15: `git push origin main v1.2.0` pushes both commits.
10. (default) Release date stays 2026-10-24 in the heading only if the release commit lands before 2026-10-25 00:00 ET; otherwise the heading and R1 use the actual ET date.

## Constraints
- Stack: this repo's tooling (bash, git, gh, jq, uv, python3 stdlib). No new dependencies, no new files besides the plan.
- Edits only the files named in R8 and R9; `plans/` is gitignored and never committed.
- Live checks spend real tokens (one `claude -p`, one planted eval run); run each once unless R7 forces a rerun.
- Dates and times in ET.

## Acceptance criteria
- [ ] R1: `jq -r '.promptCacheTtl, .subagentPromptCacheTtl, .env.ENABLE_PROMPT_CACHING_1H' settings.json` prints `1h`, `1h`, `1`; `jq empty settings.json` succeeds; `git diff HEAD~2 -- settings.json` adds only those three keys and the `model` value.
- [ ] R2: `grep -A1 '^experimental:' agents/report-writer.md agents/report-checker.md` shows `cacheTtl: 1h` twice; `git diff HEAD~2 -- agents/report-writer.md agents/report-checker.md | grep '^[-+][^-+]' | wc -l` is 4.
- [ ] R3: `grep -c '5 minutes' agents/helper.md` is 0; line 75 names the one-hour cache and settings.json; diff to helper.md is one changed line.
- [ ] R4–R6: `git log -1 --format=%B HEAD~1` contains the jq/grep output, `ephemeral_5m_input_tokens: 0` for the `claude -p` run, and a line `subagent events checked: N, ephemeral_5m: 0, ephemeral_1h: M` with N > 0 and M > 0.
- [ ] R7: no `ephemeral_5m` figure above 0 anywhere in the commit body; if the worker stopped, `plans/WORKER_NOTES.md` names the outside cause.
- [ ] R8: `git show --stat HEAD~1` lists exactly settings.json, agents/report-writer.md, agents/report-checker.md, agents/helper.md.
- [ ] R9: the archived plan's acceptance criteria R1–R18 all pass with its R13/R14 read as amended above; `grep -c 'promptCacheTtl' CHANGELOG.md RELEASE_NOTES.md` ≥1 each; `grep -c 'claude-fable-5-1\|Fable 5.1' RELEASE_NOTES.md` ≥1; `git show --stat v1.2.0` lists no `agents/` or `settings.json` path.
- [ ] R10: the `## v1.2.0 — <date>` heading date equals the release commit's date in ET.

## Amendments
- 2026-10-25 "Opus" (asked which default model was meant: Haiku as released, Fable 5.1 as planned, or Opus)
  - [ ] `jq -r .model settings.json` prints `opus`, and the v1.2.0 notes (CHANGELOG.md section, RELEASE_NOTES.md, the GitHub release body) name Opus as the default model or say it is unchanged; no `haiku` default-model wording remains there.
    Replaces: R9's `grep -c 'claude-fable-5-1\|Fable 5.1' RELEASE_NOTES.md` ≥1 and the "names the model actually committed (`claude-fable-5-1`)" edit to R6.
- 2026-10-25 "Also, the release description has some redundant things and it's not clear that it was properly written with my style from the / write-readme skill"
  - [ ] (user) In the v1.2.0 notes (CHANGELOG.md section, RELEASE_NOTES.md, GitHub release body), each change is said once: no Highlights line repeated by a section bullet, no two bullets saying the same thing.
  - [ ] (user) The v1.2.0 notes read as written with the `/write-readme` skill's style: the worker runs that skill's rules over the notes and lists in `plans/WORKER_NOTES.md` each rule and the lines it changed.
