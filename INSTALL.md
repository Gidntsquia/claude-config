# Installing claude-config

For a Claude session installing this repo on a new machine, started by a message like "Install https://github.com/Gidntsquia/claude-config following its INSTALL.md". Run the steps in order and stop only where it says STOP. Never edit a file in the user's `~/.claude`, shell rc files or terminal settings by hand: `./install.sh` makes every change, keeps a `<name>.pre-link` copy of anything it replaces, and is safe to rerun.

## 1. Check the tools

Run `command -v claude git bash python3 || command -v python`. Claude Code is already running, so `claude` is there.

- If `git` or `python3` is missing, ask once with AskUserQuestion whether to install it, then run `brew install git python` (macOS, needs Homebrew), `sudo apt-get install -y git python3` (Ubuntu/WSL) or `winget install Git.Git Python.Python.3.12` (Windows). If the user says no, STOP and tell them which tool is missing.
- `tmux` is needed only if the user picks the terminal setup in step 4. Check for it then, and install it the same way (`brew install tmux` / `sudo apt-get install -y tmux`) after a yes.

## 2. Clone

Clone into `~/.claude-config` unless the user named another folder in their message:

```
git clone https://github.com/Gidntsquia/claude-config ~/.claude-config
```

If the folder already holds a clone of this repo, run `git -C ~/.claude-config pull --ff-only` instead. Call the folder `$REPO`; every command below runs in it.

## 3. Look at the machine

- OS: `uname -s`. `Darwin` is macOS. `Linux` with `microsoft` in `/proc/version` and `$WSL_DISTRO_NAME` set is WSL (a Docker container on a WSL PC has the first but not the second). Other `Linux` is plain Linux. `MINGW*` or `MSYS*` is native Windows in Git Bash.
- Read what is in `~/.claude` already: `ls -la ~/.claude ~/.claude/agents ~/.claude/skills` and `~/.claude/settings.json` (note `model` and `statusLine`). Do not change anything.
- If `~/.claude/claude-config.json` exists, this machine was installed before: run `./install.sh` with no flags (it prints "reusing saved choices"), skip to step 6, and ask none of the questions.

On native Windows without WSL, tell the user before the questions: agents, skills, the settings merge and CLAUDE.md install from Git Bash, but the status line, tmux and the terminal setup need WSL (https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-WSL). Ask only questions 1 and 4, and pass `--no-terminal --statusline keep`.

## 4. Ask four questions

Ask all four in one AskUserQuestion call. The first option of each is the default and carries "(Recommended)".

1. **Projects folder**: where do your projects live? `~/files` (Recommended), `~/code`, `~/Projects`. "Other" lets them type a path. → `--projects <folder>`
2. **Terminal setup**: open new terminal tabs as tmux with 4 Claude panes in the projects folder, with the starship prompt and a Nerd Font check, through a Windows Terminal (WSL) or iTerm2 (macOS) "Claude tmux" profile? Options: "Yes, and make it my default profile", "Yes, keep my default profile", "No". Put the first option first and mark it Recommended when there is no `~/.tmux.conf` and no custom terminal profile (on WSL the distro's Windows Terminal profile has no `commandline`; on macOS `~/Library/Application Support/iTerm2/DynamicProfiles` is empty or missing); otherwise put "No" first and mark it Recommended. → `--terminal --default-profile`, `--terminal`, or `--no-terminal`. On plain Linux there is no profile, so offer "Yes" (`--terminal`) and "No".
3. **Status line**: Jaxon's squid (Recommended when `settings.json` has no `statusLine`), the plane (Jaxon's squid with a plane mascot and easter eggs), or keep mine (Recommended when they have one). → `--statusline squid|plane|keep`
4. **settings.json**: merge (Recommended: your values stay, the repo adds only keys you don't have, and permission lists are combined), keep mine (no change), or replace (link the repo's file; yours is kept as `settings.json.pre-link`). → `--settings merge|keep|replace`

Agents and skills are always installed. If the user picked the terminal setup and `tmux` is missing, install it now (step 1).

## 5. Install

```
./install.sh --projects <folder> <terminal flags> --statusline <choice> --settings <choice>
```

If it exits 3, some of the user's own agents or skills have the same name as the repo's; it printed each one as `clash: agents/<name>.md` or `clash: skills/<name>`. Ask one AskUserQuestion per name (up to four per call):

- **Keep mine** (Recommended): yours stays; the repo's is added as `<name>-claude-config` (`claude --agent <name>-claude-config`). → `<name>=keep`
- **Use Jaxon's**: yours moves to `<name>.pre-link.md` (skills: `<name>.pre-link`). → `<name>=replace`
- **Skip**: the repo's is not installed. → `<name>=skip`

Rerun the same command with `--agent-clash <name>=<answer>,<name>=<answer>` added. Remember every `<name>=keep` for the tour.

If it exits 1 or 2, show the user the last lines it printed and STOP.

If it printed a line starting with `@` for CLAUDE.md, tell the user that their CLAUDE.md was left alone and that adding that one line to it pulls in the repo's rules. Do not add it yourself.

## 6. Check

Run `./install.sh --check`. Every line must be PASS or SKIP and the last line `all checks passed`. On a FAIL, rerun step 5 once; if it still fails, show the FAIL lines and STOP.

## 7. Tour

Run `bash ~/.claude/statusline.sh --preview` (skip it if they kept their status line or are on Windows without WSL), then send this text, filling in `<projects>` and adding one line per kept agent (`Your planner stayed; mine is claude --agent planner-claude-config.`). Leave out step 2 if they said no to the terminal setup.

```
Installed. Five steps to get going:

1. Under every Claude prompt you'll see a status line like
   🦑 my-app | main | Opus | 5h 21%: the folder, the git branch, the model
   (each model has its own color), and how much of your 5-hour usage is gone.
   The list above shows the mascots that appear as that number climbs.
2. Open a new terminal tab: it opens tmux with 4 panes in <projects>.
   WSL: run wt.exe. Mac: run open -a iTerm and pick the "Claude tmux" profile.
   Ctrl+B then an arrow key moves between panes.
3. Each project goes through three agents, run from the project's folder:
     claude --agent planner         asks what you want, writes plans/PLAN.md
     claude --agent worker "."      builds it
     claude --agent evaluator "."   runs it and asks you if it works
   Not sure what's next? claude --agent helper walks you through it.
4. The beginner's guide: https://github.com/Gidntsquia/claude-config/wiki/Getting-Started
5. Try this now:
     mkdir <projects>/my-first-app && cd $_ && claude --agent planner

To update later, tell Claude: "update my claude-config following its UPDATING.md".
```
