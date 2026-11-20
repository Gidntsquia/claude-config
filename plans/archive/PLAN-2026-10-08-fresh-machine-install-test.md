# Spec: Fresh-machine install test for claude-config, in Docker, with the host left untouched
Drafted 2026-10-08.

## Ask
> I want to test that this claude config will be properly installed on a totally fresh machine without clobbering what I have on this machine (in case it ultimately doesn't work)

Answers (2026-10-08):
- Fresh machine = "Docker container" (Ubuntu image, repo cloned inside, install.sh run as a normal user; thrown away after).
- Installed properly = all of: "Symlinks match this machine", "Claude Code starts and sees the config", "Scripts run", "Re-run is idempotent".
- WSL/macOS steps: "Test them too, but dry-run".
- Output: "Reusable test script in the repo".
- Docker: "Install Docker in WSL" (docker-ce via apt, needs sudo).
- Auth in container: "Mount ~/.claude/.credentials.json read-only".
- No-clobber: "Both: pre-existing files preserved, and host untouched".
- Dry-run: "CLAUDE_CONFIG_DRY_RUN=1 env var"; test forces the branch with CLAUDE_CONFIG_OS=wsl|mac.

## What to build
A test script, `test/fresh-install.sh`, that builds a throwaway Ubuntu container, copies this repo into it, runs `install.sh` as a non-root user with an empty `~/.claude`, and checks that the result is exactly what this machine has (same set of symlinks, pointing into the clone), that Claude Code starts in the container with the user's mounted credentials and lists the three agents and four skills, that `statusline.sh` and `hooks/full-suite-guard.sh` run, that a second `install.sh` changes nothing, that files already present in `~/.claude` are kept as `<name>.pre-link`, and that the WSL and macOS branches print their commands under a new `CLAUDE_CONFIG_DRY_RUN=1` instead of executing them. The script snapshots the host's `~/.claude` before and after and fails if anything changed. One-time: install Docker in this WSL distro.

## Facts (verified 2026-10-08)
- Docker and podman are not installed here (`command -v docker` empty). `claude` is at `~/.local/bin/claude`, version 2.1.295.
- `install.sh` links `agents commands hooks CLAUDE.md settings.json statusline.sh` and each `skills/*/` dir into `~/.claude`; existing non-link files go to `<name>.pre-link`. It detects WSL via `/proc/version` containing "microsoft" and macOS via `uname = Darwin`; the WSL branch calls `cmd.exe`, `wslpath`, `python3 wsl/wt-profile.py`, `powershell.exe Register-ScheduledTask`, `cp` to `%USERPROFILE%\Scripts`, and `systemctl --user`; the mac branch calls `defaults write` and links `iterm2/DynamicProfiles/*.json`.
- On this host `~/.claude` has exactly these links into the repo: `CLAUDE.md agents commands hooks settings.json statusline.sh skills/{review-skill,test-speedup,weekly-roundup,write-readme}`. `~/.claude/skills/synced` is a real dir managed by Claude, not from the repo.
- `settings.json` wires the hook as `bash "$HOME/.claude/hooks/full-suite-guard.sh"` (PreToolUse, matcher Bash) and the statusline as `bash ~/.claude/statusline.sh`.
- `.gitignore` already ignores `plans/` and `CLAUDE.local.md`.
- Unverified: exact Claude Code install command for Linux (native installer `curl -fsSL https://claude.ai/install.sh | bash` vs npm `@anthropic-ai/claude-code`); which non-interactive command lists agents/skills. Worker checks `claude --help` in the container.

## Requirements
1. (user) `test/fresh-install.sh`, run from the repo root with bash, builds an Ubuntu 24.04 image (default; `CLAUDE_CONFIG_TEST_IMAGE` overrides), copies the repo's git-tracked files into it at `/home/tester/claude-config`, and runs every check as user `tester` with `HOME=/home/tester`. Exit 0 and a final `PASS` line when all checks pass; exit 1, each failing check named, otherwise. Each check prints one `ok`/`FAIL` line.
2. (user) Symlink check: after `install.sh`, `~/.claude` in the container contains symlinks for exactly `CLAUDE.md agents commands hooks settings.json statusline.sh` and `skills/<name>` for each dir under `skills/`, each resolving to the matching path in the clone. Any other entry created by `install.sh` under `~/.claude` (except `skills/` itself) is a FAIL. The expected list is derived from the repo contents, not hard-coded.
3. (user) Claude Code check: the image installs Claude Code; the test mounts the host's `~/.claude/.credentials.json` read-only into the container (`-v ...:ro`), and asserts Claude Code reports the config: agents `planner`, `worker`, `evaluator` and skills `review-skill`, `test-speedup`, `weekly-roundup`, `write-readme` appear in the output of the listing command the worker finds (default `claude agents` / `claude skills` or `claude -p` with a one-line prompt if no listing command exists). If `.credentials.json` is missing on the host the check is reported `SKIP`, not FAIL. Nothing is ever written back to the host file.
4. (user) Scripts check: `bash ~/.claude/statusline.sh` fed a sample status JSON on stdin (with `model.display_name`, `workspace.current_dir`, `cwd`) exits 0 and prints non-empty output; `bash ~/.claude/hooks/full-suite-guard.sh` fed a PreToolUse JSON for `Bash` with command `echo hi` exits 0, and fed `pytest` in a dir that has `.claude/test-commands.sh` exits 2.
5. (user) Idempotence: running `install.sh` a second time produces the same `find ~/.claude -printf '%p %y %l\n'` listing as after the first run, and creates no `*.pre-link` files.
6. (user) Pre-existing files: in a second container run, `~/.claude/CLAUDE.md` and `~/.claude/settings.json` exist as real files with known content before `install.sh`; after, `CLAUDE.md.pre-link` and `settings.json.pre-link` exist with byte-identical content and the originals are links into the clone.
7. (user) Dry-run: `install.sh` honors `CLAUDE_CONFIG_DRY_RUN=1`: every `cmd.exe`, `powershell.exe`, `defaults`, `systemctl`, `cp` to the Windows profile, and iTerm2 link is printed as `DRY: <command>` and not executed; symlinking into `~/.claude` still happens. `CLAUDE_CONFIG_OS=wsl|mac|linux` forces the branch (default: current detection). The test runs the wsl and mac branches in the container and asserts the printed lines include `Register-ScheduledTask`, `wt-profile.py`, `terminal-volume.service` (wsl) and `defaults write com.googlecode.iterm2` (mac). Without the env var, behavior on this machine is unchanged.
8. (user) Host untouched: before the first docker command and after the last, the script records `find ~/.claude -maxdepth 2 -printf '%p %y %l\n'` on the host (excluding `projects sessions session-env file-history shell-snapshots history.jsonl backups` and other session-churn paths) plus `sha256sum` of `~/.claude/.credentials.json`, and fails if the two snapshots differ.
9. (user) Docker: `README.md` gets a short "Testing the install" section with the apt steps for docker-ce in WSL (worker performs them once here, with sudo, and adds the user to the `docker` group) and `./test/fresh-install.sh`. The script fails fast with a clear message if `docker` is absent or the daemon is not running.
10. (default) The container never gets the host's `~/.claude` directory, `history.jsonl`, `projects/`, or any file besides `.credentials.json`; the image is tagged `claude-config-test` and containers run with `--rm`.
11. (default) Total run time under 5 minutes after the first image build; the image build is cached by Docker between runs.

## Constraints
- bash for the test script and install.sh changes; Dockerfile under `test/`. No new languages or package managers.
- `install.sh` stays a single script; only additive changes (dry-run and OS override). Existing behavior on this machine without the env vars is unchanged.
- Never commit `.credentials.json`, history, or session data; `test/` must not copy them.

## Acceptance criteria
- [ ] R1: `./test/fresh-install.sh` from repo root exits 0 and ends with `PASS`; each check printed one `ok` line.
- [ ] R2: deleting a line from the expected-links derivation (e.g. temporarily adding a `skills/zzz/` dir without rerunning install) makes the symlink check FAIL; restored, it passes.
- [ ] R3: test output shows the three agent names and four skill names from Claude Code inside the container; host `.credentials.json` mtime and sha256 unchanged.
- [ ] R4: statusline and hook checks print `ok`; hook check shows exit 2 for the bare `pytest` case.
- [ ] R5: second-install listing diff is empty and `find ~/.claude -name '*.pre-link'` in the container is empty.
- [ ] R6: `.pre-link` files exist and `cmp` against the planted content succeeds.
- [ ] R7: `CLAUDE_CONFIG_DRY_RUN=1 CLAUDE_CONFIG_OS=wsl ./install.sh` on this host prints `DRY:` lines and `Get-ScheduledTask 'Pin Windows Terminal Volume'` shows no new LastRunTime; same for `mac` printing `defaults write`.
- [ ] R8: host snapshot diff is empty at end of run; `ls -la ~/.claude` on this host before and after the whole session is the same (links unchanged).
- [ ] R9: `docker version` works without sudo for this user; README has the new section.
- [ ] R10: `docker ps -a` shows no leftover containers after a run; `docker run --rm claude-config-test ls /home/tester/.claude` shows no history/projects.
- [ ] R11: `time ./test/fresh-install.sh` second run under 5 min.
