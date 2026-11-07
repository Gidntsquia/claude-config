# defer-artifact

A Claude Code mod that marks the built-in `Artifact` tool deferred. Sessions carry a one-line
"Artifact" entry in the deferred-tools list instead of its full schema (about 38 KB), and Claude
loads the full definition through `ToolSearch` when it wants to read or publish an artifact.

Needs Claude Code 2.1.293 or later. On older versions, and wherever mods do not load
(`--safe-mode`, `--bare`, `disableAllHooks`), Artifact behaves as before and nothing errors.

## What it saves

About 9.6k raw tokens per request (Artifact schema 38,426 B). Measured on 2.1.319 in a plain
project: `/context` System tools 19.7k without the mod, 7.3k with it; a subagent's first request
22,565 tokens without, 10,093 with. Loading Artifact puts the full schema back for the rest of
that session.

## Using Artifact

Ask for an artifact as usual ("publish this as an artifact"). Claude runs
`ToolSearch select:Artifact` and then publishes. Skills that publish (weekly-roundup) say to load
it first. The deferred-tools list names Artifact from a session's second request on; asked on
the first message, Claude still found it with ToolSearch and published (tested on 2.1.319).

## Turning it off

- For one session: disable `defer-artifact` in `/plugin`, or start with `--safe-mode`.
- For good: remove the `mods/defer-artifact` path from `env.CLAUDE_CODE_PLUGIN_DIRS` in
  `~/.claude/settings.json` (install.sh adds it back on the next install).

## Files

- `.claude-plugin/plugin.json`: name and version.
- `hooks/hooks.json`: loads `register.js`.
- `hooks/register.js`: one `tool.describe` hook, matched to `Artifact` only.
- `tests/defer-artifact.test.ts`: `claude plugin test mods/defer-artifact`.
