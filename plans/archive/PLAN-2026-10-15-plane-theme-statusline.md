# Spec: Plane theme for statusline.sh, switchable by CLAUDE_STATUSLINE_THEME, squid untouched

## Ask
"I want to add a second status line that uses a plane as its "main character" instead of a squid. The main "easter eggs" should be plane themed instead of underwater themed as they are with my squid status line. I want this to be another distinct option; I want to keep my squid, but I want to be able to switch to the plane if I want to. My brother will likely prefer the plane status line more"

Round 1: switching = "Env var CLAUDE_STATUSLINE_THEME"; structure = "One script, theme block per character"; eggs = "Rare singles", "Impostors", "Aviation stories over prompts", "Keep the non-squid fairy tales as-is"; right result = "Squid output byte-identical when unset", "Preview script shows every egg", "Same odds and story lengths as squid".
Round 2: base emoji = "✈️ airplane"; companions = "Airport cast"; docs/install = "README statusline bullet", "install.sh flag", "CHANGELOG entry", "Wiki page"; Windows = "Nothing special".

## What to build
Extend `statusline.sh` so `CLAUDE_STATUSLINE_THEME=plane` replaces the squid and every squid/underwater easter egg with a plane and aviation-themed eggs occupying exactly the same roll bands and prompt counts, while an unset or any-other value keeps today's squid output byte for byte. Add a `--preview` mode that prints every egg of a theme, an `install.sh --theme plane` flag that writes the export into the shell profile, and short docs in README, CHANGELOG and the wiki. Everything else on the bar (directory, branch, model, effort, usage, colors, separators) is shared and unchanged.

## Facts
- Verified (read `statusline.sh`, 334 lines): theme state is one variable `squid`, set by a `roll` in 0..9999 from `cksum` of the session id; multi-prompt stories use `saga_tick <name>` counter files in `$TMPDIR`. Roll bands (upper bound exclusive): 2 golden, 15 dragon, 30 narwhal, 55 egg-hatch (hatches at tick 6), 85 tortoise/hare (8 steps), 110 seed→tree (4), 135 caterpillar (4), 160 ghost, 185 shark, 215 turtle friend, 245 rabbit friend, 275 twin, 355 crab, 455 bubbles, 575 octopus, 725 alligator, 755 Humpty, 785 Red Riding Hood, 815 bank heist (3 steps, 2 endings by `roll % 2`), 845 three pigs, 880 pokemon battle, 915 beanstalk, 945 cooking meat, 1245 food snack (`roll % 4` picks food and length 3/5/5/7); ≥1245 plain 🦑.
- Verified: `settings.json` runs `bash ~/.claude/statusline.sh`; `install.sh` line 12 symlinks `statusline.sh`, line 36 appends `export CLAUDE_STATUSLINE_NF=1` to `.bashrc` on WSL only (grep-guarded); macOS branch has no profile edit. `CLAUDE_STATUSLINE_NF=1` already switches the separator glyph via env var.
- Verified: README line 45 is the statusline bullet; `wiki/Home.md` line 16 shows `statusline.png`; `CHANGELOG.md` top entry is `## v1.1.0 — 2026-10-15`, no Unreleased section. No tests exist for statusline.sh.
- Carried over from archived EVAL (release v1.1.0): R12 "worker's final message not saved" was never checked; unrelated to this spec, nothing to do here.

