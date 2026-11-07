# Text you never wrote filled the turn

> I want to clean up the global base context of my Claude code. In this round, I want to audit every component of my context (i.e system prompt, MCP servers, skills, etc.) in terms of how many tokens they take up. I want every source tallied up. I also want each source justified as to why it's important
~ Jaxon, planner session 1e87453d in base-context-cleanup, 2026-11-04 15:57 ET

[[Base context]] means the always-loaded part.

The audit behind these numbers ran on Jaxon-PC at [[05:16]] ET on [[5 November]] and borrowed Claude Code's built-in text from one Slay the Spire advisor session ([[44904a3d]]). Its first request was billed {ref_billed} for {ref_chars}.

I take it as typical because that first turn carried the base context every session here carries, plus one project AGENTS.md of {sts_A}.

But the audit counts one token per four characters, and that one request (n = [[1]]) came to one per {ref_ratio}. By the four-character ruler the base context is {A_total}, and at the billed ratio it is {A_measured}. Claude Code's own `/context` screen says {ctx_given}.

---

Every session on this machine starts with {A_total} by the raw count, {fe_turn} a turn, and {p_tools} of them are built-in tool schemas, text you never wrote. The logs vouch for {a_used} of it.

## 🧮 What fills the base context every turn?

The base context is mostly the schemas of the built-in tools, {p_tools} of it, and every other source together comes to {a_rest}.

After the first turn the base context is read from the cache, and the study prices every source by one rule, {fe_rate} Fable-equivalent tokens (FE) a turn for each raw token.

The table lists each source of the base context with its raw count and what it costs a turn.

::table source | raw | a turn ;; built-in tools | {p_tools} | {p_tools_fe} ;; system prompt | {p_sys} | {p_sys_fe} ;; skill listings | {p_skills} | {p_skills_fe} ;; agent listings | {p_agents} | {p_agents_fe} ;; CLAUDE.md files | {p_memory} | {p_memory_fe} ;; output style | {p_style} | {p_style_fe} ;; hooks, settings, statusline | {p_config} | {p_config_fe} | cap=Section A, global session, one token per four characters

One tool fills most of the base context's first row.

The Artifact tool "renders an HTML file as an Artifact: a web page hosted on claude.ai". Its schema is {artifact_raw} by itself, {artifact_fe} a turn, and that is more than every other source in the base context outside the tools row.

The last row never reaches the model, because hooks, settings and the statusline run on the machine, but the audit counts it anyway.

## 🔭 How much of it do the logs back?

The logs back {a_used} of the base context, the skill and agent listings that some session called in the four weeks before [[5 November]].

The audit counts sessions only for skills and agents it can see invoked in a log, so it has no count for the system prompt, the tool schemas, your CLAUDE.md files or the config. Tool calls are in the logs, but the study never tallied them, so the use of the base context's tools is not measured.

The split sorts the base context by what the logs say about it.

::split A_total | a_used a_unused a_notmeasured | labels=called unused not_measured | cap=Section A raw tokens by session count over four weeks

{a_unused_n} listings in the base context went unused, among them the four document skills and the built-in artifact-capabilities, the largest of them. The busiest is the report-writer agent, called in {rw_sessions}. I cannot justify the not-measured part from use, because the study did not measure it.

## ⏱️ What waits until it is called?

The base context keeps {B_total} more off the turn until a skill, agent or MCP server is called, which the study calls Section B. Skill bodies are {B_skills} of it and agent files {B_agents}.

The split puts what was called in the four weeks beside what was not.

::split B_total | B_used B_unused | labels=called not_called | cap=Section B raw tokens, global session

More of this on-demand context sat unused than was called, and the largest unused body is the setup-writing-style skill at {sws_raw}.

The total is a floor, since {B_unknown_n} built-in bodies (the Explore agent and the claude-api skill among them) are not on disk and their size is not measured. Another {C_total} is configured but switched off, Section C, and adds nothing to the base context a turn.

## 🔀 What do the named projects add?

The base context grows in each of the three projects you named, and agent-eval-experiment adds the most to every turn, {eval_A} raw, {eval_fe} a turn.

The table lists what each project adds to the base context of a session with no project files.

::table project | always | on demand | a turn ;; pogo | {pogo_A} | {pogo_B} | {pogo_fe} ;; agent-eval | {eval_A} | {eval_B} | {eval_fe} ;; assistant | {asst_A} | {asst_B} | {asst_fe} | cap=added over the global session

Nearly all of agent-eval-experiment's addition is its AGENTS.md at {eval_agents_md}, which joins the base context in every session there.

The assistant-agent project adds little to the base context and {asst_B} on demand, nearly half of it the schemas of its own MCP server, {asst_mcp}. In pogo-gbl-team-generator, the project you opened most ({pogo_sess}), the project CLAUDE.md is {pogo_md} of what it adds.

Among the other projects the study tallied for having three or more sessions, deadlock-street-brawl-helper adds the most to the base context, {dsb_A} raw across {dsb_sess}.

## 🔁 Back to that first request

That Slay the Spire session ([[44904a3d]]) was billed {ref_billed} for its first request, and at that session's ratio the base context's raw {A_total} come to {A_measured} on every turn of every session. Every source in it is now tallied, from the {artifact_raw} Artifact schema down to the statusline command.

Most of the base context is Claude Code's own text. Only {a_used} has a session in the logs to justify it, and {a_notmeasured} has no usage count, so the audit can say what the base context costs and cannot say for most of it whether you use it. The tally stops there, as you asked, with no cuts in it.

📚 `context-audit.json` (global and project tallies, reconciliation, pricing), `context-audit.md` (the same data as the script's table), `README.md` (definitions).

::checker loops=1 raised=4 fixed=4 open=0 tokens=577639 seconds=124
