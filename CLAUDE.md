## Communication Style
Write in plain, direct language. No startup/consulting jargon ('levers', 'happy to dig into', 'unlock', 'double-click'). State what happened, what it costs, and what to do next.
Give every clock time in US Eastern time, never UTC (logs and `date -u` are UTC; convert first).

## Shell Conventions
- Always quote URLs and paths in shell commands to avoid word-splitting.
- Exclude large data files from grep/search (e.g. `--exclude=*.txt --exclude-dir=data`); never scan multi-MB dictionaries.
- `~/.claude` config files are symlinks into the git repo `~/files/claude-config`; commit and push changes there.

## Machine-Specific Notes
@~/.claude/CLAUDE.local.md
