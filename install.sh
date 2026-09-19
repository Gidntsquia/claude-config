#!/usr/bin/env bash
# Symlink this repo's files into ~/.claude. Existing real files are moved to <name>.pre-link.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$HOME/.claude"
mkdir -p "$C/skills"
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then rm "$dst"; elif [ -e "$dst" ]; then mv "$dst" "$dst.pre-link"; fi
  ln -s "$src" "$dst"
}
for i in agents commands hooks CLAUDE.md settings.json statusline.sh; do link "$R/$i" "$C/$i"; done
for s in "$R"/skills/*/; do s="${s%/}"; link "$s" "$C/skills/$(basename "$s")"; done
echo "linked into $C"
