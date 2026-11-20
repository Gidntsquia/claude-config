# Spec: worker.md's usage-limit section rewritten to Anthropic's agent-definition guidance, with docs/agent-style.md recording the guidance

## Ask
Replan from `plans/EVAL.md` (2026-10-24, verdict replan). User said: "Yes, the fluff is gone. However, it's not clear that we used agent definition best practices as defined by Anthropic. Investigate".
Answers, verbatim:
- Scope: "Just the section for now. If we do well, I may audit the whole worker.md agent"
- Findings to apply: "Positive closing line", "Command on its own line", "Plain flag wording", "Trim the description"
- Evidence: "Table in PLAN.md + docs page"
- Judging: "Read section next to the table"
- Section length: "No cap, judge by eye"
- Docs page: "Guidelines + source quotes"
- Where the run command goes: "Wherever it should go based on you research"
- Start pointer: "Move the trigger out of Start"
Carried: everything in the archived plan passed (R1–R9); the `--handoff` script, its tests and the Start sentence stay as they are. The uncommitted `settings.json` hunk is still left alone.

## What to build
Rewrite the `## At the usage limit` section of `agents/worker.md` (currently lines 111–119) and the two places that point at it so they follow the guidance quoted under Facts: one sentence of trigger plus reason, two one-sentence numbered steps, the command in its own fenced block, a closing line that says what to do rather than what to avoid. Trim the frontmatter description to the one clause that says what the agent does. Write `docs/agent-style.md`: the house rules for agent files, each with the Anthropic quote it comes from and a link, and list it in README's Documentation section. Nothing else changes.

## Facts
Audit of the committed section (`agents/worker.md:111-119`, HEAD 093b600) against four Anthropic pages, fetched 2026-10-24 by the planner. The worker applies these; it does not re-research.

