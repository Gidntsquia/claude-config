# Which tests are kept

Every test as it stood on commit 4bbcc43 (2026-11-27), what break it catches, and a verdict: keep, merge, rewrite
or delete. The tree matches this page as of the commit that added it; a test added later is listed with the verdict new.

Total: before 805, after 755 (10 deleted; 59 merged into 18; 1 added after the review, marked new).

- A test is listed once, under the first feature it is tagged with; each table says how many tests of other tables
  also carry its tag.
- delete: the same input is tested elsewhere, or the test pins something no behaviour depends on.
- merge: several tests read one run or one rule; they are now one test, and the failure output says which line broke.
- rewrite: none. The sleeps the research wanted rewritten were replaced in the port and are refused by the lint.
- A cut that would lower `bin/release/faults` is put back and marked keep.

## install

install.sh links the config into ~/.claude and --check verifies a fresh or existing home.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| docker: every install scenario passes in a fresh ubuntu:24.04 container | install.sh failing on a bare Ubuntu that has only git, curl, python3 and tmux | keep | the only run on a system that is not a CI runner image |
| macOS: the real defaults reads, writes and deletes keys the way the stand-in does | the real defaults behaving differently from the stand-in | keep | the only comparison of the defaults stand-in with the real tool |
| --agent-clash keep: the clashing agent gets a renamed copy and the assistant is not installed globally | --agent-clash keep overwriting your agent, or the assistant installed globally | keep | one group of checks of this install scenario; no other scenario starts from this home |
| assistant linked into a project: it finds its MCP server and guard hook in the clone | the assistant not finding its MCP server or guard hook from a project | keep | one group of checks of this install scenario; no other scenario starts from this home |
| --agent-clash keep: --check passes the assistant, the clone is unchanged, no .pre-link file | --check failing with the assistant linked | keep | one group of checks of this install scenario; no other scenario starts from this home |
| assistant: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: the starting install is as described | the scenario not starting from the older release with the user's commits (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: the merge, the settings conflict and install.sh keeping your skill happen | the update skipping the merge, the conflict or the kept skill (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: your commits, your files in them and your branch are still there | your commits, files or branch lost in the update (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: session files, history and plugins are byte-identical | session files, history or plugins changed (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: your settings file stays yours, with your keys and your edit | your settings file replaced or broken (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: your uncommitted lines and notes file are back and the stash is empty | your uncommitted lines or notes lost, or left in the stash (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: the clone's settings file keeps your edit, takes the release's values, no conflict markers | conflict markers left in the clone's settings file, or your edit lost (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: your own skill folder is untouched and everything else links into the clone | your own skill folder replaced by a link (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.3.0-beta.5 with your edits: --check passes, no new .pre-link copy, git status lists only your four files | --check failing, .pre-link copies made, or stray files in the clone (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| dirty-beta5: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing (from v1.3.0-beta.5) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: the starting install is as described | the scenario not starting from the older release with the user's commits (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: the merge, the settings conflict and install.sh keeping your skill happen | the update skipping the merge, the conflict or the kept skill (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: your commits, your files in them and your branch are still there | your commits, files or branch lost in the update (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: session files, history and plugins are byte-identical | session files, history or plugins changed (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: your settings file stays yours, with your keys and your edit | your settings file replaced or broken (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: your uncommitted lines and notes file are back and the stash is empty | your uncommitted lines or notes lost, or left in the stash (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: the clone's settings file keeps your edit, takes the release's values, no conflict markers | conflict markers left in the clone's settings file, or your edit lost (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: your own skill folder is untouched and everything else links into the clone | your own skill folder replaced by a link (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1 with your edits: --check passes, no new .pre-link copy, git status lists only your four files | --check failing, .pre-link copies made, or stray files in the clone (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| dirty-v121: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing (from v1.2.1) | keep | one group of checks of this install scenario; no other scenario starts from this home |
| existing settings: install.sh exits 0 and install.sh --check passes | install.sh or --check failing on a home with settings | keep | one group of checks of this install scenario; no other scenario starts from this home |
| existing settings: the repo holds no personal path | nothing the installed-text tests do not catch: it reads the repo, not the home | delete | same check as installed-text's two path tests; the scenario still runs it and “ran to its end” fails if it does |
| existing settings: claude doctor exits 0 | an install over your settings that claude doctor rejects | keep | one group of checks of this install scenario; no other scenario starts from this home |
| existing settings: claude-config.json names this clone | claude-config.json naming another clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| existing settings: your model, status line and deny list stay, and the repo's keys are added | your model, status line or deny list overwritten | keep | one group of checks of this install scenario; no other scenario starts from this home |
| existing settings: your plugin dirs and hooks stay, with the repo's added after them | your plugin dirs or hooks dropped | keep | one group of checks of this install scenario; no other scenario starts from this home |
| existing settings: CLAUDE.md stays byte-identical and --agent-clash replace installs the repo's planner | CLAUDE.md changed, or --agent-clash replace not replacing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| existing settings: a rerun with no flags reuses the saved choices and lists the mod dir once | a rerun forgetting the saved choices | keep | one group of checks of this install scenario; no other scenario starts from this home |
| existing settings: no .pre-link file is left and --check shows every repo agent installed or kept | .pre-link files left, or --check missing an agent | keep | one group of checks of this install scenario; no other scenario starts from this home |
| b: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| fresh install: install.sh exits 0 and install.sh --check passes | install.sh or --check failing on an empty .claude | keep | one group of checks of this install scenario; no other scenario starts from this home |
| fresh install: the repo holds no personal path | nothing the installed-text tests do not catch: it reads the repo, not the home | delete | same check as installed-text's two path tests; the scenario still runs it and “ran to its end” fails if it does |
| fresh install: claude doctor exits 0 | an install claude doctor rejects | keep | one group of checks of this install scenario; no other scenario starts from this home |
| fresh install: claude-config.json names this clone | claude-config.json naming another clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| fresh install: the status line, CLAUDE.md, the mod dir and the planner agent are in place | the status line, CLAUDE.md, mod dir or planner agent not installed | keep | one group of checks of this install scenario; no other scenario starts from this home |
| fresh install: a rerun with no flags reuses the saved choices and lists the mod dir once | a rerun forgetting the saved choices or listing the mod dir twice | keep | one group of checks of this install scenario; no other scenario starts from this home |
| fresh install: no .pre-link file is left and --check shows every repo agent installed or kept | .pre-link files left, or --check missing an agent | keep | one group of checks of this install scenario; no other scenario starts from this home |
| a: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| a throwaway home without a keychain: the run fails | an install test running in a home with no keychain, so macOS puts a dialog on the real screen (past error 5) | merge | into “a throwaway home without a keychain: the run fails, names the home, and neither install.sh nor claude runs in it”: three lines of one refused run |
| a throwaway home without a keychain: the FAIL line names the home | the failure not saying which home | merge | into “a throwaway home without a keychain: the run fails, names the home, and neither install.sh nor claude runs in it”: three lines of one refused run |
| a throwaway home without a keychain: neither install.sh nor claude runs in it | install.sh or claude run in that home anyway | merge | into “a throwaway home without a keychain: the run fails, names the home, and neither install.sh nor claude runs in it”: three lines of one refused run |
| nokeychain: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| on WSL the install tests refuse to run with --terminal | the install tests writing Windows Terminal keys from WSL | keep | one group of checks of this install scenario; no other scenario starts from this home |
| moved clone: the first install works | the scenario's first install failing | merge | into “moved clone: plain ./install.sh from the new path relinks everything and calls nothing yours”: the first install is only that test's starting point |
| moved clone: plain ./install.sh from the new path relinks everything and calls nothing yours | a moved clone treated as the user's own files (past error 1c) | merge | into “moved clone: plain ./install.sh from the new path relinks everything and calls nothing yours”: the first install is only that test's starting point |
| moved clone: settings.json names the new path only | settings.json still naming the old path | keep | one group of checks of this install scenario; no other scenario starts from this home |
| moved clone: --check passes, the clone is unchanged, no .pre-link file | --check failing after the move | keep | one group of checks of this install scenario; no other scenario starts from this home |
| moved clone without claude-config.json: plain ./install.sh relinks everything and calls nothing yours | the same without claude-config.json to say where the clone was | keep | one group of checks of this install scenario; no other scenario starts from this home |
| moved clone without claude-config.json: the status line and the terminal setup stay installed | the status line or terminal setup lost in the move | keep | one group of checks of this install scenario; no other scenario starts from this home |
| moved clone without claude-config.json: --check passes, the clone is unchanged, no .pre-link file | --check failing after the move without claude-config.json | keep | one group of checks of this install scenario; no other scenario starts from this home |
| moved: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| usage-guard script missing: the install works and leaves 7 usage-guard hook commands | the install failing or dropping guard hooks | keep | one group of checks of this install scenario; no other scenario starts from this home |
| usage-guard script missing: each of the 7 hook commands exits 0 | a session blocked on every tool call when the guard is gone (past error 1b) | keep | replays past error 1b; one group of checks of this install scenario; no other scenario starts from this home |
| usage-guard script missing: you are told once per session that the guard is off | silence, or a notice on every call, when the guard is off | keep | one group of checks of this install scenario; no other scenario starts from this home |
| usage-guard script missing: a rerun and --check pass, the clone is unchanged, no .pre-link file | a rerun or --check failing without the guard | keep | one group of checks of this install scenario; no other scenario starts from this home |
| noguard: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| a hook's script missing: the install works and has at least 8 hook commands | the install failing or installing fewer hook commands | keep | one group of checks of this install scenario; no other scenario starts from this home |
| a hook's script missing: every installed hook command still exits 0 | a hook erroring in every session when its script is gone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| a hook's script missing: --check passes, the clone is unchanged, no .pre-link file | --check failing with a hook script missing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| nohook: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| paths with spaces: install.sh works and creates the projects folder | install.sh splitting a path at a space | keep | one group of checks of this install scenario; no other scenario starts from this home |
| paths with spaces: claude-config.json keeps both paths whole | claude-config.json cutting a path at a space | keep | one group of checks of this install scenario; no other scenario starts from this home |
| paths with spaces: --check passes, the clone is unchanged, no .pre-link file | --check failing on paths with spaces | keep | one group of checks of this install scenario; no other scenario starts from this home |
| paths with spaces: a rerun passes the same checks | a rerun failing on paths with spaces | keep | one group of checks of this install scenario; no other scenario starts from this home |
| odd: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1: its own installer works and leaves the older layout | the scenario not starting from a real v1.2.1 layout | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1: iTerm2 points at the clone until install.sh runs, and not after | iTerm2 left loading preferences from the clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1: the current install.sh, no flags, makes hooks and settings.json real | hooks or settings.json left as links into the clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from v1.2.1: --check passes, the clone is unchanged, no .pre-link file | --check failing after the update from v1.2.1 | keep | one group of checks of this install scenario; no other scenario starts from this home |
| oldtag: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| install as a Mac: the common and macOS tools are linked, no WSL tool and no .ps1 | a Mac install missing a macOS tool or getting a WSL one | keep | one group of checks of this install scenario; no other scenario starts from this home |
| install as a Mac: --check passes and lists win.sh and evshow.sh | --check failing or not listing the window tools on a Mac | keep | one group of checks of this install scenario; no other scenario starts from this home |
| install as a Mac: --check says whether Firefox is installed, and a missing one is only a warning | a missing Firefox failing --check, or not mentioned | keep | one group of checks of this install scenario; no other scenario starts from this home |
| rerun as plain Linux: only the common tools remain | macOS tools left after a rerun as Linux | keep | one group of checks of this install scenario; no other scenario starts from this home |
| install as a Mac: the clone is unchanged | the install writing into the clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| osmac: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| install as WSL: the common and WSL tools are linked and no macOS tool | a WSL install missing a WSL tool or getting a macOS one | keep | one group of checks of this install scenario; no other scenario starts from this home |
| install as WSL: --check passes and lists win.sh and evshow.sh | --check failing or not listing the window tools on WSL | keep | one group of checks of this install scenario; no other scenario starts from this home |
| --check as a Mac on a WSL install fails and names the WSL tools | --check passing an install made for another OS | keep | one group of checks of this install scenario; no other scenario starts from this home |
| rerun as a Mac: the WSL tools are swapped for the macOS ones | WSL tools left after a rerun as a Mac | keep | one group of checks of this install scenario; no other scenario starts from this home |
| install as WSL: the clone is unchanged | the install writing into the clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| oswsl: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from September: iTerm2's own write shows as a local change in the clone | the scenario not starting: iTerm2's write not a local change | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from September: the plist iTerm2 uses is in place after the pull, byte for byte | the pull losing the plist iTerm2 uses | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from September: install.sh leaves the plist alone and stops iTerm2 loading from the clone | install.sh touching the plist or leaving iTerm2 on the clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| update from September: --check passes, only the kept plist is new in the clone, no .pre-link file | --check failing, or more than the kept plist new in the clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| plist: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| updating a pre-v1.3 layout: hooks becomes a real folder of links and the clone keeps its own | the old hooks link kept, so new hooks land in the clone (past error 1a) | keep | replays past error 1a; one group of checks of this install scenario; no other scenario starts from this home |
| updating a pre-v1.3 layout: links to things gone from the repo are removed, and it says so | dead links to things the repo dropped left in place | keep | one group of checks of this install scenario; no other scenario starts from this home |
| updating a pre-v1.3 layout: settings.json becomes a real file | settings.json left as a link into the clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| updating a pre-v1.3 layout: iTerm2 stops loading its preferences from the clone | iTerm2 left loading preferences from the clone | keep | one group of checks of this install scenario; no other scenario starts from this home |
| updating a pre-v1.3 layout: --check passes, the clone is unchanged, no .pre-link file | --check failing after updating the old layout | keep | one group of checks of this install scenario; no other scenario starts from this home |
| updating a pre-v1.3 layout: a second run with no flags passes the same checks | a second run undoing the update | keep | one group of checks of this install scenario; no other scenario starts from this home |
| sep22: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| python3 and tmux missing: install.sh stops, names both with their install commands, changes nothing | install.sh half-installing without python3 and tmux, or not saying how to get them | keep | one group of checks of this install scenario; no other scenario starts from this home |
| tmux missing with --terminal: install.sh stops, names it, changes nothing | --terminal half-installing without tmux | keep | one group of checks of this install scenario; no other scenario starts from this home |
| stock PATH: the install works and prints the claude mcp add command while claude is absent | the install needing more than a stock PATH, or failing while claude is absent | keep | one group of checks of this install scenario; no other scenario starts from this home |
| stock PATH: a rerun with claude present works | a rerun failing once claude is there | keep | one group of checks of this install scenario; no other scenario starts from this home |
| stock PATH: --check passes, the clone is unchanged, no .pre-link file | --check failing on the stock PATH | keep | one group of checks of this install scenario; no other scenario starts from this home |
| stock: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |
| your own files: install.sh succeeds and says it kept your agent and skill | your same-name agent or skill replaced silently | keep | one group of checks of this install scenario; no other scenario starts from this home |
| your own files: agent, skill, command, hook and settings.json stay byte-identical | any of your five files changed | keep | one group of checks of this install scenario; no other scenario starts from this home |
| your own files: the repo's other agents and skills are installed next to yours | the repo's other agents and skills not installed beside yours | keep | one group of checks of this install scenario; no other scenario starts from this home |
| your own files: an untracked file with a personal path is a warning naming it, not a failure | --check failing on your untracked file with a home path (past error 1e) | keep | replays past error 1e; one group of checks of this install scenario; no other scenario starts from this home |
| your own files: --check passes, the clone is unchanged, no .pre-link file | --check failing with your files in place | keep | one group of checks of this install scenario; no other scenario starts from this home |
| theirs: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | one group of checks of this install scenario; no other scenario starts from this home |

before 112, after 107

## user-settings

your own settings, agents, skills and CLAUDE.md survive an install.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| a skill of yours with the same name stays as it is when --agent-clash is not given | your same-name skill replaced without --agent-clash | keep | one group of checks of this install scenario; no other scenario starts from this home |

7 more tests carry `feature:user-settings` and are listed under their first tag.

before 1, after 1

## updates

updating an older install: old tags, moved clones, dirty clones.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| plain ./install.sh keeps every choice made at the first install | a plain rerun resetting the choices of the first install | keep | one group of checks of this install scenario; no other scenario starts from this home |

44 more tests carry `feature:updates` and are listed under their first tag.

before 1, after 1

## install-check

install.sh --check reports each item as PASS, WARN, SKIP or FAIL.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| --check names a leftover .pre-link backup inside skills and agents | --check missing leftovers nested in skills and agents | keep | one group of checks of this install scenario; no other scenario starts from this home |

22 more tests carry `feature:install-check` and are listed under their first tag.

before 1, after 1

## installed-text

no installed file names the author's repos or projects.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| no installed file names the author's projects or says to push the config repo | an installed file naming the author's projects | keep | what installs into every user's home; a slip here ships to all of them |
| settings.json is valid JSON | a settings.json Claude Code cannot read | keep | what installs into every user's home; a slip here ships to all of them |
| no tracked installed file holds a personal home path | a tracked file holding a personal home path | keep | what installs into every user's home; a slip here ships to all of them |
| a tracked file holding a personal home path fails the check and is named | the path check passing a tracked file that holds one | keep | what installs into every user's home; a slip here ships to all of them |

before 4, after 4

## run-agent

run-agent starts, schedules, revives and hands off agent runs.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| the real claude knows every option a launch passes to it | a launch passing claude an option the real one does not have | keep | the only comparison of the claude-cli stand-in with the real tool |
| the real claude exits with an error for an option it does not know | the real claude accepting unknown options silently | keep | the only comparison of the claude-cli stand-in with the real tool |
| an agent asking for a split is told it is ignored and gets its own pane | an agent's split request opening a pane beside the user | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| an agent asking for several launches at once is refused | an agent starting several runs at once | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| a caller under claude --agent is recognised as that agent | a caller under claude --agent taken for a person | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| a caller marked as human is not taken for an agent | a person taken for an agent | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| an agent's split launch in tmux replaces its pane, with no new window or pane | an agent's launch opening a new window or pane | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| a run scheduled by an agent is marked as such and loses its split target | an agent's scheduled run keeping its split target | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| an agent's run with no pane left waits, opening no window, session or claude | an agent's run with no pane opening a window on its own | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| a waiting run passes --health, and neither --revive nor an agent's call starts it | a waiting run started by --revive or by an agent | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| the next run-agent call by a person starts the waiting run in a new window | a waiting run never started when the person returns | keep | what an agent may do to the user's tmux; no other test calls run-agent as an agent |
| /run-agent planner with an existing absolute folder prints the cd line | an absolute folder not turned into a cd line | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent -C takes a relative folder; a worker line carries the subagent caps | -C with a relative folder misread, or the worker caps lost | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent --cwd= takes a folder with a space, with a model | --cwd= with a space in the folder split in two | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent --cwd tilde means the home folder | --cwd ~ not meaning the home folder | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent a bare folder name means the sibling of the git root | a bare folder name not found as the git root's sibling | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent a folder under the current one wins over the sibling | the sibling chosen over a folder under the current one | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent a bare folder name found nowhere says where it looked | a folder found nowhere failing without saying where it looked | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent a missing absolute folder is refused and not created | a missing absolute folder created | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent a missing folder under the home folder is refused and not created | a missing folder under the home created | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent a file given as the folder is refused | a file accepted as the folder | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent without a folder names the run after the git root | the run not named after the git root | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent without a folder, with a model | the model lost when no folder is given | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent planner without a prompt passes no prompt | the planner given a default prompt | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent planner without a prompt, in another folder | the planner given a default prompt in another folder | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent an extra word shows the usage text | an extra word run as part of the command | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent a typed --name wins over the folder name | a typed --name replaced by the folder name | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| /run-agent two folders show the usage text | two folders accepted | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| run-agent --resolve collapses . and .. in a folder path | --resolve leaving . and .. in the path | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| run-agent --resolve reports a missing folder | --resolve accepting a missing folder | keep | one way of naming the folder; a wrong folder starts the agent in the wrong repo |
| the scheduled line and --jobs name the agent's default model | the agent's default model not shown when none is typed | keep | a scheduled run fires hours later with nobody watching |
| a run scheduled from a stripped environment still starts the claude it recorded, with worker limits | a scheduled run starting another claude, or without worker limits, from a bare environment | keep | a scheduled run fires hours later with nobody watching |
| a claude that fails to start is logged with its error, which stays on screen | a claude that fails to start vanishing without its error | keep | a scheduled run fires hours later with nobody watching |
| --jobs reports a failed run once | a failed run reported on every --jobs | keep | a scheduled run fires hours later with nobody watching |
| --jobs lists a job file from an older version | an older version's job file crashing --jobs | keep | a scheduled run fires hours later with nobody watching |
| a job file from an older version still fires | an older version's job never firing | keep | a scheduled run fires hours later with nobody watching |
| four split launches give four new one-pane windows at once and leave your window alone | split launches landing in the user's window, or one after another | keep | the only tests of several launches in one call |
| the confirm session is started with a session id of its own | the confirm session resuming another session | keep | the only tests of several launches in one call |
| the confirm session is named after the agent, folder and time | the confirm session unnamed | keep | the only tests of several launches in one call |
| the confirm prompt carries the current time, the reset time and the time rules | the confirm prompt missing the time, reset or rules | keep | the only tests of several launches in one call |
| the confirm session's transcript is deleted when it exits | confirm transcripts piling up | keep | the only tests of several launches in one call |
| four planners in one call open a 2x2 window, one per folder, and leave your window alone | four planners not laid out 2x2, or in the user's window | keep | the only tests of several launches in one call |
| a group without 'confirm' starts all four at once, with no question | a group without confirm asking a question | keep | the only tests of several launches in one call |
| a group with 'confirm' opens only the confirm, alone in a new window | a group with confirm starting before the answer | keep | the only tests of several launches in one call |
| saying Yes fills the confirm's own window with four panes | Yes not filling the confirm's window with the four panes | keep | the only tests of several launches in one call |
| a test run inside a claude tmux pane leaves that pane alone | a test run replacing the claude pane it runs in | keep | keeps the suite from touching the session of whoever runs it |
| without test mode the same run replaces the pane, so the guard is what protects it | the guard test passing because nothing would replace the pane anyway | keep | keeps the suite from touching the session of whoever runs it |
| in test mode a pane on someone else's tmux server is not replaced | a test replacing a pane on the user's tmux server | keep | keeps the suite from touching the session of whoever runs it |
| in test mode no window is opened on someone else's tmux server | a test opening a window on the user's tmux server | keep | keeps the suite from touching the session of whoever runs it |
| in test mode a socket named like the default server is refused | a test socket standing in for the default server | keep | keeps the suite from touching the session of whoever runs it |
| handoff prints the note, the commit and the relaunch | handoff not printing the note, commit and relaunch | keep | handoff runs at the usage limit, when nothing can be retried |
| the handoff note has a timed heading, the text given, the dirty files and the relaunch | the note missing its time, text, dirty files or relaunch | keep | handoff runs at the usage limit, when nothing can be retried |
| handoff commits the work and leaves a clean tree without plans/ | work left uncommitted, or plans/ committed | keep | handoff runs at the usage limit, when nothing can be retried |
| the handoff relaunch is listed by --jobs | the relaunch not scheduled | keep | handoff runs at the usage limit, when nothing can be retried |
| handoff outside tmux still writes note and commit and says nothing was scheduled | handoff failing outside tmux | keep | handoff runs at the usage limit, when nothing can be retried |
| handoff with no reset from the API still schedules, notes and commits | handoff failing when the API gives no reset | keep | handoff runs at the usage limit, when nothing can be retried |
| handoff with no text on a clean tree writes only heading, dirty line and relaunch | an empty handoff writing noise | keep | handoff runs at the usage limit, when nothing can be retried |
| handoff outside a git repository writes the note and says there is no git | handoff failing outside a git repository | keep | handoff runs at the usage limit, when nothing can be retried |
| three handoffs at the same instant get three job ids, each for its own folder | simultaneous handoffs sharing a job id (past error 4) | keep | replays past error 4; handoff runs at the usage limit, when nothing can be retried |
| a handoff keeps plans/ out of the commit even when git does not ignore it | plans/ committed when git does not ignore it | keep | handoff runs at the usage limit, when nothing can be retried |
| a live usage answer is cached in the state folder | a live reset not cached | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| /run-agent after window with the usage API unreachable: now + 5 h, assumed, cache not used | a stale cached reset used for 'after window' when the API is unreachable | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| /run-agent after window with the usage API at 429: now + 5 h, assumed | the same at HTTP 429 | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| --window-reset with no live answer is now + 5 h, assumed, ignoring the cache | --window-reset using the cache | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| --window-reset live is the API reset rounded up to a whole second | a reset not rounded up, so a run fires before the window opens | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| /run-agent two hours before the window uses the cached reset when the API says 429 | the cached reset not used for a time counted back from the window | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| /run-agent at 9pm with the API at 429 shows the reset as cached | the reset not marked as cached | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| /run-agent never shows the 429 error text | the 429 error text shown to the user | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| a 429 answer is retried after 1 s and 3 s, then the cached reset is shown | no retry on 429, or a retry that waits too long | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| with no cache the reset is estimated from a running session | no estimate from a running session when there is no cache | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| --window-reset ignores the session estimate | --window-reset trusting a session estimate | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| /run-agent after window with only a session estimate: now + 5 h, assumed | 'after window' trusting a session estimate | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| an unexpired credentials file token is used and the Keychain is not read | the Keychain read when the file token is good | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| an expired file token falls back to the Keychain item | an expired file token used although the Keychain has one | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| with no credentials file the Keychain token is used | no token found when only the Keychain has one | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| an expired file token is still used when the Keychain cannot be read | no token at all when the Keychain cannot be read | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| with neither a file nor a Keychain item there is no token | a token invented when there is none | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| the usage API call verifies TLS with /etc/ssl/cert.pem when present | the usage call no longer naming the system certificate file | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| with only old sessions the reset is now + 5 h, assumed | old sessions taken for an open window | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| with nothing known the reset is now + 5 h, assumed | a crash when nothing is known about the window | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| /run-agent two hours before the window with nothing known still schedules from the assumed window | a time counted back from the window refused when nothing is known | keep | one source of the reset time or token; a wrong reset fires a run into a spent window |
| --jobs marks a run whose runner died as dead | a dead runner shown as sleeping | keep | what happens to a pending run after a crash, sleep or update |
| --revive silently gives a future run a new runner and leaves a live one alone | --revive doubling a live runner or missing a dead one | keep | what happens to a pending run after a crash, sleep or update |
| --revive forgets the pane when the tmux server is a new one | a revived run aimed at a pane of an old tmux server | keep | what happens to a pending run after a crash, sleep or update |
| --revive skips and logs an overdue run without starting claude | an overdue run started late by --revive | keep | what happens to a pending run after a crash, sleep or update |
| a pending run shows as sleeping and its process is the fixed wait loop | the runner being anything but the fixed wait loop | keep | what happens to a pending run after a crash, sleep or update |
| rewriting runner.sh while a run sleeps does not break it | an update to runner.sh breaking runs already asleep | keep | what happens to a pending run after a crash, sleep or update |
| a runner that errors is shown by --jobs and --health, and cancel removes its log | a runner error hidden from --jobs and --health | keep | what happens to a pending run after a crash, sleep or update |
| a run that wakes late by less than an hour fires at once and is logged as late | a run that wakes a little late dropped | keep | what happens to a pending run after a crash, sleep or update |
| a run that wakes more than an hour late is skipped and does not start claude | a run that wakes hours late still starting claude | keep | what happens to a pending run after a crash, sleep or update |
| scheduling with the clone's path, piped to tail, needs no permission | a permission prompt for scheduling by the clone's path | keep | one permission rule or store guard; no other test checks it |
| cd, then scheduling and listing through the installed script, needs no permission | a permission prompt for cd then the installed script | keep | one permission rule or store guard; no other test checks it |
| in a mixed command only the parts that are not run-agent's ask for permission | the rules allowing the non-run-agent part of a mixed command | keep | one permission rule or store guard; no other test checks it |
| bash on a run-agent script and both forms of the shell command need no permission | a permission prompt for bash on a run-agent script | keep | one permission rule or store guard; no other test checks it |
| something put in front of run-agent still asks for permission | a command put in front of run-agent allowed | keep | one permission rule or store guard; no other test checks it |
| settings.json holds the six run-agent rules and none that starts with a wildcard | a run-agent rule missing from settings.json, or one starting with a wildcard | keep | one permission rule or store guard; no other test checks it |
| --clean removes files older than 30 days and keeps newer ones | --clean deleting new files or keeping old ones | keep | one permission rule or store guard; no other test checks it |
| --jobs warns when the state folder passes 50 MB | the state folder growing unnoticed | keep | one permission rule or store guard; no other test checks it |
| there is no runner.log and nothing writes one | a runner.log growing without bound | keep | one permission rule or store guard; no other test checks it |
| a dry run of two launches lists both and the one window they share | a dry run of two launches hiding one | keep | one permission rule or store guard; no other test checks it |
| several launches at once cannot be scheduled | several launches scheduled as one | keep | one permission rule or store guard; no other test checks it |
| a + inside a quoted prompt does not split the launch | a + inside a prompt splitting the launch | keep | one permission rule or store guard; no other test checks it |
| twelve runs scheduled at the same instant each get their own id and job | runs scheduled at the same instant sharing an id (past error 4) | keep | replays past error 4; one permission rule or store guard; no other test checks it |
| in test mode --jobs refuses the real job store | a test's --jobs reading the real job store | merge | into “in test mode --jobs, --health, --cancel, --revive, --clean and scheduling each refuse the real job store”: six commands through one guard, one line each |
| in test mode --health refuses the real job store | a test's --health reading the real job store | merge | into “in test mode --jobs, --health, --cancel, --revive, --clean and scheduling each refuse the real job store”: six commands through one guard, one line each |
| in test mode --cancel refuses the real job store | a test's --cancel cancelling real jobs | merge | into “in test mode --jobs, --health, --cancel, --revive, --clean and scheduling each refuse the real job store”: six commands through one guard, one line each |
| in test mode --revive refuses the real job store | a test's --revive reviving real jobs | merge | into “in test mode --jobs, --health, --cancel, --revive, --clean and scheduling each refuse the real job store”: six commands through one guard, one line each |
| in test mode --clean refuses the real job store | a test's --clean deleting real files | merge | into “in test mode --jobs, --health, --cancel, --revive, --clean and scheduling each refuse the real job store”: six commands through one guard, one line each |
| in test mode scheduling refuses the real job store | a test scheduling into the real job store | merge | into “in test mode --jobs, --health, --cancel, --revive, --clean and scheduling each refuse the real job store”: six commands through one guard, one line each |
| in test mode a job store under the home .claude folder is refused | a test using a job store under ~/.claude | keep | one permission rule or store guard; no other test checks it |
| in test mode the scripts cannot see a parent claude process | a test seeing the claude session it runs in | keep | one permission rule or store guard; no other test checks it |
| scheduling prints one line, writes the job and --jobs lists it | scheduling failing on BSD date (past error 1f), or the job not listed | keep | replays past error 1f; the scheduling path end to end in a private tmux server |
| a scheduled run fires into its pane, is logged with its due time and leaves the list | a due run not firing into its pane, or staying in the list | keep | the scheduling path end to end in a private tmux server |
| --cancel removes the only pending run, stops its runner and logs it | --cancel leaving the runner alive | keep | the scheduling path end to end in a private tmux server |
| with two runs pending --cancel asks which, and --cancel <id> removes each | --cancel guessing between two runs | keep | the scheduling path end to end in a private tmux server |
| a reset later than 'until' is skipped, logged and nothing is scheduled | a run scheduled past its 'until' | keep | the scheduling path end to end in a private tmux server |
| the runner never asks for the reset time when it fires | the runner asking the API at fire time | keep | the scheduling path end to end in a private tmux server |
| a window run fires at its stored time although the API moved on, until 60 s later | a window run moved when the API changes its mind (past error 3) | keep | replays past error 3; the scheduling path end to end in a private tmux server |
| a window run fires at its stored time although the API moved on, until 6 h later | the same with a long 'until' | keep | the scheduling path end to end in a private tmux server |
| with the usage API unreachable a window run is set 5 h ahead and shown as assumed | a window run not scheduled when the API is down | keep | the scheduling path end to end in a private tmux server |
| --need-tmux outside tmux schedules nothing and says how to do it by hand | --need-tmux scheduling outside tmux | keep | the scheduling path end to end in a private tmux server |
| --need-tmux with the usage API down still schedules the run | --need-tmux failing when the API is down | keep | the scheduling path end to end in a private tmux server |
| --need-tmux ends with the Relaunch line when it schedules | the Relaunch line missing | keep | the scheduling path end to end in a private tmux server |
| --dry-run shows command, folder, time and reset and schedules nothing | --dry-run scheduling something | keep | the scheduling path end to end in a private tmux server |
| a run whose pane is gone fires in a new window | a run lost when its pane is gone | keep | the scheduling path end to end in a private tmux server |
| a run whose tmux server is gone fires in a new session | a run lost when its tmux server is gone | keep | the scheduling path end to end in a private tmux server |
| an unclear word gets one question, with no guessed reading | an unclear word guessed at, or asked about twice | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| answering 'Drop it' moves on to the confirm question | 'Drop it' not moving on | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| answering 'Part of the prompt' puts the word in the prompt | 'Part of the prompt' dropping the word | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| answering No changes nothing | No changing the launch | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| without 'confirm', dropping the unclear word schedules at once | a second question after the word is dropped | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| after three unusable answers nothing changes and you are told to type it by hand | an endless loop on unusable answers | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| with no agent named, the question is which agent | usage printed when no agent is named | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| a prompt alone asks which agent instead of printing usage | usage printed for a prompt alone | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| the agent answer leads to the confirm question | the agent answer not leading to the confirm | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| without 'confirm', the agent answer schedules at once | a second question after the agent is answered | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| 'tomorrow at 1am' with confirm asks one Schedule? question | more than one question for a clear time with confirm | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| 'two hours before the window' schedules without a question, and --jobs shows how the time was worked out | a question asked for a time the parser can work out | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| time words the parser cannot read go to the model to resolve, with no question to you | the user asked about time words the model can resolve | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| the resolved time schedules at once | the resolved time not scheduled | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| with confirm, the resolved time replaces the old words in the Schedule? question | the old words shown in the Schedule? question | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| answering Yes makes the script schedule the run itself | Yes leaving the scheduling to the model | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| answers after the run is scheduled are ignored | a late answer scheduling a second run | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| with no model typed the confirm question names the default | the default model not named in the confirm | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| a typed model is shown as typed, not as a default | a typed model shown as a default | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| a run aimed at a folder that does not exist asks before creating it | a missing folder created without asking | keep | one turn of the question loop; a wrong turn schedules what the user did not ask for |
| 'split' after a launch asks for a split | 'split' read as part of the prompt | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| 'new window' after a launch asks for a new window | 'new window' read as part of the prompt | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| 'after window' is read as a time, not as a window target | 'after window' read as a window target | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| the run-agent shell command's dry run prints command, folder and time | the shell command's dry run missing a part | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| the run-agent shell command passes --jobs and --next through as flags | --jobs and --next taken for a prompt | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| the next step is three lines: a short sentence, the /run-agent line and the claude line | the next-step lines changing shape | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| the next step for a phone evaluation says it runs on your phone | the phone evaluation not said to run on the phone | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| the next worker lines carry no model or effort from the running session | the next worker inheriting this session's model | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| the next evaluator lines carry no model or effort from the running session | the next evaluator inheriting this session's model | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| the next planner lines carry no model or effort from the running session | the next planner inheriting this session's model | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| the next helper lines carry no model or effort from the running session | the next helper inheriting this session's model | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| typing /run-agent is answered by the script, with no model turn | /run-agent costing a model turn | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| /run-agent jobs answers with the job list | /run-agent jobs not listing | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| /run-agent outside tmux answers with the line to type | /run-agent outside tmux failing with no line to type | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| /run-agent typed inside an agent session counts as the person's, not the agent's | a person's /run-agent inside an agent session refused as the agent's | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| settings.json runs the /run-agent hook with at least 60 s to answer | the /run-agent hook timing out | keep | where a launch goes and what the next-step lines say; agents print those lines verbatim |
| /run-agent time: at 9pm | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: at 9pm and --at 9pm”: two spellings, one answer |
| /run-agent time: --at 9pm | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: at 9pm and --at 9pm”: two spellings, one answer |
| /run-agent time: at 9:30pm | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: at 21:40 | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: at 2140 | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: at 9 (bare hour, next occurrence = 9 PM) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: at 5 (bare hour, 5 PM passed -> 5 AM) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: at 5 pm (passed -> tomorrow) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: in 2h | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: in 2h and --in 2h”: two spellings, one answer |
| /run-agent time: --in 2h | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: in 2h and --in 2h”: two spellings, one answer |
| /run-agent time: in 90m | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: in 1h30 | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: in 2 hours | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: in 45 min | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: after window | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: after window, after the window, next window, when the window resets, after reset and --after window all mean the reset”: six phrasings, one answer |
| /run-agent time: after the window | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: after window, after the window, next window, when the window resets, after reset and --after window all mean the reset”: six phrasings, one answer |
| /run-agent time: next window | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: after window, after the window, next window, when the window resets, after reset and --after window all mean the reset”: six phrasings, one answer |
| /run-agent time: when the window resets | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: after window, after the window, next window, when the window resets, after reset and --after window all mean the reset”: six phrasings, one answer |
| /run-agent time: after reset | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: after window, after the window, next window, when the window resets, after reset and --after window all mean the reset”: six phrasings, one answer |
| /run-agent time: --after window | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: after window, after the window, next window, when the window resets, after reset and --after window all mean the reset”: six phrasings, one answer |
| /run-agent time: after window until 11pm | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: until without a window phrase -> unsure | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: unparseable after at -> unsure | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: in <dir> still a directory | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: dir + at 9pm | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: dry with model, effort, at | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: dry run alone fetches the reset | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: dry run and --dry-run alone fetch the reset”: two spellings, one answer |
| /run-agent time: --dry-run | this time phrase read as the wrong time, or not read | merge | into “/run-agent time: dry run and --dry-run alone fetch the reset”: two spellings, one answer |
| /run-agent time: 'tomorrow at 1am' with a model and effort is the next calendar day | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: 'two hours before the window' counts back from the reset | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: '1 hr before the current window' counts back from the reset | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: '2 h after the window resets' counts on from the reset | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: '30 min before window ends' counts back from the reset | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: 1 hr before 9pm | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: 2 hours after 9pm | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: tomorrow (default 9 AM) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: tomorrow 7am | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: at 1am tomorrow | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: 3pm tomorrow | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: tonight (default 7 PM) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: tonight at 9 (PM) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: this evening (default 7 PM) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: today at 9pm | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: noon (next = tomorrow) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: at midnight | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: friday at 3pm (tomorrow is Friday) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: monday (next Monday, default 9 AM) | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: next thursday = a week ahead | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: in 2 hours 10 min | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: in an hour | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: today alone -> unsure | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: tomorrow at 25pm -> unsure | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: today at 5pm (already past) -> unsure | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| /run-agent time: 3 hours before the window (already past) -> at_error | this time phrase read as the wrong time, or not read | keep | its own phrase with its own expected time; no other test parses this input |
| a launch from tmux starts claude in the chosen folder, spaces and all | claude started in the wrong folder, or a spaced path split | keep | the launch itself, in a real tmux pane |
| the session name reaches claude as one argument | the session name split into several arguments | keep | the launch itself, in a real tmux pane |
| when claude exits a shell is left in the pane | the pane closing when claude exits | keep | the launch itself, in a real tmux pane |
| a planner launch carries no subagent limits | a planner limited like a worker | keep | the launch itself, in a real tmux pane |
| a worker launch carries sonnet subagents, 3 at a time, depth 1, and the shell left behind does not keep them | a worker without its subagent limits, or the limits leaking into the shell | keep | the launch itself, in a real tmux pane |
| outside tmux the worker line to type carries the subagent limits | the typed worker line missing the limits | keep | the launch itself, in a real tmux pane |
| /run-agent log: key=value, spaced =, commas | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: key=value, spaced =, commas, confirm | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: effort =medium | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: em dashes | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: single dashes | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: bare model + '<effort> effort' | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: model+effort | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: commas everywhere | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: confirm before em-dash flags | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: curly quotes | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: claude --agent evaluator '.' | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent log: newline inside the prompt | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: haiku usage error on 'model=fable effort =medium' | this typed form parsed into the wrong launch | delete | same input and expected answer as “log: effort =medium” |
| /run-agent sessions: haiku usage error on em-dash flags | this typed form parsed into the wrong launch | delete | same input and expected answer as “log: em dashes” |
| /run-agent sessions: haiku 'not run' on single-dash flags | this typed form parsed into the wrong launch | delete | same input and expected answer as “log: single dashes” |
| /run-agent sessions: haiku dropped 'low effort' | this typed form parsed into the wrong launch | delete | same input and expected answer as “log: bare model + '<effort> effort'” |
| /run-agent sessions: haiku 'could not parse' bare model + em-dash effort | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: haiku dry run | this typed form parsed into the wrong launch | delete | same input as “time: dry with model, effort, at” |
| /run-agent sessions: full claude command with em-dash flags | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: full claude command, capital Confirm | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: full claude command, trailing dot | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: straight open quote, curly close | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: planner prompt, straight open, curly close | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: confirm before the curly prompt | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: confirm after the curly prompt | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: --confirm flag | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: newline inside a curly prompt | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: 'model fable, effort medium' words | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: model=opus, effort=medium | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: 'using opus' | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: flag before the agent | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: stray words -> unsure | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: yolo | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent sessions: bare agent 'planner' (no default prompt) | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent typo: fabel -> fable | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent typo: efort lo -> effort low | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent typo: wroker -> worker | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent typo: zzqx -> unsure | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent typo: lwo (tie low/two-ish) -> unsure | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: with opus yolo resume | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: just do it is three unplaceable words | this typed form parsed into the wrong launch | merge | into “/run-agent words: just do it, force, go, yolo-run, no confirm and a trailing ! cannot be placed and are asked about”: six inputs through one rule (a word with no place is asked about) |
| /run-agent words: confirm inside the prompt is prompt | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: old force words inside the prompt are prompt | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: worker! -> the bare ! is unplaceable | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: trailing ! is unplaceable | this typed form parsed into the wrong launch | merge | into “/run-agent words: just do it, force, go, yolo-run, no confirm and a trailing ! cannot be placed and are asked about”: six inputs through one rule (a word with no place is asked about) |
| /run-agent words: force alone is unplaceable | this typed form parsed into the wrong launch | merge | into “/run-agent words: just do it, force, go, yolo-run, no confirm and a trailing ! cannot be placed and are asked about”: six inputs through one rule (a word with no place is asked about) |
| /run-agent words: go alone is unplaceable | this typed form parsed into the wrong launch | merge | into “/run-agent words: just do it, force, go, yolo-run, no confirm and a trailing ! cannot be placed and are asked about”: six inputs through one rule (a word with no place is asked about) |
| /run-agent words: yolo-run is unplaceable | this typed form parsed into the wrong launch | merge | into “/run-agent words: just do it, force, go, yolo-run, no confirm and a trailing ! cannot be placed and are asked about”: six inputs through one rule (a word with no place is asked about) |
| /run-agent words: no confirm = two unplaceable words | this typed form parsed into the wrong launch | merge | into “/run-agent words: just do it, force, go, yolo-run, no confirm and a trailing ! cannot be placed and are asked about”: six inputs through one rule (a word with no place is asked about) |
| /run-agent words: now = at once, no schedule | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: confirm = confirm:1 | this typed form parsed into the wrong launch | merge | into “/run-agent words: confirm and --confirm both ask before the run”: two spellings, one answer |
| /run-agent words: --confirm = confirm:1 | this typed form parsed into the wrong launch | merge | into “/run-agent words: confirm and --confirm both ask before the run”: two spellings, one answer |
| /run-agent words: --force / -f fall where unknown flags fall | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: --parse has no force key | this typed form parsed into the wrong launch | delete | the confirm test compares the whole answer, so a force key already fails it |
| /run-agent words: a path under the home folder | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: --name given | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: two directories -> error | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |
| /run-agent words: planner has no default prompt | this typed form parsed into the wrong launch | keep | a form somebody typed, taken from the logs; no other test parses this input |

before 280, after 255

## usage-api

reading real usage limits and reset times.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| macOS: parse.py reads the login token from the Keychain through the real security | the Keychain item name or the security call being wrong on a real Mac | keep | the only comparison of the security stand-in with the real tool |
| the real usage API answers a made-up token with HTTP 401 over verified TLS | the usage request failing TLS or not reaching the real API | keep | replays past error 2; the only test against the real usage API and Keychain |
| the usage request trusts the system's certificates when Python itself finds none | the request failing where Python finds no certificates of its own | keep | the only test against the real usage API and Keychain |
| the window reset shown is the five-hour window's, not the weekly one | the weekly reset shown in place of the five-hour one | keep | the only test against the real usage API and Keychain |

before 4, after 4

## evaluator-tools

window tools an evaluator run opens, places, shows and closes.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| live: win.sh me answers | win.sh me failing with the real tools | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| live: registering the items opens nothing before the answer | a window opening before the user says they are ready | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| live: the file item opens in a separate Firefox after the answer, with one window on screen | the real Firefox not opening, or opening inside the user's own Firefox | keep | the only comparison of the win-sh stand-in with the real tool |
| live: the terminal item is shown as a page and the first item's Firefox and profile are gone | the previous item's Firefox or profile left behind | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| live: the terminal page holds the session's text with its colours kept | the terminal page losing text or colours with the real tmux | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| live: the web item is shown as itself and the terminal page's Firefox is gone | a web item shown as a snapshot, or the terminal page's Firefox left open | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| live: ending the run leaves no Firefox or profile of its own | a Firefox or profile of the run left after it ends | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| live: your own Firefox is as it was | the user's own Firefox closed or changed by the run | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| live: every Firefox and iTerm2 window is where it was | the user's windows moved by the run | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| live: the history, flash measurement and picture path answer as on a Mac | history, flash and picture-path answers failing on a real Mac | keep | the only run with the real Firefox and tmux; the quick tier uses stand-ins |
| the real Firefox writes prefs.js into a fresh profile, stays running and ends on TERM | the real Firefox no longer writing prefs.js, staying up or ending on TERM as win.sh expects | keep | the only comparison of the firefox stand-in with the real tool |
| the real tmux captures a pane's text with its colours | the real tmux capturing colours differently from the stand-in | keep | the only comparison of the tmux stand-in with the real tool |
| the real tmux says no to has-session for a name that does not exist | the real tmux answering has-session differently from the stand-in | keep | the only comparison of the tmux stand-in with the real tool |
| macOS: the real open fails with a message for a page that does not exist | the real open not failing the way the stand-in does | keep | the only comparison of the open stand-in with the real tool |
| the shared evaluator tools are in local-tools/common | a shared tool missing from local-tools/common | keep | a misplaced or unparseable tool breaks every install of that OS |
| the Mac-only page makers are in local-tools/macos | a Mac page maker missing from local-tools/macos | keep | a misplaced or unparseable tool breaks every install of that OS |
| WSL and macOS each have the five window commands, executable | an OS lacking one of the five window commands, or one not executable | keep | a misplaced or unparseable tool breaks every install of that OS |
| no PowerShell file sits in the common or macOS tool folders | a PowerShell file landing in the common or macOS folder | keep | a misplaced or unparseable tool breaks every install of that OS |
| no tool name exists both in common and in an OS folder, so links cannot collide | one tool name in two folders, so install links collide | keep | a misplaced or unparseable tool breaks every install of that OS |
| the old top-level wsl/local-tools folder is gone | nothing today: the folder was moved once and nothing recreates it | delete | pins a move that is finished; the layout tests beside it already need local-tools/wsl |
| every evaluator shell script parses | a shell script with a syntax error | keep | a misplaced or unparseable tool breaks every install of that OS |
| the Mac and shared scripts parse under bash 3.2 | a bash 4 construct in a script a stock Mac runs | keep | a misplaced or unparseable tool breaks every install of that OS |
| the macOS scripts call no command a stock Mac lacks | a Mac script calling a command a stock Mac lacks | keep | a misplaced or unparseable tool breaks every install of that OS |
| the macOS tools open no iTerm tab, drive no other browser and need no screen permission | the Mac tools going back to iTerm tabs, another browser or screen capture | merge | into “the macOS tools and evshow.sh open no iTerm tab, drive no other browser, need no screen permission and rotate no modes”: one search for the removed ways of showing, over two sets of files |
| evshow.sh has no rotation between ways of showing | evshow.sh going back to rotating ways of showing | merge | into “the macOS tools and evshow.sh open no iTerm tab, drive no other browser, need no screen permission and rotate no modes”: one search for the removed ways of showing, over two sets of files |
| the evaluator asks no question about which way of showing to use | nothing in the tools: it greps the evaluator's prompt for words of a removed feature | delete | greps a prompt for words of a removed feature; no behaviour depends on it |
| every evaluator Python tool parses | a Python tool with a syntax error | keep | a misplaced or unparseable tool breaks every install of that OS |
| the Mac phone picture tool needs no Node, Playwright or Chromium | the Mac phone tool depending on Node or Chromium again | keep | a misplaced or unparseable tool breaks every install of that OS |
| registering a file item opens nothing yet and remembers the file | registering a file opening it at once, or forgetting it | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| registering a window without a title is refused | a window registered with no title | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| registering a file that does not exist says so | a missing file accepted | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| asking for a VS Code window says VS Code is retired | a VS Code request not refused with the reason | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| asking for a Windows Terminal window is refused | a Windows Terminal request accepted on a Mac | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| win.sh me names the tmux pane and no window geometry | win.sh me printing window geometry or no pane | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| opening a terminal item starts a tmux session and defers the window | a terminal item not starting its tmux session, or opening a window early | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| nothing is opened while items are only registered | anything opening while items are only registered | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| showing the first item starts its own Firefox on a fresh profile | the first item reusing the user's Firefox or an old profile | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| the shown Firefox profile has no default-browser, welcome or restore prompt | the shown Firefox asking default-browser, welcome or restore questions | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| showing an item takes no screenshot and does not use the default browser | a screenshot taken or the default browser used when showing | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| the next item closes the previous Firefox and deletes its profile | the previous Firefox or its profile left when the next item shows | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| a terminal item is shown as a page of the session's text with its colours kept | the terminal page losing the session's text or colours | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| a web item is shown as its own address and the terminal page's Firefox is closed | a web item shown as a copy, or the terminal page's Firefox left open | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| your own HTML file is shown as itself, in the only Firefox of the run | the user's HTML wrapped in another page, or a second Firefox started | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| closing the items ends their tmux session, Firefox and profiles and kills nothing of yours | closing leaving a session, Firefox or profile, or killing something of the user's | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| restoring the desktop on a Mac says nothing changed | restore claiming to change the desktop on a Mac | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| closing a window this session did not open is refused | closing a window the session did not open | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| showing an unknown item says no window matches | an unknown item shown silently | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| an unknown win.sh command is a usage error | an unknown command accepted | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| the Firefox path is the program inside the app | the Firefox path pointing at the app folder, not the program | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| without Firefox installed the page opens in your default browser and says why | no page at all when Firefox is not installed | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| closing a page that went to your browser leaves it there | closing a page that is in the user's own browser | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| without Firefox installed the Firefox path is open | the Firefox path wrong when Firefox is absent | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| a Firefox that exits at once is reported quickly and the page opens in your browser | a Firefox that dies at start waited on for 10 s, or no fallback | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| when neither Firefox nor your browser opens, the failure says why | a silent failure when nothing can open the page | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| a Firefox still running 10 seconds after its start counts as shown | a slow-starting Firefox reported as failed | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| a terminal item whose session is gone is not shown and says what tmux said | a dead tmux session shown as an empty page | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| screen capture on a Mac says it did not capture | screen capture pretending to work on a Mac | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| a whole run on the Mac tools shows two items one after the other and ends with no Firefox left | a whole run leaving a Firefox behind or showing items out of order | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| an answer other than Yes to the readiness question shows nothing | any answer but Yes opening a window | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| the page of a line range starts with the first line asked for | a line-range page starting at the wrong line | keep | one command or failure path of win.sh on a Mac; no other quick test reaches it |
| arming for the first question names the first item | arming not naming the first item | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| after the Yes answer the first item is shown in Firefox mode | the first item not shown after Yes | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| the time from question to window is logged | the question-to-window time not logged | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| the first item is opened by the watcher, not by the wait fallback | the watcher not firing, so the wait fallback opens the item | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| showing the first item arms the next one | the next item not armed | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| on a Mac no screenshot is named in the log | a screenshot named on a Mac | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| the window tool is asked to start the first item with no window sizes | window sizes passed to the Mac window tool | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| after the first answer the second item is shown and called the last | the second item not shown or not called the last | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| the second item replaces the first item's window | the second item opening beside the first | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| ending the run says nothing on the desktop changed | end claiming a desktop change | merge | into “ending the run closes the last item's window, says nothing on the desktop changed, and disarming succeeds”: three readings of the run's last two commands |
| ending the run closes the last item's window | the last window left open | merge | into “ending the run closes the last item's window, says nothing on the desktop changed, and disarming succeeds”: three readings of the run's last two commands |
| on a Mac the run never moves, measures or quits a window | the run moving, measuring or quitting a window | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| on a Mac the flash measurement says it is not measured | flash measured on a Mac | merge | into “on a Mac the flash measurement says it is not measured and the picture path says there is no picture”: two one-line answers of commands a Mac does not have |
| on a Mac asking for the picture path says there is no picture | a picture path given on a Mac | merge | into “on a Mac the flash measurement says it is not measured and the picture path says there is no picture”: two one-line answers of commands a Mac does not have |
| the history keeps both items and the time from answer to next question | history losing an item or the timing | keep | one step of the evaluator's show loop; a break here is a window that never opens |
| disarming after the run succeeds | disarm failing | merge | into “ending the run closes the last item's window, says nothing on the desktop changed, and disarming succeeds”: three readings of the run's last two commands |
| evshow.sh says it has no window tools on an unsupported system | a silent no-op on an unsupported system | keep | one step of the evaluator's show loop; a break here is a window that never opens |

before 77, after 71

## windows-install

install on Windows without WSL: copies where links fail, WSL-only parts skipped.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| windows: install.sh succeeds and copies what it cannot link | the install failing where links are refused, or not copying | keep | the only tests of the copy route used when links are refused |
| windows: the status line is installed; tmux setup and run-agent are skipped and named | the status line missing on Windows, or tmux setup or run-agent installed there, or skipped silently | keep | the only tests of the copy route used when links are refused |
| windows: --check accepts the copies | --check failing copies | keep | the only tests of the copy route used when links are refused |
| windows: a rerun succeeds and the clone is unchanged | a rerun treating its own copies as yours, or writing into the clone | keep | the only tests of the copy route used when links are refused |
| windows: a rerun after an update refreshes unedited copies and keeps edited ones | stale copies kept after an update, or your edited copy replaced | keep | replays past error windows-stale-copy; the only tests of the copy route used when links are refused |
| windows: installing into a home already in use keeps your agent, CLAUDE.md and setting | your agent, CLAUDE.md or setting lost on Windows | keep | the only tests of the copy route used when links are refused |
| windows: the whole scenario ran to its end with no failed check | the scenario stopping early or any of its checks failing | keep | the only tests of the copy route used when links are refused |
| windows: the test workflow runs the quick tier on Windows for every push to main and pull request | CI no longer running the quick tier on Windows (past error 6) | keep | replays past error 6; the only tests of the copy route used when links are refused |

before 8, after 8

## usage-guard

launch limits for worker sessions, and every settings hook with its script missing.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| usage-guard: its own suite passes | any case of the guard's own suite (Linux) | keep | a hook that errors blocks every tool call of every session |
| usage-guard: a worker's headless launch with no budget flags is blocked and says which to add | a worker's headless launch with no budget getting through | keep | a hook that errors blocks every tool call of every session |
| usage-guard: a worker's launch with both flags is allowed and told the day's count | a budgeted launch blocked, or the day's count not told | keep | a hook that errors blocks every tool call of every session |
| usage-guard: a command that only mentions claude -p is not a launch | a command that only mentions claude -p counted as a launch | keep | a hook that errors blocks every tool call of every session |
| usage-guard: your own sessions and other agents are left alone | the guard acting on the user's own sessions or other agents | keep | a hook that errors blocks every tool call of every session |
| hooks: settings.json hooks only the events the tests below cover | a new hook event added with no test of its missing script | keep | a hook that errors blocks every tool call of every session |
| hooks: UserPromptExpansion with the run-agent script missing exits 0 and says nothing | the /run-agent hook erroring when its script is gone | keep | a hook that errors blocks every tool call of every session |
| hooks: PreToolUse with the guard missing blocks nothing and says once per session that it is off | PreToolUse blocking or nagging when the guard is gone | keep | a hook that errors blocks every tool call of every session |
| hooks: PostToolUse with the guard missing exits 0 and says it is off | PostToolUse erroring when the guard is gone | merge | into “hooks: PostToolUse, SessionStart, SubagentStart and SubagentStop with the guard missing each exit 0 and say it is off”: four events through the same check; the failure names the event |
| hooks: SessionStart with the guard missing exits 0 and says it is off | SessionStart erroring when the guard is gone | merge | into “hooks: PostToolUse, SessionStart, SubagentStart and SubagentStop with the guard missing each exit 0 and say it is off”: four events through the same check; the failure names the event |
| hooks: SubagentStart with the guard missing exits 0 and says it is off | SubagentStart erroring when the guard is gone | merge | into “hooks: PostToolUse, SessionStart, SubagentStart and SubagentStop with the guard missing each exit 0 and say it is off”: four events through the same check; the failure names the event |
| hooks: SubagentStop with the guard missing exits 0 and says it is off | SubagentStop erroring when the guard is gone | merge | into “hooks: PostToolUse, SessionStart, SubagentStart and SubagentStop with the guard missing each exit 0 and say it is off”: four events through the same check; the failure names the event |

before 12, after 9

## report-writer

report-writer build and check scripts.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| a full build with the real card renderer draws a picture for every card | the real card renderer drawing no picture for a card | keep | the only comparison of the report-node stand-in with the real tool |
| a table too long for one card is split and every part keeps the header row | a split table losing its header row in the real renderer | keep | the only comparison of the report-node stand-in with the real tool |
| build reads each figure from the study files and prints it with its unit on the page | a figure printed that is not the study file's, or without its unit | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build looks for study files in the report folder's parent when --data is not given | study files not found in the parent folder | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build replaces a wrong derived figure and says so | a wrong derived figure left in the report | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build shows a negative signed change with a real minus sign | a negative change shown with a hyphen | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build refuses to read a figure from a data file the writer made inside the report folder | figures read from a file the writer made itself | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build refuses to read a figure from a file outside the data folder | figures read from outside the data folder | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build stops on a figure the numbers file does not have | a missing figure filled with nothing | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build stops on a digit typed into a table cell | a digit typed into a table cell accepted | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build stops on a table row with the wrong number of cells | a ragged table row accepted | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build stops on a split bar whose parts do not add up to its total | a split bar that does not add up accepted | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build stops on a side-by-side card label that holds a digit | a digit in a side-by-side label accepted | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build prints the checker's loops, findings and cost on the last line of the report | the checker's loops, findings and cost missing from the last line | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build turns a send-back note into its own page without a checker folder | a send-back note needing a checker folder | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build names the missing report or numbers file | a missing report or numbers file not named | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| a full build splits the report into screen-sized cards, counts words and writes one ledger line | cards not split by screen, words miscounted, or the ledger line doubled | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| build says so when the card renderer fails | a renderer failure passing silently | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| the card renderer is JavaScript node can parse | the card renderer not parsing under node | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| check passes the figure checks on a freshly built report | check failing a freshly built report | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| check fails a report whose figure no longer matches the study file | a figure that no longer matches its study file passing | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| check fails a number typed straight into the page or the prose | a number typed into the page or prose passing | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| check compares the deciding figures and state words with an expected file | the deciding figures or state words differing from the expected file | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| the golden report passes every check that does not need the study data | the golden report failing its own checks | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| check fails a report that copies sentences from the golden report | sentences copied from the golden report passing | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| the focus case is caught for its section that has no outline row | a section with no outline row passing | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| the slips case is caught for its four writing slips | the four writing slips passing | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| check fails a serious checker finding that was left open | an open serious finding passing | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| preflight is silent when everything a build needs is there | preflight complaining when all is there | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| preflight names the missing files and how to restore them | preflight not naming a missing file or how to restore it | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| preflight asks for Node.js when node is not on PATH | a missing node not reported | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| preflight passes on the install command for a missing browser library | the browser library's install command lost | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| checker usage totals the tokens and seconds of subagents started since the given time | subagent tokens and seconds miscounted | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |
| checker usage reports zero when no subagent ran, and needs a start time | a nonzero total with no subagent, or no start time accepted | keep | one rule of build, check or preflight; a report that breaks it misleads its reader |

before 34, after 34

## restore-sessions

restore-sessions skill scripts.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| the real tmux answers the pane questions restore-sessions asks | the real tmux pane answers differing from the restore-sessions stand-in | keep | the only comparison of the restore-tmux stand-in with the real tool |
| the real ps and pgrep list processes the way restore-sessions reads them | the real ps and pgrep output differing from what restore-sessions reads | keep | the only comparison of the restore-ps stand-in with the real tool |
| stop-time.sh reads the real journalctl or says why it cannot | stop-time.sh misreading the real journalctl | keep | the only comparison of the journalctl stand-in with the real tool |
| GNU date and touch read the times the restore-sessions stand-ins read | GNU date and touch reading times differently from the stand-ins | keep | the only comparison of the gnu-date stand-in with the real tool |
| find-sessions lists exactly the sessions the shutdown eval expects, oldest first | the wrong sessions, or the wrong order, after a shutdown | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| find-sessions marks the mid-task eval session as stopped mid-task | a session stopped mid-task not marked | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| find-sessions takes the hour before the stop and five seconds after, nothing outside | sessions outside the hour before the stop taken, or ones inside missed | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| find-sessions leaves out a session closed with /exit but keeps one resumed after it | a session closed with /exit restored, or one resumed after it dropped | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| find-sessions says mid-task for an unfinished tool call, tool result, thinking or API error only | mid-task claimed for a finished turn | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| find-sessions adds an idle session whose process file survived the stop | an idle session with a surviving process file missed | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| find-sessions leaves out a headless session's surviving process file | a headless session restored | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| find-sessions leaves out a process file whose process is still alive | a session that is still running restored twice | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| find-sessions explains a missing time, an unreadable time and a missing folder | a bad time or folder failing without a reason | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| stop-time formats a time the user gives and refuses one it cannot read | stop-time accepting a time it cannot read | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| stop-time reads the stop, this boot and the previous boot from the journal | the stop and boot times misread from the journal | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| stop-time says why when the journal fails or holds no previous boot | a journal failure with no reason given | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan with no tmux server opens new session 0 with a pet top-left and the sessions beside it | the first window laid out wrongly with no tmux server | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan reuses an idle shell, leaves a busy pane alone and never changes tmux | a busy pane reused, or tmux changed by plan | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan does not reuse a shell pane that has a program running under it | a shell with a program under it reused | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan opens a second window once the first holds a pet and three sessions | a fifth pane squeezed into the first window | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan leaves out headless, empty, temporary, older, vanished and already running sessions and says why | headless, empty, temporary, old, vanished or running sessions restored, or left out silently | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan treats a transcript written after this boot as already running | a transcript written after this boot restored again | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan applies the user's corrections: drop, keep and move | drop, keep and move corrections not applied | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan refuses a correction it cannot apply and exits 3 | a correction that cannot apply accepted | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| plan and apply say which input is missing | a missing input not named | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| verify passes a resumed pane with the right prompt, agent, mode and model | a correctly resumed pane failed | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| verify fails a pane that came back with a different agent | a pane back with another agent passed | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| verify fails a pane with no Claude prompt, typed input, or a trust question | a pane with no prompt, typed input or a trust question passed | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| verify fails a pane that came back in another mode or model | a pane back in another mode or model passed | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| verify fails a pane whose resume line is missing or was typed over, or whose session was not found | a missing or overtyped resume line passed | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| verify fails a pet pane that is not running the pet | a pet pane not running the pet passed | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |
| apply resumes each session with the model it was using | sessions resumed with the default model, not theirs | keep | one rule of find, plan, verify or apply; a miss loses or doubles a session after a crash |

before 32, after 32

## test-speedup

test-speedup skill measure script.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| baseline reads the count and slowest times from a real Maven run | baseline misreading a real Maven run | keep | the only comparison of the maven stand-in with the real tool |
| baseline reads the count and slowest examples from a real RSpec run | baseline misreading a real RSpec run | keep | the only comparison of the rspec stand-in with the real tool |
| baseline reads the count of every outcome from a real pytest run | baseline miscounting outcomes of a real pytest run | keep | the only comparison of the pytest stand-in with the real tool |
| detect names the runner from the project's files | the wrong runner named for a project | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| detect names pytest or gradle from any one of its project files | pytest or gradle missed by one of its files | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| detect says unknown and exits 3 in a folder with no test runner | a guess made in a folder with no runner | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| time reports the command, its seconds and its failing status | a failing command timed as a success | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| time without a command prints its usage | time with no command doing something | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| a second run is refused while one is in flight | two timed runs at once skewing each other | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| a lock left by a dead run is cleared and the command still runs | a dead run's lock blocking every later run | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| unlock removes the lock | unlock leaving the lock | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| baseline reports time, status, count and the slowest tests from one run | baseline missing time, status, count or the slowest tests | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| baseline lists the failures and returns the runner's status | baseline hiding failures or the runner's status | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| baseline reads the count and slowest times from Maven's XML reports | Maven's XML reports misread | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| run passes extra arguments to the runner and reports time and status | extra arguments dropped by run | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| an unknown command prints the list of commands | an unknown command failing silently | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| a refused second run leaves the first run's lock in place | a refused run deleting the first run's lock | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |
| a pytest baseline counts failed, skipped and expected-to-fail tests as well as passed | a pytest baseline counting passed tests only | keep | one command of measure.sh; a wrong time or count misleads the speed-up it reports |

before 18, after 18

## weekly-roundup

weekly-roundup gather, archive and charts.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| test_week_chart | the week chart drawn wrongly | keep | one rule of the roundup's numbers or colours |
| test_archive_chart_and_days_required | the archive chart drawn without its days | keep | one rule of the roundup's numbers or colours |
| test_first_run_one_entry | a first run writing more than one entry | keep | one rule of the roundup's numbers or colours |
| test_rerun_equals_single_run | a rerun doubling the entry | keep | one rule of the roundup's numbers or colours |
| test_rerun_drops_own_feature_links_keeps_other | a rerun dropping another machine's feature links | keep | one rule of the roundup's numbers or colours |
| test_dangling_feature_link_warns_and_drops | a dangling feature link kept | keep | one rule of the roundup's numbers or colours |
| test_same_hostname_different_person_errors | two people on one hostname merged | keep | one rule of the roundup's numbers or colours |
| test_two_hostnames_same_person_stay_two | one person's two machines merged | keep | one rule of the roundup's numbers or colours |
| test_legacy_entry_without_hostname_matched | an old entry without a hostname duplicated | keep | one rule of the roundup's numbers or colours |
| test_shared_project_keeps_other_machine | a shared project losing the other machine's part | keep | one rule of the roundup's numbers or colours |
| test_rewrite_lists_authored | the rewrite list missing authored projects | keep | one rule of the roundup's numbers or colours |
| test_days_shape_sums_and_boundaries | day totals not summing, or wrong at the boundaries | keep | one rule of the roundup's numbers or colours |
| test_days_two_people_and_shared_session_once | a shared session counted twice across two people | keep | one rule of the roundup's numbers or colours |
| test_legacy_pool_entry_without_days | an old pool entry without days crashing | keep | one rule of the roundup's numbers or colours |
| test_person_palettes_separated | two people's colours overlapping | keep | one rule of the roundup's numbers or colours |
| test_colors_stable_across_runs_and_joining | colours changing between runs or when someone joins | keep | one rule of the roundup's numbers or colours |
| test_mapped_color_reused_and_new_project_takes_free_accent | a mapped colour not reused, or a new project taking a used one | keep | one rule of the roundup's numbers or colours |
| test_thirteen_projects_cycle | a crash past twelve projects | keep | one rule of the roundup's numbers or colours |
| test_cache_reads_cost_less_on_a_model_with_a_cheaper_cache_rate | cache reads priced at the full rate | keep | one rule of the roundup's numbers or colours |
| test_a_reply_written_to_the_log_twice_while_streaming_is_counted_once | a streamed reply counted twice | keep | one rule of the roundup's numbers or colours |
| test_the_published_data_does_not_hold_what_you_asked_in_a_session | prompts published in the data | keep | one rule of the roundup's numbers or colours |

before 21, after 21

## defer-artifact

the defer-artifact mod.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| the Artifact tool is described as deferred and keeps the rest of its description | the Artifact description not deferred, or its text lost | keep | each is one behaviour of the mod |
| other tools are left as they were | other tools' descriptions changed | keep | each is one behaviour of the mod |
| the mod hooks only the description of the Artifact tool | the mod hooking more than the Artifact description | keep | each is one behaviour of the mod |
| if describing Artifact fails once, the mod falls back to the normal description | one failure breaking the description for good | keep | each is one behaviour of the mod |
| the mod has the manifest the installer looks for | the installer not finding the mod's manifest | keep | each is one behaviour of the mod |

before 5, after 5

## update-by-claude

Claude Code updates an install by following UPDATING.md.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| update: UPDATING.md's commands move the install to the latest release, not a pre-release | UPDATING.md's commands landing on a pre-release or not moving | keep | runs the commands UPDATING.md prints, as Claude would |
| update: the user's edits and own files are still there afterwards | the user's edits or files lost by the update | keep | runs the commands UPDATING.md prints, as Claude would |
| update: what the release added is linked and install.sh --check finds every link | new things unlinked after the update | keep | runs the commands UPDATING.md prints, as Claude would |

before 3, after 3

## statusline

status line output.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| statusline: it shows the project folder and the model, dropping a default version number | the folder or model missing, or a default version number shown | keep | one part of the line the user reads all day |
| statusline: the reasoning effort is drawn as a gauge beside the model | the effort gauge missing | keep | one part of the line the user reads all day |
| statusline: in a git folder it shows the branch, cut short past 20 characters | the branch missing or not cut at 20 characters | keep | one part of the line the user reads all day |
| statusline: the 5 hour usage always shows, the weekly figure only from 70 percent | the weekly figure shown too early, or the 5 hour one hidden | keep | one part of the line the user reads all day |
| statusline: usage turns red at 90 percent and not before | usage red too early or never | keep | one part of the line the user reads all day |
| statusline: before the first reply it shows the last usage it saw | an empty line before the first reply | keep | one part of the line the user reads all day |
| statusline: --preview lists 25 easter eggs for each theme and rejects another name | --preview accepting any theme name or miscounting eggs | keep | one part of the line the user reads all day |
| statusline: an ordinary session shows the plain mascot of its theme | the mascot of another theme shown | keep | one part of the line the user reads all day |
| statusline: a session that rolls an easter egg shows that egg in its theme | an easter egg from another theme shown | keep | one part of the line the user reads all day |
| statusline: while guard allow is in force it shows the unlock time in US Eastern | the unlock time shown in UTC | new | catches the planted fault statusline/unlock-time-utc, which no test caught before |

before 9, after 10

## agent-prompts

agent definitions name tools, options and agents that exist.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| each agent's frontmatter carries the file's name and a description | an agent file whose name or description is missing or wrong | keep | a renamed tool, option or file is otherwise found only in a live session |
| every file an agent reads from the claude-config folder is in the repo | an agent told to read a config file that is not in the repo | keep | a renamed tool, option or file is otherwise found only in a live session |
| every repo file an agent names by a relative path is there | an agent naming a repo file that is not there | keep | a renamed tool, option or file is otherwise found only in a live session |
| every installed script an agent runs comes from the repo | an agent running an installed script the repo does not ship | keep | a renamed tool, option or file is otherwise found only in a live session |
| every shell script an agent names ships for both macOS and WSL | a script an agent names shipping for one OS only | keep | a renamed tool, option or file is otherwise found only in a live session |
| every window command an agent calls is one the macOS window script handles | an agent calling a window command the macOS script lacks | keep | a renamed tool, option or file is otherwise found only in a live session |
| the window commands an agent calls are handled on WSL | an agent calling a window command the WSL script lacks | keep | a renamed tool, option or file is otherwise found only in a live session |
| every show command the evaluator calls is one evshow.sh handles | the evaluator calling a show command evshow.sh lacks | keep | a renamed tool, option or file is otherwise found only in a live session |
| every run-agent option an agent uses is one the script dispatches | an agent using a run-agent option the script does not dispatch | keep | a renamed tool, option or file is otherwise found only in a live session |
| every MCP tool an agent names is one its server offers | an agent naming an MCP tool its server does not offer | keep | a renamed tool, option or file is otherwise found only in a live session |
| the helper's wiki server path leads from its own file to the server | the helper's path to its wiki server being wrong | keep | a renamed tool, option or file is otherwise found only in a live session |
| every agent that another agent starts exists | an agent starting another agent that does not exist | keep | a renamed tool, option or file is otherwise found only in a live session |
| the planner can start the researcher it is told to use | the planner unable to start the researcher | keep | a renamed tool, option or file is otherwise found only in a live session |

before 13, after 13

## terminal-setup

iTerm2 and tmux terminal setup.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| macOS: --terminal with iTerm2 absent skips the profile and --check still passes | --terminal failing, or --check failing, on a Mac without iTerm2 | keep | replays past error 1d with the real iTerm2 |
| macOS: brew leaves iTerm2 in /Applications | the scenario not starting: iTerm2 not installed | merge | into “macOS: the update starts as it did on the real Mac: iTerm2 running on the clone's plist, its own write a local change, the pull deleting it”: six preconditions of one run; none is the behaviour under test |
| macOS: the September clone tracks the iTerm2 plist | the scenario not starting: the old clone not tracking the plist | merge | into “macOS: the update starts as it did on the real Mac: iTerm2 running on the clone's plist, its own write a local change, the pull deleting it”: six preconditions of one run; none is the behaviour under test |
| macOS: the real iTerm2 is running | the scenario not starting: iTerm2 not running | merge | into “macOS: the update starts as it did on the real Mac: iTerm2 running on the clone's plist, its own write a local change, the pull deleting it”: six preconditions of one run; none is the behaviour under test |
| macOS: the real iTerm2 is set to load its preferences from the clone | the scenario not starting: iTerm2 not reading the clone's plist | merge | into “macOS: the update starts as it did on the real Mac: iTerm2 running on the clone's plist, its own write a local change, the pull deleting it”: six preconditions of one run; none is the behaviour under test |
| macOS: git sees the plist iTerm2 rewrote as a local change | the scenario not starting: iTerm2's write not seen by git | merge | into “macOS: the update starts as it did on the real Mac: iTerm2 running on the clone's plist, its own write a local change, the pull deleting it”: six preconditions of one run; none is the behaviour under test |
| macOS: the pull deletes the tracked plist, so copying it back is what keeps it | the scenario not starting: the pull not deleting the plist | merge | into “macOS: the update starts as it did on the real Mac: iTerm2 running on the clone's plist, its own write a local change, the pull deleting it”: six preconditions of one run; none is the behaviour under test |
| macOS: install.sh under bash 3.2 and the stock PATH succeeds during the update | install.sh failing under bash 3.2 while iTerm2 is open | merge | into “macOS: install.sh under bash 3.2 and the stock PATH succeeds during the update and iTerm2 stays running”: one command and its effect on the app |
| macOS: iTerm2 is still running after the update | the update quitting iTerm2 | merge | into “macOS: install.sh under bash 3.2 and the stock PATH succeeds during the update and iTerm2 stays running”: one command and its effect on the app |
| macOS: an update run while the real iTerm2 reads its preferences from the clone keeps its plist | the update removing the plist iTerm2 is using | merge | into “macOS: an update run while the real iTerm2 reads its preferences from the clone keeps its plist, byte for byte”: kept and unchanged are one promise |
| macOS: the kept plist is what iTerm2 last saved, byte for byte | the kept plist differing from what iTerm2 saved | merge | into “macOS: an update run while the real iTerm2 reads its preferences from the clone keeps its plist, byte for byte”: kept and unchanged are one promise |
| macOS: install.sh says it added the Claude tmux profile | the profile not reported as added | merge | into “macOS: the Claude tmux profile is added as a file iTerm2 can read, linked into the clone, and iTerm2 no longer loads its preferences from the clone”: five readings of the one profile file |
| macOS: the profile file iTerm2 loads exists and resolves into the clone | the profile file missing or not linked into the clone | merge | into “macOS: the Claude tmux profile is added as a file iTerm2 can read, linked into the clone, and iTerm2 no longer loads its preferences from the clone”: five readings of the one profile file |
| macOS: that profile file holds the Claude tmux profile | the profile file holding another profile | merge | into “macOS: the Claude tmux profile is added as a file iTerm2 can read, linked into the clone, and iTerm2 no longer loads its preferences from the clone”: five readings of the one profile file |
| macOS: plutil can read the profile file | a profile file iTerm2 cannot read | merge | into “macOS: the Claude tmux profile is added as a file iTerm2 can read, linked into the clone, and iTerm2 no longer loads its preferences from the clone”: five readings of the one profile file |
| macOS: iTerm2 no longer loads its preferences from the clone | iTerm2 still loading preferences from the clone after the update | merge | into “macOS: the Claude tmux profile is added as a file iTerm2 can read, linked into the clone, and iTerm2 no longer loads its preferences from the clone”: five readings of the one profile file |
| macOS: install.sh --check after the update ends all checks passed | --check failing after the update | merge | into “macOS: install.sh --check after the update ends all checks passed and passes the iTerm2 profile”: two lines of one --check run |
| macOS: install.sh --check passes the iTerm2 profile | --check not listing the iTerm2 profile | merge | into “macOS: install.sh --check after the update ends all checks passed and passes the iTerm2 profile”: two lines of one --check run |
| opening the Claude terminal shows four panes | the Claude terminal opening with other than four panes | keep | changes the user's own terminal settings |
| Windows Terminal keeps your default profile when --default-profile is not chosen | Windows Terminal's default profile changed unasked | keep | changes the user's own terminal settings |
| macOS: making the Claude profile iTerm2's default remembers which profile was your default | the user's old iTerm2 default forgotten | keep | changes the user's own terminal settings |

before 21, after 9

## phone-pictures

phone-sized screenshots for the evaluator.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| a page of three screens becomes three phone-width pictures and nothing else | a three-screen page giving the wrong number or width of pictures | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| pictures stay 780 wide where the Mac always shows scroll bars | pictures 750 px wide on a Mac that always shows scroll bars | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| a short page becomes one picture no taller than a screen | a short page padded out to several pictures | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| the picture of a one-line page ends near the text, with no blank screen below it | a blank screen below a one-line page | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| a Markdown file becomes a phone-width picture | a Markdown file not drawn | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| a long text file is cut into phone screens | a long text file not cut into screens | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| a range of lines of a text file becomes a picture | a line range ignored | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| the real picture taker draws only the lines of the range it was handed | lines outside the range drawn by the real picture taker | keep | the only comparison of the phone-bidi stand-in with the real tool |
| a terminal session becomes a phone-width picture | a tmux session not turned into a picture | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| text a terminal prints in green stays green in its picture | terminal colours lost in the picture | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| a web address becomes phone-width pictures | a web address not pictured | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| an address that does not answer gives no picture and says why | a dead address giving an empty picture or no reason | keep | needs the real headless Firefox; nothing in the quick tier draws a picture |
| a Firefox that never opens its port means no picture, no file and no process left | a missing Firefox not reported by the phone tool | keep | the phone tool's failure paths; the machine tier only runs it where Firefox works |
| a phone picture without Firefox installed says it is not installed | the phone tool waiting for ever on a Firefox that opens no port | keep | the phone tool's failure paths; the machine tier only runs it where Firefox works |
| a picture of a line range numbers the lines as the file does | the wrong tool chosen for the OS | keep | the phone tool's failure paths; the machine tier only runs it where Firefox works |

before 15, after 15

## wsl-tools

WSL window and terminal tools.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| every WSL shell script parses under /bin/bash | a WSL script with a syntax error | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| wt-profile sets tmux-quad and the font on this distro's WSL profile only | wt-profile changing another distro's profile, or not setting tmux-quad and the font | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| wt-profile --default makes the profile the default and says what the old one was | --default not switching, or not saying what the old default was | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| wt-profile run twice leaves the file untouched the second time | a second run rewriting the file | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| wt-profile --check answers yes or no and changes nothing | --check changing something | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| wt-profile says when the distro has no Windows Terminal profile | a distro with no profile failing silently | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| wt-profile will not rewrite a settings file with comments and says what to add by hand | a settings file with comments rewritten and its comments lost | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| wt-profile reads a settings file that starts with a byte order mark | a byte order mark breaking the read | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| winenv prints the Windows user folders in Windows and WSL form | the Windows user folders wrong in either form | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| winenv asks Windows once and answers from its cache afterwards | Windows asked on every call | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| winenv says it is not on WSL when Windows gives no user folder, and caches nothing | a failed answer cached | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| game guard names a running game and logs the refused request | a running game not named, or the refusal not logged | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| game guard is silent and logs nothing when no game is running | noise when no game is running | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| game guard looks for the games named in GAME_GUARD_PROCS | GAME_GUARD_PROCS ignored | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| GAME_GUARD=off allows everything without asking Windows | GAME_GUARD=off still asking Windows | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| game guard reports no game on a machine that is not WSL | the guard failing off WSL | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| the window tools refuse to run on a machine that is not WSL | the window tools running off WSL | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| win.sh hands the window request to PowerShell and returns its answer | win.sh not passing the request or the answer | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| win.sh will not show a window while a game is running | a window shown over a game | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| win.sh will not move on to the next window while a game is running | the next window shown over a game | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| win-app finds Firefox under the Windows Program Files folder | Firefox not found under Program Files | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| win-app gives Firefox a file URL for a Linux path, with the safe mode key disabled | a Linux path given to Firefox as it is, or safe mode offered | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| win-app opens nothing while a game is running and logs the request | an app opened over a game | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| win-app --hidden asks for a hidden window by title and records its handle | --hidden opening a visible window or losing its handle | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| win-app says VS Code is retired and rejects an unknown app | VS Code opened, or an unknown app accepted | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| screen-capture asks PowerShell for a PNG in the Windows home and prints its WSL path | the capture path wrong or not converted | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| screen-capture prints no path when PowerShell fails | a path printed for a failed capture | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| term-open starts a tmux session in a hidden terminal and types the command into it | term-open's window visible, or the command not typed | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| term-open kills its tmux session when the window cannot be opened hidden | a stray tmux session after a failed open | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| term-open fails when the opened window cannot be found | term-open succeeding with no window found | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| term-open does nothing while a game is running | a terminal opened over a game | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| term-close closes the window, kills the session and reports a failed close | term-close leaving the window or session, or hiding a failed close | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |
| the terminal volume service runs the scheduled task the installer registers for an existing script | the volume service pointing at a task or script that does not exist | keep | WSL has no CI runner; these stand-in runs are the only tests of its tools |

before 33, after 33

## helper

helper agent and its wiki MCP server.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| the real helper server starts and lists its five tools | the helper server not starting under a real MCP client, or its tool list drifting from the stand-in's | keep | the only comparison of the mcp stand-in with the real tool |
| helper server: it offers exactly the five read-only wiki tools | the server offering a tool that writes, or missing one | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: wiki_list names the pages and wiki_read gives one by title, with spaces or dashes | pages not found by a title with spaces or dashes | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: asking for a page that does not exist names the pages that do | a missing page answered with nothing to go on | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: wiki_search finds a line whatever its case and says so when nothing matches | search missing a line by case, or silent when nothing matches | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: agent_read gives the agent files and refuses any other name | agent_read giving any file asked for | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: a wiki stamped with today's agent files is reported in step | an up-to-date wiki reported as behind | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: an agent file changed after the stamp is named as ahead of the guide | an agent file changed after the stamp not named | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: an agent file edited but not committed is said to have uncommitted edits | uncommitted agent edits not mentioned | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: an agent file the stamp does not list is named as ahead of the guide | an agent the stamp does not list counted as in step | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: a wiki with no stamp counts every agent as ahead of it | an unstamped wiki counted as in step | keep | one answer of the helper's server; the helper cites it to beginners |
| helper server: workflow_status answers as JSON that names the changed files | workflow_status not valid JSON or missing the changed files | keep | one answer of the helper's server; the helper cites it to beginners |
| stamp-wiki writes a stamp the server reads as in step, and replaces an old one | stamp-wiki writing a stamp the server rejects, or keeping the old one | keep | one answer of the helper's server; the helper cites it to beginners |

before 13, after 13

## assistant

assistant agent, its MCP server and guard hook.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| the real assistant server starts and lists its seven tools | the assistant server not starting, or its tool list drifting from the stand-in's | keep | the only comparison of the mcp stand-in with the real tool |
| assistant guard: tmux commands that only read are allowed | the guard blocking read-only tmux commands | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: typing into a pane from the shell is blocked and names assistant_send | typing into a pane from the shell getting through | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: starting and closing panes from the shell are blocked, wrapped or chained too | panes started or closed from the shell, wrapped or chained, getting through | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: background commands are blocked and point at assistant_schedule | background commands getting through | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: a forced launch needs confirmed=True | a forced launch going ahead unconfirmed | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: other tools and unreadable input are let through | the guard blocking other tools or crashing on bad input | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: typing into the assistant's own pane needs self=True | the assistant typing into its own pane unasked | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: closing the assistant's own pane needs self=True | the assistant closing its own pane unasked | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: a pet pane takes no text and is not closed by itself | text sent to, or a close of, the pet pane | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: answering a judgement menu is blocked, quoting the question; plain text is not | the assistant answering a judgement menu for the user | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: force on a running pane needs confirmed=True; on an idle shell it does not | force on a running pane going ahead unconfirmed | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant guard: force on a pane waiting on a question needs confirmed=True | force on a pane waiting on a question going ahead unconfirmed | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant server: it offers the seven assistant_ tools and sees the panes of this tmux server | the server missing a tool or not seeing this tmux server's panes | keep | each is one rule of the guard or one answer of the server; no other test asks it |
| assistant server: pane ids given as one comma-separated line are answered one by one | comma-separated pane ids read as one pane | keep | each is one rule of the guard or one answer of the server; no other test asks it |

before 15, after 15

## doc-skills

write-readme, write-report and review-skill instructions.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| each documentation skill is named after its folder and says when to use it | a skill whose name does not match its folder, or with no usable description | keep | skill text is the product here; each names what must stay true of it |
| every reference file a documentation skill names is in that skill's folder | a skill naming a reference file that is missing | keep | skill text is the product here; each names what must stay true of it |
| the README style file holds the template, voice rules and rejected sentences write-readme promises | the style file missing a section write-readme promises | keep | skill text is the product here; each names what must stay true of it |
| every git command write-readme names is a command git has | write-readme naming a git command that does not exist | keep | skill text is the product here; each names what must stay true of it |
| write-report starts an agent that exists, with the options that agent reads | write-report starting an agent or option that does not exist | keep | skill text is the product here; each names what must stay true of it |
| the report check write-report asks for is one check.py offers | write-report asking for a check check.py lacks | keep | skill text is the product here; each names what must stay true of it |
| every send-back and failure ending write-report acts on is one the report-writer can end with | write-report acting on an ending the report-writer never gives | keep | skill text is the product here; each names what must stay true of it |
| review-skill runs the six passes its description lists, in order | review-skill's passes differing from its description | keep | skill text is the product here; each names what must stay true of it |
| review-skill takes the skill to review as its argument and waits before editing | review-skill editing before approval | keep | skill text is the product here; each names what must stay true of it |
| write-report does not deliver a report with an open high checker finding | a report delivered with an open high finding | keep | skill text is the product here; each names what must stay true of it |
| write-readme asks before it creates a GitHub repo | a GitHub repo created without asking | keep | skill text is the product here; each names what must stay true of it |

before 11, after 11

## context-trims

context trims survive the settings merge.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| a new user gets every trim exactly as the repo has it | a new user's settings differing from the repo's trims | keep | each is one merge rule of the trims |
| a user's own skill overrides win and the repo's others are added | the repo's skill overrides replacing the user's | keep | each is one merge rule of the trims |
| denied tools and denied servers are added beside the user's own, without doubles | deny lists not unioned, or doubled | keep | each is one merge rule of the trims |
| features the user switched on stay on and untouched ones are switched off | features the user switched on being switched off | keep | each is one merge rule of the trims |
| installing again keeps the trims unchanged | trims doubling up on a second install | keep | each is one merge rule of the trims |
| a new user of this repo's settings gets workflows and their keyword trigger switched off | workflows left on for a new user | keep | each is one merge rule of the trims |

before 6, after 6

## test-runner

test/run: tiers, lint, feature list.

| Test | Catches | Verdict | Reason |
|---|---|---|---|
| test/run: pages that match the tree and sit at their caps pass | the record checks failing a correct tree | keep | the pages a new session reads; an unchecked page goes stale |
| test/run: ARCHITECTURE.md naming a missing path fails the run and names the line | ARCHITECTURE.md naming a path that is gone | keep | the pages a new session reads; an unchecked page goes stale |
| test/run: a Decisions section over 20 lines or a Next section over 10 fails the run | the Decisions or Next section growing past its cap | keep | the pages a new session reads; an unchecked page goes stale |
| test/run: a missing section, a missing page and a long project CLAUDE.md each fail the run | a missing section or page, or a long project CLAUDE.md, passing | keep | the pages a new session reads; an unchecked page goes stale |
| test/run: a project CLAUDE.md importing a file that is not there fails the run | a project CLAUDE.md importing a missing file | keep | the pages a new session reads; an unchecked page goes stale |
| README status line: three systems passing the same tests read as one result | three passing systems not shown as one result | keep | the pages a new session reads; an unchecked page goes stale |
| README status line: a system not run, failing, skipping or older says so | a system that failed, skipped or is stale shown as passing | keep | the pages a new session reads; an unchecked page goes stale |
| bin/release/trust-report all: runs every tier, records this system's result and rewrites the README status line | trust-report all not running every tier or not rewriting the README line | keep | the pages a new session reads; an unchecked page goes stale |
| bin/release/trust-report: any argument but all is refused | trust-report accepting other arguments | keep | the pages a new session reads; an unchecked page goes stale |
| test/run: a TESTING.md over 80 lines fails the run; 80 passes | TESTING.md growing past 80 lines | keep | the pages a new session reads; an unchecked page goes stale |
| the project CLAUDE.md points a session at the records and the one test command | the project CLAUDE.md no longer pointing at the records and test/run | keep | the pages a new session reads; an unchecked page goes stale |
| the README's status line links to TESTING.md | the README status line no longer linking to TESTING.md | keep | the pages a new session reads; an unchecked page goes stale |
| ARCHITECTURE.md: every part says its folder and where new work goes | an ARCHITECTURE.md row with no folder or no place for new work | keep | the pages a new session reads; an unchecked page goes stale |
| ARCHITECTURE.md: every folder in the repo is on the page | a repo folder missing from ARCHITECTURE.md | keep | the pages a new session reads; an unchecked page goes stale |
| test/run: passing tests end in PASS <n> tests and exit 0 | a passing run not ending PASS or exiting nonzero | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a failing test ends in FAIL <failed> of <n> and exit 1 | a failing run exiting 0 | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a test file bats cannot read is a failure, not a pass | an unreadable test file counted as a pass | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: bats dying part way through is a failure, not a pass | bats dying half way counted as a pass | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a fixed wait in a quick test fails the run and names file and line | a fixed wait in a quick test let through | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a fixed wait spelled with its full path or in python is caught too | a fixed wait spelled another way let through | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: network, the real home, a bare skip and a fixed port each fail the run | network, the real home, a bare skip or a fixed port let through | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: an unknown tier prints the usage and exits 2 | an unknown tier run as something | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: the old modes and any extra argument print the usage and exit 2 | an old mode or extra argument accepted | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a failing run names each failed test with its feature just above the FAIL line | a failure not named with its feature above the FAIL line | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a failing pytest test is named with the feature of its file | a failing pytest test not named | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a lint problem and a feature with no test each get a FAILED line | a lint problem or an empty feature not on a FAILED line | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a test file that hangs is killed after the time limit and fails the run | a hanging file stalling the run for ever | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: more files than slots all run and are all counted | files beyond the parallel slots dropped from the count | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a check that bash 3.2 would silently ignore is refused | a check bash 3.2 silently ignores let through | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a list whose features all have tests passes and says how many it counted | a complete feature list failing, or the count wrong | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a new tagged test passes with no other file edited, and so does deleting one | a new tagged test needing another file edited | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: deleting a feature's last test fails the run and names the feature | a feature left with no test passing | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a test with no feature tag, or an id the list lacks, fails the run | an untagged test, or an unlisted id, passing | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a bad line, a row with a third column and a double id each fail the run | a malformed features.txt row passing | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a missing features.txt fails the run | a missing features.txt passing | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a pytest file's test functions count for the feature its comment names | pytest tests not counted for their feature | keep | the runner's own promise; if this breaks, a pass means nothing |
| assertions: --regexp reads the output as one string, the line helpers read it line by line | the fallback assertions reading output differently from bats-assert | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: skipped tests are counted on a line of their own | skipped tests hidden in the total | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a quick test skipped for a missing tool is a failure | a quick test skipped for a missing tool passing | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: a machine test may skip for a missing tool | a machine test's honest skip failing the run | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: the regex operator is not a home folder; a tilde path after an equals sign is | lint false alarms on =~, or a missed ~ path after = | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run --only: runs the tests of that feature and no others | --only running other features' tests | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/faults: counts the faults the tests catch, names the missed one and leaves the repo as it was | faults miscounting, or leaving the repo patched | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/faults: all caught exits 0 and a full run records the result | faults failing when all are caught, or not recording a full run | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/faults: fewer than three faults, a patch that edits tests and one that does not apply all fail | faults accepting too few patches, a patch to a test, or one that does not apply | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/repeat: passing runs agree, each under its own seed, and the result is recorded | repeat not using a seed per run, or not recording | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/repeat: with no TEST_SEED it picks a seed and prints it | repeat hiding its seed | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/repeat: one run that differs lowers the count, fails and names the test | a differing run not lowering the count or not named | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/repeat: no number, or a word for one, prints its usage and exits 2 | repeat accepting no number | keep | the runner's own promise; if this breaks, a pass means nothing |
| test/run: TEST_SEED decides the order of the files, is printed, and the same seed repeats it | TEST_SEED not deciding the order, or not repeatable | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/repeat <n> <files>: adds up the runs of several result files against the planned number | shard results not added up against the plan | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/trust-report: writes the five numbers between the marks and keeps the rest of TESTING.md | trust-report overwriting the rest of TESTING.md or missing a number | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/trust-report: repeated runs that all failed the same way are shown as failed | runs that all failed alike shown as agreement | keep | the runner's own promise; if this breaks, a pass means nothing |
| weekly repeat job: passes at 300 passing runs on each system, fails when 300 failed the same way or a system is missing | the weekly job passing on 300 identical failures | keep | the runner's own promise; if this breaks, a pass means nothing |
| weekly repeat job: a shard that dies before finishing leaves no old result to upload | a dead shard uploading an old result | keep | the runner's own promise; if this breaks, a pass means nothing |
| bin/release/trust-report: a TESTING.md without the marks is left alone and exits 2 | a TESTING.md without marks rewritten | keep | the runner's own promise; if this breaks, a pass means nothing |

before 56, after 56
