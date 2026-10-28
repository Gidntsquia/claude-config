# Windows install test that runs on any Windows PC (Home included): Git Bash, a brand-new empty profile folder as
# HOME/USERPROFILE, a fresh clone of the repo, then the install scenarios. Log: fresh-profile-install.log next to this
# script's working directory (or the path in -Log). Needs Git for Windows; installs Claude Code into the fresh profile.
param([string]$Repo = 'https://github.com/Gidntsquia/claude-config', [string]$Branch = 'main',
      [string]$Log = "$env:TEMP\fresh-profile-install.log")
$ErrorActionPreference = 'Continue'
$bash = "$env:ProgramFiles\Git\bin\bash.exe"
if (-not (Test-Path $bash)) { Write-Host "Git for Windows not found at $bash"; exit 1 }
$prof = Join-Path $env:TEMP ("cc-fresh-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $prof | Out-Null
Start-Transcript -Path $Log -Force | Out-Null
Write-Host "== $(Get-Date -Format s) fresh profile: $prof (empty: $((Get-ChildItem -Force $prof).Count -eq 0))"
$env:USERPROFILE = $prof; $env:HOME = $prof; $env:MSYS = 'winsymlinks:nativestrict'
Write-Host '== installing Claude Code into the fresh profile'
irm https://claude.ai/install.ps1 | iex
$env:PATH = "$prof\.local\bin;$env:PATH"
$h = ($prof -replace '\\', '/')
& $bash -c "set -e; export HOME='$h'; git clone -q -b '$Branch' '$Repo' ~/claude-config; cd ~/claude-config; bash test/install-scenarios.sh --no-terminal"
$rc = $LASTEXITCODE
Write-Host "== result: $(if ($rc -eq 0) { 'PASSED' } else { "FAILED (exit $rc)" })"
Stop-Transcript | Out-Null
Remove-Item -Recurse -Force $prof -ErrorAction SilentlyContinue
exit $rc
