# Runs inside Windows Sandbox (see README.md). Installs WSL with Ubuntu, then inside Ubuntu installs git, python3, tmux
# and Claude Code, clones claude-config and runs test/install-scenarios.sh --terminal (the same two scenarios as
# test/docker-install.sh). Everything is logged to C:\shared\install-test.log, which is the host folder you mapped.
$ErrorActionPreference = 'Continue'
$log = 'C:\shared\install-test.log'
Start-Transcript -Path $log -Append | Out-Null
Write-Host "== $(Get-Date -Format s) claude-config install test"

$distros = (wsl.exe -l -q 2>$null) -replace "`0", '' | Where-Object { $_ -match 'Ubuntu' }
if (-not $distros) {
  Write-Host '== wsl --install -d Ubuntu --no-launch'
  wsl.exe --install -d Ubuntu --no-launch
  if ($LASTEXITCODE -ne 0) {
    Write-Host "wsl --install exited $LASTEXITCODE. Windows Sandbox may not support nested virtualization on this PC; see README.md."
    Stop-Transcript | Out-Null; exit 1
  }
  # The Ubuntu app registers the distro on first launch; do it without the interactive user prompt.
  ubuntu.exe install --root
}

$repo = if (Test-Path C:\shared\repo.txt) { (Get-Content C:\shared\repo.txt -Raw).Trim() } else { 'https://github.com/Gidntsquia/claude-config' }
$branch = if (Test-Path C:\shared\branch.txt) { (Get-Content C:\shared\branch.txt -Raw).Trim() } else { 'main' }
$script = @"
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -q && apt-get install -y -q git curl ca-certificates python3 tmux
id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester
su - tester -c 'set -e
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH=`$HOME/.local/bin:`$PATH
  rm -rf ~/claude-config && git clone -q -b $branch $repo ~/claude-config
  cd ~/claude-config && bash test/install-scenarios.sh --terminal'
"@
Write-Host '== running the install scenarios inside Ubuntu'
wsl.exe -d Ubuntu -u root -- bash -c ($script -replace "`r", '')
$rc = $LASTEXITCODE
Write-Host "== result: $(if ($rc -eq 0) { 'PASSED' } else { "FAILED (exit $rc)" })"
Stop-Transcript | Out-Null
exit $rc
