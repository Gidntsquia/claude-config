#!/usr/bin/env bash
# usage: find-personal-paths.sh [clone]   Lists every installed file of the clone that still names a person's home
# folder or the old trip folder. A tracked file prints as its path and makes the exit code 1 (it would be pushed).
# A file git does not track prints as `WARN <path>` and does not fail: it is yours and stays on this machine.
# Prints nothing and exits 0 when the clone is clean.
# Installed files = the clone minus .git, wiki/, archive/, plans/, examples/, agents/evals/ (and git-ignored files
# when the clone is a git checkout). The patterns are split in two so this file does not match itself.
set -u
R="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$R" || exit 2
p1="jax""on"; p2="/Us""ers/"; p3="/ho""me/"; p4="september""-trip"
GIT=""; { [ -d .git ] || [ -f .git ]; } && command -v git >/dev/null 2>&1 && GIT=1
scan() {  # scan <prefix>: print <prefix><file> for each listed file that matches; exit 1 on any hit
  local f hit=0
  while IFS= read -r f; do
    case "$f" in wiki/*|archive/*|plans/*|examples/*|agents/evals/*|.git/*) continue ;; esac
    [ -f "$f" ] || continue
    if grep -Iq -e "$p1" -e "$p2" -e "$p3" -e "$p4" -- "$f"; then echo "$1$f"; hit=1; fi
  done
  return "$hit"
}
if [ -n "$GIT" ]; then
  git ls-files --others --exclude-standard | scan "WARN "
  git ls-files --cached | scan ""
else
  find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | scan ""
fi
