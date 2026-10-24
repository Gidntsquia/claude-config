# Agent style

Rules for writing the agent files in `agents/`, each traced to the Anthropic page it comes from.

1. **Say what to do, not what to avoid.** A rule reads "write prose paragraphs", not "do not use markdown".
   > "Tell Claude what to do instead of what not to do … Instead of: 'Do not use markdown' … Try: 'Your response should be composed of smoothly flowing prose paragraphs.'"
   https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
2. **Ordered work is a numbered list, one sentence per step.** Commands go in their own code block under the step.
   > "Provide instructions as sequential steps using numbered lists or bullet points when the order or completeness of steps matters."
   https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
3. **Colleague test.** A line a new colleague would stumble on is rewritten until they would not.
   > "Show your prompt to a colleague with minimal context on the task and ask them to follow it. If they'd be confused, Claude will be too."
   https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
4. **Give the reason with the rule.** One clause saying why is enough.
   > "Providing context or motivation behind your instructions … can give Claude more information about your goals."
   https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
5. **Plain wording.** Plain sentences, with capitals, "must" and "critical" left out.
   > "The fix is to soften any aggressive language. Where you might have said 'CRITICAL: You MUST use this tool when…,' you can use more normal prompting such as 'Use this tool when…'"
   https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
6. **Short description, detail in the body.** The `description` says what the agent does in one clause; the rest goes below the frontmatter.
   > "Trim the `description` fields of your subagents, and move detail into each subagent's system prompt"
   https://code.claude.com/docs/en/sub-agents
7. **The launch command is for people.** `claude --agent …` lives in the READMEs; the agent reads its own file only after it has been launched.
   > "For each line, ask: Would removing this cause Claude to make mistakes? If not, cut it."
   https://code.claude.com/docs/en/best-practices
8. **One place per rule.** Each rule is stated once, where it applies, so the file stays short enough to be followed.
   > "If Claude keeps doing something you don't want despite having a rule against it, the file is probably too long and the rule is getting lost."
   https://code.claude.com/docs/en/best-practices
9. **Documented frontmatter only.** Fields are from the sub-agents reference (name, description, tools, model, effort, permissionMode, color, …).
   > "Claude Code ignores a field it doesn't recognize without reporting an error."
   https://code.claude.com/docs/en/sub-agents
