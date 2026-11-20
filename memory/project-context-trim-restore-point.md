---
name: project-context-trim-restore-point
description: 2026-10-08 context trimming of ~/.claude config; git tag pre-trim-2026-10-08 in claude-config is the rollback point
metadata:
  type: project
---

On 2026-10-08 Jaxon trimmed Claude Code's context: denied the Workflow tool, added skillOverrides, set workflowKeywordTriggerEnabled false, and set env ENABLE_CLAUDEAI_MCP_SERVERS=false (no claude.ai connectors such as Claude Docs). The tag `pre-trim-2026-10-08` (commit 7c8651b) in ~/files/claude-config marks the config before any of it; it's pushed to GitHub.

**Why:** Jaxon wants a guaranteed way back if the trimming breaks something.
**How to apply:** If tools, skills, or connectors seem to be missing or broken, check these settings first. To roll back: `git checkout pre-trim-2026-10-08 -- settings.json` in the claude-config repo. See [[reference-claude-config-repo]].