| Guideline (source, quote) | Current section | Verdict |
|---|---|---|
| Tell what to do, not what not to do. Prompting best practices: "Tell Claude what to do instead of what not to do … Instead of: 'Do not use markdown' … Try: 'Your response should be composed of smoothly flowing prose paragraphs.'" | Line 119: "Build nothing new, ask nothing, start no subagents" | Gap → fix (R2) |
| Numbered steps, one per step. Prompting best practices: "Provide instructions as sequential steps using numbered lists or bullet points when the order or completeness of steps matters." Sub-agents reference example: "When invoked: 1. … 2. … 3." one line each | Step 1 is a 3-line wrapped sentence with the command inline | Gap → fix (R1) |
| Colleague test. Prompting best practices: "Show your prompt to a colleague with minimal context on the task and ask them to follow it. If they'd be confused, Claude will be too." | "drop a flag you do not know" | Gap → fix (R1) |
| Short description, detail in body. Sub-agents reference: "Trim the `description` fields of your subagents, and move detail into each subagent's system prompt"; "Those descriptions take up context, so keep them short." | Description carries `Run as claude --agent worker "."` | Gap → fix (R3) |
| Launch command is for the human, not the agent. Claude Code best practices, CLAUDE.md table: include "Bash commands Claude can't guess", exclude "Anything Claude can figure out by reading code" and "Self-evident practices"; "For each line, ask: Would removing this cause Claude to make mistakes? If not, cut it." The agent never runs its own launch command. | — | Decision (R3): the command lives only in `README.md` Quickstart and `agents/README.md`, both of which already show it; it is not added to the body. |
| Give the reason. Prompting best practices: "Providing context or motivation behind your instructions … can give Claude more information about your goals." | Intro sentence gives one reason | Met |
| Soft wording. Prompting best practices: "The fix is to soften any aggressive language. Where you might have said 'CRITICAL: You MUST use this tool when…,' you can use more normal prompting such as 'Use this tool when…'" | No ALL-CAPS, "must", "exactly", "never" in the section | Met |
| One place per rule; long files get ignored. Claude Code best practices: "If Claude keeps doing something you don't want despite having a rule against it, the file is probably too long and the rule is getting lost." | The trigger is named twice: Start paragraph line 15–16 ("then `## At the usage limit` below replaces everything else") and the section's intro | Gap → fix (R4): trigger named once, in the section |
| Mid-turn message placement. Prompting Claude Sonnet 5.5 (worker's model): "Deliver mid-turn user input as a user turn." Claude Code delivers the usage-limit message as a user turn, so one plain sentence naming it is enough. | Intro names `[Usage limit reached;` | Met |
| Stop-and-report pattern. Prompting Claude Sonnet 5.5 sample: "When the work the user asked for is done and checked, stop and report." | Step 2 final message ≤ 6 lines | Met |
| Only documented frontmatter. Sub-agents reference: "Claude Code ignores a field it doesn't recognize without reporting an error." Documented: name, description, tools, disallowedTools, model, effort, permissionMode, color, initialPrompt, mcpServers, skills, hooks, memory, maxTurns, autoCompactWindow, background, omitClaudeMd, isolation, experimental. | name, description, model, effort, permissionMode, color | Met |
| Limit tool access. Sub-agents reference: "To restrict tools, use the `tools` field as an allowlist" | No `tools` field | Not applied: the worker needs every tool; out of scope ("just the section"). |

Sources: https://code.claude.com/docs/en/sub-agents · https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices · https://code.claude.com/docs/en/best-practices · https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5
Other: `docs/ai-tells.md` is the only file in `docs/`; README's Documentation list links it as "(also [docs/ai-tells.md](docs/ai-tells.md))". `agents/README.md:6` describes the worker's handoff and stays true. `test.sh` passes 142 cases; no script changes this round.

## Requirements
1. (user) `## At the usage limit` in `agents/worker.md` becomes: one intro sentence (trigger `[Usage limit reached;` + the reason: the allowance is small and fixed, so the handoff replaces finishing the piece in hand); a numbered list of two steps, each one sentence on one line (wrapped at the file's width if needed, but no clause lists): 1 write `Done:`, `In progress:` (half-finished files, subagent output included), `Next:` (the relaunched worker's first step) and pipe them to the command below, "with the same prompt, `--model` and `--effort` you were launched with"; 2 final message of at most 6 lines: the limit was reached, what is done, what is left, the three lines the script printed. The command sits in its own fenced block directly under step 1: `~/.claude/skills/run-agent/scripts/run-agent.sh --handoff worker "<prompt>" -- --model <model> --effort <effort>`. No length cap; the user judges by eye.
2. (user) The closing line states what to do: from here the only work is the handoff; running subagents finish on their own and are listed under In progress. No "nothing", "no", "never", "don't" in the section.
3. (user; placement is the planner's research decision) Frontmatter `description` becomes `Builds what plans/PLAN.md specifies, and does what the user says while doing it.` The launch command is not added to the body; `README.md` and `agents/README.md` already carry it.
4. (user) The Start paragraph (`worker.md:9-16`) loses the clause "or a message beginning `[Usage limit reached;` arrives: then `## At the usage limit` below replaces everything else"; the sentence ends after the blocked-criterion clause. The "Start: if `plans/WORKER_NOTES.md` ends with a `## Stopped at usage limit` section…" sentence stays unchanged. The section's intro is the only place the trigger is named.
5. (user) `docs/agent-style.md`, about 30 lines: title, one sentence on what it is for (rules for writing agent files in this repo, each traced to an Anthropic page), then one entry per guideline in the Facts table marked Met, Gap or Decision (not the tools allowlist row): a one-line house rule in plain words, the quoted sentence under it, and the source link. Order: say what to do; numbered one-line steps; colleague test; reason with each rule; soft wording; short description, detail in body; launch command for humans only; one place per rule; documented frontmatter only. No table, no mention of this round's audit.
6. (default) `README.md` Documentation list gains one bullet for `docs/agent-style.md` in the same style as the ai-tells bullet ("[Agent style](docs/agent-style.md) — how the agent files are written, traced to Anthropic's guidance"). `CHANGELOG.md` gets a top entry naming the section rewrite, the description trim and the new doc.
7. (default) Nothing else changes: `run-agent.sh`, `test.sh`, `SKILL.md`, the other agents, `settings.json` (its uncommitted hunk stays uncommitted and unreverted), `agents/README.md`.
8. (default) Wording across the changed lines follows the Facts rows: no ALL-CAPS emphasis, no "must", "exactly", "always", "never", "wrong"; each rule keeps at most one reason clause.
9. (default) `bash skills/run-agent/scripts/test.sh` still passes; the change is committed in one commit touching only `agents/worker.md`, `docs/agent-style.md`, `README.md`, `CHANGELOG.md`.

## Constraints
- Stack is what the repo uses: Markdown agent files, bash + Python under `skills/`. No new dependencies, hooks or agents.
- The planner did the research; the worker applies the Facts quotes verbatim where quoted and does not re-fetch the pages.
- The user judges by reading; keep the section as prose a human skims.

## Acceptance criteria
- [ ] R1: `sed -n '/^## At the usage limit/,$p' agents/worker.md` shows intro sentence, `1.` and `2.` each one sentence, one fenced block containing one `run-agent.sh --handoff` line, closing line; `grep -c 'drop a flag' agents/worker.md` → 0; "same prompt, `--model` and `--effort`" present.
- [ ] R2: in that range `grep -n -i -E '\bnothing\b|\bno\b|never|don.t|do not'` finds nothing; the closing line names the handoff as the only work and In progress for subagents.
- [ ] R3: `sed -n 3p agents/worker.md` is `description: Builds what plans/PLAN.md specifies, and does what the user says while doing it.`; `grep -c 'claude --agent worker' agents/worker.md` → 0; `grep -c 'claude --agent worker' README.md agents/README.md` ≥ 1 each.
- [ ] R4: `grep -c 'Usage limit reached' agents/worker.md` → 1, and it is inside the section; `sed -n 9,16p` still has the Start sentence.
- [ ] R5: `docs/agent-style.md` exists, 25–40 lines, 9 house rules each followed by a quoted sentence and a `https://` link; `grep -c -i audit docs/agent-style.md` → 0.
- [ ] R6: `grep -n 'agent-style' README.md CHANGELOG.md` finds one line each.
- [ ] R7/R9: `git show --stat HEAD` lists only `agents/worker.md`, `docs/agent-style.md`, `README.md`, `CHANGELOG.md`; `git diff settings.json` unchanged before and after; `bash skills/run-agent/scripts/test.sh` ends `0 failed`.
- [ ] R8: `grep -n -E '\b(MUST|CRITICAL|IMPORTANT|exactly|always|never|wrong)\b' agents/worker.md` finds nothing in lines 1–16 or the section (hits elsewhere are out of scope).
- [ ] Judging (user): evaluator opens `agents/worker.md` at the section and `plans/PLAN.md` at the Facts table side by side in VS Code; the user says whether each Gap row is now closed.