## Requirements
1. (user) `CLAUDE_STATUSLINE_THEME=plane` selects the plane theme. Unset, empty, `squid`, or any other value selects squid. The value is read case-insensitively (default).
2. (user) With the variable unset, the script's stdout for any input JSON and any session id is byte-identical to the current `statusline.sh` (commit ca4a2ce), including every squid easter egg and story step.
3. (user) One script `statusline.sh`: colors, model, effort, branch, usage, caching and rendering code is shared; the only theme-dependent part is the block that sets the character variable. (default) Rename the variable from `squid` to `mascot` or similar is allowed; output must not change.
4. (user) Plane theme everyday character is `✈️` (U+2708 U+FE0F) where squid shows `🦑`, including the plain ≥1245 case and the "back to normal" end of the snack story.
5. (user) Every squid band maps to a plane egg in the same roll band, same number of `saga_tick` steps, same `roll % 2` / `roll % 4` branching, and its own counter name so counters never collide with squid's. Mapping: golden → `✨✈️✨`; dragon → `🚀` rocket; narwhal → `✈️🦄` unicorn jet; egg-hatch → `✈️🏭✈️` factory, rolls out `✈️✈️✈️` at tick 6; tortoise/hare → runway race (same 8-step track, `🐇`/`🐢` replaced by two aircraft, e.g. `🛩️` vs `✈️`, finish `🏁`, trophy/napping ending kept); ghost → `👻✈️` ghost flight; shark → `🐦✈️` bird strike; turtle friend → `✈️🐦` bird wingman; rabbit friend → `✈️🐈` airport cat; twin → `✈️✈️` formation; crab → `🚁` helicopter; bubbles → `☁️` lost in clouds; octopus → `🛩️` prop plane; alligator → `🎈` balloon; bank heist → aviation story of 3 steps with 2 endings (e.g. takeoff→cruise→`🛬✅` landed or `✈️🌩️` diverted); pokemon battle → Wright Brothers first flight (3 steps, 2 endings); cooking meat → Apollo launch (4 steps, 2 endings); seed→tree → airport delay board (4 steps); caterpillar → baggage claim (4 steps); food snack → in-flight meal (`✈️🍱…`, same four foods or four meal emojis with lengths 3/5/5/7, `✈️😌` when finished). (user) Humpty Dumpty, Red Riding Hood, three pigs and beanstalk stay unchanged in the plane theme. Worker may adjust individual emoji within this spirit; bands and step counts may not change.
6. (user) `bash statusline.sh --preview [squid|plane]` reads no stdin and prints one line per egg: theme, roll band (`lo-hi`), counter name if any, and every step/ending string in order, in plain text (no ANSI colors needed). `--preview` with no theme prints both. Exit 0. (default) `--preview` writes no counter files.
7. (user) `./install.sh --theme plane` appends `export CLAUDE_STATUSLINE_THEME=plane` to `~/.bashrc` (WSL/Linux) or `~/.zshrc` (macOS) once, grep-guarded like the NF line; `--theme squid` appends nothing and removes nothing; no flag changes nothing. Any other value exits 1 with a one-line usage message.
8. (user) README statusline bullet gains one sentence: setting `CLAUDE_STATUSLINE_THEME=plane` (or `./install.sh --theme plane`) switches the mascot and easter eggs to a plane theme.
9. (user) `CHANGELOG.md` gets an `## Unreleased` entry above v1.1.0 describing the plane theme, the env var, `--preview`, and the install flag.
10. (user) `wiki/Cheat-Sheet.md` (or `wiki/Home.md` near the statusline image) gets a short "Plane theme" note with the env var and a screenshot `wiki/plane-statusline.png` of the bar rendered with the plane theme. (default) Screenshot taken from Windows Terminal on this box; if no capture is possible, the note goes in without an image and WORKER_NOTES.md says so.
11. (default) Nothing is added for base Windows beyond the env var; all emoji used are from the standard Unicode emoji set with at most one variation selector, no ZWJ sequences.
12. (default) `CLAUDE_STATUSLINE_NF` continues to work in both themes.

## Constraints
- Bash 4+, `jq`, `cksum`, `awk` as today; no new runtime dependencies. Script stays a single file; no sourcing of theme files.
- Only `statusline.sh`, `install.sh`, `README.md`, `CHANGELOG.md`, `wiki/*` and `plans/WORKER_NOTES.md` change. `settings.json` unchanged.
- Nothing in `plans/` or `wiki/` is committed unless the repo already tracks it (`wiki/` is tracked).

## Acceptance criteria
- [ ] R2: for 300 session ids (`s1..s300`) and two sample JSON inputs (with and without rate_limits, effort set), run old script (`git show ca4a2ce:statusline.sh`) and new script 9 times each with a fresh `TMPDIR`; `diff` of all outputs is empty.
- [ ] R1/R4: same sweep with `CLAUDE_STATUSLINE_THEME=plane`; no output contains `🦑`, `🦀`, `🐙`, `🐊`, `🦈`, `🫧`; the ≥1245 case shows `✈️`.
- [ ] R5: `--preview plane` and `--preview squid` list the same count of eggs, the same band boundaries and the same number of steps per band, in the same order; plane counter names differ from squid's; Humpty/Red Hood/pigs/beanstalk strings are identical in both.
- [ ] R6: `bash statusline.sh --preview` exits 0 with no stdin, prints both themes, leaves no new files in `TMPDIR`.
- [ ] R7: in a temp HOME, `./install.sh --theme plane` twice leaves exactly one `export CLAUDE_STATUSLINE_THEME=plane` line; `--theme squid` and no flag leave none; `--theme foo` exits 1.
- [ ] R8/R9/R10: `grep -n CLAUDE_STATUSLINE_THEME README.md CHANGELOG.md wiki/*.md` each hit at least once; CHANGELOG `## Unreleased` is the first heading after the title.
- [ ] R11: `grep -P '\x{200D}' statusline.sh` finds nothing.
- [ ] R12: `CLAUDE_STATUSLINE_NF=1` with each theme renders the `` separator.
- [ ] `bash -n statusline.sh install.sh` and `shellcheck statusline.sh` (if installed) report no errors.
