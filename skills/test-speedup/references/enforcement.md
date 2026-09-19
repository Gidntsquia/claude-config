# Enforcement — the PreToolUse guard

The CLAUDE.md block in `references/policy.md` is advisory. It competes with the
model's own prior that running everything is the careful thing to do, and that
prior wins often enough that a perfectly tiered suite still gets run at full
width after a one-line edit. That is the complaint this file exists to answer:
the tiering worked, and the wall clock didn't move, because nothing routed to it.

The guard is a `PreToolUse` hook on `Bash`. It blocks a test command that names
no path, no name filter, and no tier flag, and tells the agent which narrow
command to run instead. Policy for the common case, override for the real one.

Install it in **step 1's shadow** — every file here is runner-invisible, so
writing them while the baseline runs is safe.

## 1. The commands file

`<repo>/.claude/test-commands.sh` — the single place the four strings live, so
the hook and CLAUDE.md can't drift apart:

```sh
FILE_CMD="pytest -m '' -n0 <file>"     # one file (must bypass the tier filter)
CHANGED_CMD="pytest --testmon -n0"     # changed files only
FAST_CMD="pytest -n auto -m 'not slow'"# fast tier — the default local run
FULL_CMD="pytest -n auto -m ''"        # union of fast and slow
DEFAULT_IS_FAST=1                      # `npm test` / `make test` runs FAST_CMD
```

Set `DEFAULT_IS_FAST=1` only once the repo's own default script really does run
the fast tier (see §4). Left at 0, the guard blocks `npm test` and `make test`.

## 2. The hook

**Check for a global install first:**

```
test -f ~/.claude/hooks/full-suite-guard.sh && grep -q full-suite-guard ~/.claude/settings.json
```

Both true → the hook is already live for every repo on this machine. Skip the
rest of this section entirely; §1's commands file is all that's needed, since
it is what switches the guard on for this repo. Say so in the report rather
than installing a second copy — two registrations means every block message
prints twice.

Otherwise install it per repo:

```
cp <skill>/scripts/full-suite-guard.sh <repo>/.claude/hooks/full-suite-guard.sh
chmod +x <repo>/.claude/hooks/full-suite-guard.sh
```

Merge into `<repo>/.claude/settings.json` — merge, never overwrite; a repo with
existing hooks keeps them:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/full-suite-guard.sh" }
        ]
      }
    ]
  }
}
```

`settings.json` is shared with the team through git. A repo that keeps agent
config out of version control gets `.claude/settings.local.json` instead — same
block, and add it to `.gitignore` if it isn't already.

## 3. Verify

```
bash <skill>/scripts/guard-selftest.sh .claude/hooks/full-suite-guard.sh
```

Both halves have to pass. A guard that blocks everything is worse than no
guard: the agent stops running tests at all, or burns turns fighting it.

Then say in the report that Claude Code asks the user to approve a new project
hook the first time it fires, and that until they approve it the guard does
nothing. A guard already installed globally in `~/.claude/settings.json` needs
no approval — the user wrote it themselves — so mention that path if the repo
route looks like friction.

## Inert until a repo opts in

The guard exits 0 immediately when it finds no `.claude/test-commands.sh`
(checking `$CLAUDE_PROJECT_DIR` first, then the working directory). A repo that
has never been through this skill has no narrow command to offer, so blocking
its test runs would be obstruction with nothing to suggest.

That is what makes the global install safe, and it is the recommended shape:
one hook entry in `~/.claude/settings.json`, no per-repo approval prompt, and
it stays dormant everywhere until this skill writes a commands file — at which
point that repo, and only that repo, is guarded.

## 4. Make the default command the fast one

The highest-leverage line in the whole pass, because it needs nobody to read
anything: whatever the repo's habitual command is — `npm test`, `make test`,
`just test`, the `test` script in `package.json` or the `Makefile` — point it at
the fast tier, and add a second explicitly-named target for the union
(`npm run test:full`, `make test-full`). CI and the pre-push hook call the union
target by name.

An agent that ignores CLAUDE.md, never sees the guard, and types the command it
already knew still gets the fast run.

## What the guard deliberately allows

- `TS_FULL=1 <cmd>` — the override. The deny message hands it to the agent, so
  a genuine full run costs one extra turn, not a fight.
- Anything running `measure.sh` — this skill's own passes.
- `--collect-only`, `--dry-run`, `--listTests`, `--list` — no tests execute.
- Any invocation naming a path, `-k`/`-t`/`-e`/`-run`/`--tests`, a tier marker,
  or a changed-files flag.

`pytest -m ''` is treated as a full run, not a filtered one: an empty marker
expression cancels the tier default, which makes it the union command.

## When the union gets cheap, relax the guard

The guard exists to stop a 150-second command being typed after a one-line edit.
If step 3b's consolidation lands hard enough that the union is down to seconds,
that command is no longer worth blocking, and a guard that blocks it is pure
friction — the agent burns a turn on `TS_FULL=1` to run something that costs
less than the argument about it.

Rule of thumb: **union under ~20s → drop `FULL_CMD` from what the guard blocks**,
keeping the block on the genuinely unbounded forms (a bare runner invocation with
no path, no filter, no tier). Say it in the report either way, with the number.
Do not quietly leave a guard in place that the measurements you just took have
made pointless, and do not remove it silently either — it is the user's repo and
the user's habit being shaped.

The same applies to the CLAUDE.md block: a policy paragraph warning that the full
suite "costs minutes" is worse than no paragraph once it costs thirteen seconds.
Update the numbers in the prose when the numbers change.

## Counting

Each `TS_FULL=1` run appends a byte to `$TMPDIR/ts-guard-<session_id>`, and the
next deny message quotes the count back. "You have already run the full suite
twice this session" is the argument that lands when the generic policy line
doesn't.
