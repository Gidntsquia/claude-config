# Handoff: v1.2.1 one-sentence install

## Mac test (Jaxon's brother, or anyone with a Mac)

Use a Mac account that has Claude Code installed and signed in. iTerm2 is optional: without it the install skips the profile.

1. Open a terminal, run `claude`, and paste:
   `Install https://github.com/Gidntsquia/claude-config following its INSTALL.md`
2. Answer the four questions (projects folder, terminal setup, status line, settings). Pick "Yes, and make it my default profile" for the terminal setup to test iTerm2.
3. Claude runs `./install.sh --check` at the end. Confirm the last line is `all checks passed`.
4. Open a new iTerm2 window or tab (Cmd+T). It should open tmux with 4 panes in the projects folder, with the starship prompt. Run `claude` in one pane and check the status line shows under the prompt (folder | branch | model | 5h %).
5. In one pane: `mkdir ~/files/toy && cd ~/files/toy && claude --agent planner` (use your projects folder). Ask for something tiny, like "a web page with a button that counts clicks". Then `claude --agent worker "."`, then `claude --agent evaluator "."`.
6. Report back "Mac passed", or the step number, what you saw and the output of `./install.sh --check` from `~/.claude-config`.

To undo: `cd ~/.claude-config && cat ~/.claude/claude-config.json`; every replaced file is next to the original as `<name>.pre-link`, and install printed the one command that restores your old iTerm2 default profile.

## State

See `plans/WORKER_NOTES.md` (section "v1.2.1 one-sentence install") for each acceptance criterion. Everything is pushed to main. The v1.2.1 tag and `gh release create v1.2.1 --latest` wait for "Mac passed".

After "Mac passed":

```
git tag -a v1.2.1 -m "v1.2.1" && git push origin v1.2.1
gh release create v1.2.1 --title "v1.2.1" --notes-file RELEASE_NOTES.md --latest
```
