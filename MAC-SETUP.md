# Mac setup for claude-config

Read this page before cloning anything: <https://github.com/Gidntsquia/claude-config/blob/mac-handoff/MAC-SETUP.md>

This checklist sets up a Mac to keep working on claude-config: full planner/worker/evaluator rounds, Mac testing, and the v1.3 promotion. Nothing in it needs the Windows PC. Everything it uses is on GitHub: the `main` branch, the wiki, and the `mac-handoff` branch this page lives on.

How to use it: run the steps top to bottom in Terminal. Each step is one block to paste, followed by the line you should see. A step marked **Mac only** was not run in the rehearsal on the PC (it needs Homebrew, a browser login or a Mac app); every other step was run there from a fresh clone, in this order.

What stayed on the PC, and why, is in [LEFT-BEHIND.md](https://github.com/Gidntsquia/claude-config/blob/mac-handoff/LEFT-BEHIND.md).

## Known before you start

- The `mac-handoff` branch is public, like the rest of the repo. It holds old plans and notes with this PC's paths (`/home/jaxon/...`) in them. It holds no credentials.
- `mac-handoff` shares no history with `main`. Never merge it. Delete it when the trip is over: `git push origin --delete mac-handoff`.
- The memory notes and `archive/README.txt` name PC paths (`/home/jaxon/files/claude-config`). On the Mac read them as `~/files/claude-config`.
- Rerunning `./install.sh` with `--settings replace` rewrites `~/.claude/settings.json` from the repo copy. Run step 13 again after any rerun.
- No step failed in the rehearsal because of tracked code.

## Tools

### 1. Homebrew packages (Mac only)

```bash
brew install git python tmux gh uv
```

You should see: `tmux` and the other four names in the output of `brew list --formula | grep -E '^(git|python|tmux|gh|uv)'` (Homebrew names python with its version, such as `python@3.13`).

If `brew` is missing, install it first from <https://brew.sh>.

### 2. Claude Code 2.1.296 or newer (Mac only)

```bash
curl -fsSL https://claude.ai/install.sh | bash
claude update
```

You should see: `claude --version` prints `2.1.296` or a higher number. The usage guard needs that version.

### 3. Sign in to GitHub (Mac only)

```bash
gh auth login
gh auth setup-git
git config --global user.name "<your name>"
git config --global user.email "<your email>"
```

You should see: `gh auth status` prints `Logged in to github.com account Gidntsquia`.

### 4. iTerm2 and the Nerd Font, optional (Mac only)

```bash
brew install --cask iterm2 font-jetbrains-mono-nerd-font
```

You should see: `/Applications/iTerm.app` exists. Without iTerm2 the installer skips the "Claude tmux" profile and you run `tmux-quad` in any terminal. Without the font the prompt shows boxes. Install both before step 7 if you want the profile.

### 5. Check the tools

```bash
for t in git python3 tmux gh uv claude; do command -v "$t" >/dev/null || echo "missing: $t"; done; echo "tools checked"
```

You should see: `tools checked`, with no `missing:` line above it.

## Install

### 6. Clone

```bash
mkdir -p ~/files
git clone https://github.com/Gidntsquia/claude-config.git ~/files/claude-config
git -C ~/files/claude-config branch --show-current
```

You should see: `main`

### 7. Install

```bash
cd ~/files/claude-config
./install.sh --projects ~/files --terminal --default-profile --statusline squid --settings replace
echo "install exit $?"
```

You should see: `install exit 0`

These are the same choices this PC uses. Open a new terminal window afterwards so `~/.local/bin` is on your PATH.

### 8. Check the install

```bash
cd ~/files/claude-config
./install.sh --check | tail -1
```

You should see: `all checks passed`

### 9. Run the run-agent tests

```bash
cd ~/files/claude-config
bash skills/run-agent/scripts/test.sh 2>&1 | tail -1
```

You should see: `315 passed, 0 failed`

## Handoff files

### 10. Plans and the old prompt archive

```bash
cd ~/files/claude-config
git fetch origin mac-handoff
git archive origin/mac-handoff plans archive | tar -xf -
ls plans/PLAN.md plans/EVAL.md plans/WORKER_NOTES.md archive/README.txt
```

You should see: `plans/WORKER_NOTES.md`

Both folders are git-ignored on `main`, so `git status` stays clean. `plans/PLAN.md` and `plans/EVAL.md` are the v1.3 pre-release plan and its evaluation, so the planner picks the release up where it stopped.

### 11. The wiki and its unpublished page

```bash
cd ~/files/claude-config
git clone https://github.com/Gidntsquia/claude-config.wiki.git wiki
git show origin/mac-handoff:wiki/AI-Tells.md > wiki/AI-Tells.md
git -C wiki status --short
```

You should see: `?? AI-Tells.md`

The page is untracked in the wiki clone, the same state it had on the PC. It has never been published.

### 12. Memory notes

```bash
cd ~/files/claude-config
m="$HOME/.claude/projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')/memory"
mkdir -p "$m"
git archive origin/mac-handoff memory | tar -xf - -C "$m" --strip-components=1
ls "$m" | wc -l | tr -d ' '
```

You should see: `4`

Claude Code keeps a project's memory in a folder named after the clone's full path, with every character that is not a letter or digit turned into `-`. On a Mac that is `~/.claude/projects/-Users-<you>-files-claude-config/memory/`.

## This PC's settings

### 13. Model, effort levels and allow rules

The PC's `~/.claude/settings.json` differs from the repo copy in these values:

- `model`: `"fable"` (the repo copy says `"sonnet"`)
- `modelSettings`: the repo's table plus `"claude-fable-5-2": {"effortLevel": "low"}`. The whole table on the PC:
  `claude-fable-5` xhigh, `claude-fable-5-1` low, `claude-fable-5-2` low, `claude-sonnet-5` low, `claude-sonnet-5-5` low, `claude-opus-5` high, `claude-opus-5-5` medium, `qwen3.5-9b-local` low, `qwen3.5-9b-claude` low
- 2 allow rules, which on the PC read `Bash(/home/jaxon/files/claude-config/skills/run-agent/scripts/run-agent.sh *)` and `Bash(bash /home/jaxon/files/claude-config/skills/run-agent/scripts/*)`. They are the repo's `~/files/claude-config/...` rules with the clone's full path written out. The command writes them with the Mac's path.

```bash
python3 - <<'EOF'
import json, os
f = os.path.realpath(os.path.expanduser("~/.claude/settings.json"))
repo = os.path.realpath(os.path.expanduser("~/files/claude-config"))
s = json.load(open(f))
s["model"] = "fable"
s["modelSettings"] = {
    "claude-fable-5": {"effortLevel": "xhigh"},
    "claude-fable-5-1": {"effortLevel": "low"},
    "claude-sonnet-5": {"effortLevel": "low"},
    "qwen3.5-9b-local": {"effortLevel": "low"},
    "qwen3.5-9b-claude": {"effortLevel": "low"},
    "claude-sonnet-5-5": {"effortLevel": "low"},
    "claude-opus-5": {"effortLevel": "high"},
    "claude-opus-5-5": {"effortLevel": "medium"},
    "claude-fable-5-2": {"effortLevel": "low"},
}
allow = s.setdefault("permissions", {}).setdefault("allow", [])
rules = ["Bash(%s/skills/run-agent/scripts/run-agent.sh *)" % repo, "Bash(bash %s/skills/run-agent/scripts/*)" % repo]
for r in rules:
    if r not in allow:
        allow.append(r)
json.dump(s, open(f, "w"), indent=2)
open(f, "a").write("\n")
print("settings: model %s, %d effort levels, %d of 2 allow rules" % (s["model"], len(s["modelSettings"]), sum(r in allow for r in rules)))
EOF
```

You should see: `settings: model fable, 9 effort levels, 2 of 2 allow rules`

### 14. CLAUDE.local.md for the Mac

The repo has no macOS version of this file, and the installer leaves it alone on a Mac. This writes one with the two macOS "open" commands from `wsl/CLAUDE.local.md`, unless you already have the file.

```bash
f="$HOME/.claude/CLAUDE.local.md"
if [ -e "$f" ]; then echo "kept your existing $f"; else cat > "$f" <<'EOF'
## Environment
This is macOS.

## Opening things for the user (macOS)
- Web pages, HTML files, running apps and GitHub-hosted docs: `open -a Firefox "<path or url>"`
- `.md`, logs, text and source: `open -a "Visual Studio Code" "<path>"`
EOF
fi
grep -c 'open -a' "$f"
```

You should see: `2`

### 15. Confirm every handoff file is in place

```bash
cd ~/files/claude-config
m="$HOME/.claude/projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')/memory"
ls -d plans/PLAN.md plans/EVAL.md plans/EVAL_NOTES.md plans/WORKER_NOTES.md plans/RELEASE_TRACE.md plans/HANDOFF.md \
  plans/NOTE-run-agent-watchdog.md plans/STATUS-v1-3-1386430343.md plans/research plans/archive plans/LEFT-BEHIND.md \
  archive/README.txt wiki/AI-Tells.md "$m"/MEMORY.md "$HOME/.claude/CLAUDE.local.md" \
  && echo "plans/archive files: $(ls plans/archive | wc -l | tr -d ' ')" \
  && echo "archive files: $(ls archive | wc -l | tr -d ' ')" \
  && echo "memory files: $(ls "$m" | wc -l | tr -d ' ')" \
  && echo "handoff files in place"
```

You should see: `handoff files in place`, after `plans/archive files: 79`, `archive files: 6` and `memory files: 4`.

## What is open

1. **The `touch` wording in the release notes.** `RELEASE_NOTES.md:34` reads "`test.sh` can no longer touch a live tmux pane." and `skills/write-readme/references/style.md:26` flags "touch". Your answer at the 2026-11-18 evaluation: "Fine for now as the beta release. We will need a closer look when we do the full release". The full release is where the notes get reread against the style file.
2. **There is no v1.3.0 tag.** The newest tag is `v1.3.0-beta.4`, a pre-release. `UPDATING.md` step 3 skips pre-releases, so nobody who follows it gets 1.3 until a non-beta tag is published.
3. **CI runs only on a published release.** The install workflow triggers on `release: published` and nothing else. A macOS fix gets its macOS CI run only when a new release (a beta counts) is published.
4. **Checks only the Mac can do.** Neither was possible on the PC:
   - The iTerm2 profile: after step 7 with iTerm2 installed, `./install.sh --check | grep iTerm2` should print `PASS iTerm2 Claude tmux profile`, and iTerm2 > Settings > Profiles should list "Claude tmux".
   - A scheduled run-agent job under a real macOS session: schedule one from a tmux pane (`/run-agent` with a time a few minutes ahead), confirm `run-agent jobs` lists it, and confirm it fires. beta.3 failed here with `setsid: command not found`; beta.4 fixed it, and only CI has run that fix on macOS.
   - Kept known issue: with `--agent-clash keep`, the assistant copy cannot find its MCP server.
5. **Next command.** From a tmux pane in the clone:

   ```bash
   cd ~/files/claude-config && claude --agent planner
   ```

   Tell the planner you are promoting v1.3 to the full release. It reads `plans/PLAN.md`, `plans/EVAL.md` and `plans/EVAL_NOTES.md` from step 10.
