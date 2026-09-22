## Communication Style
Write in plain, direct language. No startup/consulting jargon ('levers', 'happy to dig into', 'unlock', 'double-click'). State what happened, what it costs, and what to do next.

## Shell Conventions
- Always quote URLs and paths in shell commands to avoid word-splitting.
- Exclude large data files from grep/search (e.g. `--exclude=*.txt --exclude-dir=data`); never scan multi-MB dictionaries.
- Re-read a file immediately before Edit if a previous Edit failed on string match.
