#!/usr/bin/env bash
# usage: find-personal-paths.sh [clone]   Lists every installed file of the clone that still names a person's home
# folder or the old trip folder. Prints nothing and exits 0 when the clone is clean, else prints the files, exits 1.
# Installed files = the clone minus .git, wiki/, archive/, plans/, examples/, agents/evals/ (and git-ignored files
# when the clone is a git checkout). The patterns are split in two so this file does not match itself.
set -u
R="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$R" || exit 2
p1="jax""on"; p2="/Us""ers/"; p3="/ho""me/"; p4="september""-trip"
list() {
  if [ -d .git ] && command -v git >/dev/null 2>&1; then
    git ls-files --cached --others --exclude-standard
  else
    find . -path ./.git -prune -o -type f -print | sed 's|^\./||'
  fi
}
hits=0
while IFS= read -r f; do
  case "$f" in wiki/*|archive/*|plans/*|examples/*|agents/evals/*|.git/*) continue ;; esac
  [ -f "$f" ] || continue
  if grep -Iq -e "$p1" -e "$p2" -e "$p3" -e "$p4" -- "$f"; then echo "$f"; hits=1; fi
done < <(list)
exit "$hits"
