# Windows Sandbox install test

Tests the install on a clean Windows with WSL, the way a new user's PC starts. It is run by hand once per release; CI does not run it (GitHub's Windows runners cannot run WSL).

## Steps

1. Turn on Windows Sandbox once: Start menu, "Turn Windows features on or off", tick **Windows Sandbox**, restart. It needs Windows 10/11 Pro, Enterprise or Education.
2. Make the folder `C:\claude-config-sandbox` and copy `claude-config.wsb` and `install-test.ps1` from this folder into it. From WSL:
   `mkdir -p /mnt/c/claude-config-sandbox && cp test/windows-sandbox/{claude-config.wsb,install-test.ps1} /mnt/c/claude-config-sandbox/`
3. Optional: to test a branch or a fork, put its name in `C:\claude-config-sandbox\branch.txt` or its URL in `repo.txt`.
4. Double-click `C:\claude-config-sandbox\claude-config.wsb`. The Sandbox opens and runs `install-test.ps1` in a PowerShell window. It installs WSL and Ubuntu, then Claude Code, then runs `test/install-scenarios.sh --terminal` inside Ubuntu.
5. If `wsl --install` asks for a restart, the Sandbox cannot restart and keep its state: the run stops there and the log says so. Nested virtualization (WSL 2 inside the Sandbox) only works on some PCs; the log then shows `wsl --install exited ...`.
6. Read `C:\claude-config-sandbox\install-test.log`. Its last line is `== result: PASSED` or `== result: FAILED (exit N)`, with each `ok` / `FAIL` line above it.
7. Close the Sandbox window; everything in it is thrown away.

## No Sandbox? (Windows Home)

Run `test/windows-fresh-profile.ps1` instead; it needs only Git for Windows. From WSL or PowerShell:
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File <path>\test\windows-fresh-profile.ps1`
It makes an empty profile folder, installs Claude Code into it, clones the repo, runs both install scenarios in Git Bash with that folder as HOME, and prints `== result: PASSED` when `install.sh --check` says "all checks passed".
