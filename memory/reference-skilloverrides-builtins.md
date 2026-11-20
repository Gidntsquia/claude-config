---
name: reference-skilloverrides-builtins
description: "skillOverrides in settings.json does work on built-in (bundled) skills like loop, dataviz; verified 2026-10-08"
metadata:
  node_type: memory
  type: reference
  originSessionId: 1b9f55a9-0d47-4c22-a1ea-2b80d352387f
  modified: 2026-10-08T05:42:14.756Z
---

`skillOverrides` in `~/.claude/settings.json` hides built-in skills too (e.g. `"dataviz": "off"`), not just user/plugin skills. Verified 2026-10-08: after setting overrides, a new session's skill listing showed only the 6 kept skills (run, artifact-design, claude-api, frontend-design, artifact-capabilities, update-config).

No need for `disableBundledSkills` (all-or-nothing) to trim individual built-ins. Overrides live in the global file; the ai-sandbox project's `settings.local.json` was emptied to `{}` after merging its overrides into global. Part of the 2026-10-08 trim: [[project-context-trim-restore-point]].
