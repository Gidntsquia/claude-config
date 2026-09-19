# claude-config

My Claude Code config. The files live here; `~/.claude` holds symlinks to them.

- `agents/` — planner, worker, evaluator (see `agents/USAGE.txt`)
- `skills/` — personal skills (each one linked separately; `~/.claude/skills/synced` is managed by Claude and stays out)
- `commands/`, `hooks/`, `CLAUDE.md`, `settings.json`, `statusline.sh`

New machine: clone, then run `./install.sh`.

Never add `.credentials.json`, `history.jsonl`, `projects/`, or other session data.
