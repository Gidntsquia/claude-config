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
for i in agents commands CLAUDE.md settings.json statusline.sh; do link "$R/$i" "$C/$i"; done
for s in "$R"/skills/*/; do s="${s%/}"; link "$s" "$C/skills/$(basename "$s")"; done
echo "linked into $C"

# iTerm2 (macOS only): read/write settings from iterm2/ in this repo, and link dynamic profiles.
if [ "$(uname)" = "Darwin" ]; then
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$R/iterm2"
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
  D="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  mkdir -p "$D"
  for f in "$R"/iterm2/DynamicProfiles/*.json; do link "$f" "$D/$(basename "$f")"; done
  echo "iTerm2 now uses $R/iterm2 (restart iTerm2)"
fi

# WSL only: new Windows Terminal tabs for this distro open tmux with 4 panes in ~/files.
if grep -qi microsoft /proc/version 2>/dev/null; then
  mkdir -p "$HOME/.local/bin"
  link "$R/wsl/tmux-quad" "$HOME/.local/bin/tmux-quad"

  # Starship prompt (gruvbox-rainbow preset) in bash. Windows Terminal needs a Nerd Font for the glyphs.
  [ -x "$HOME/.local/bin/starship" ] || curl -sS "https://starship.rs/install.sh" | sh -s -- -y -b "$HOME/.local/bin"
  mkdir -p "$HOME/.config"
  link "$R/wsl/starship.toml" "$HOME/.config/starship.toml"
  grep -q 'starship init bash' "$HOME/.bashrc" || printf '\neval "$(~/.local/bin/starship init bash)"\n' >> "$HOME/.bashrc"
  grep -q 'CLAUDE_STATUSLINE_NF' "$HOME/.bashrc" || echo 'export CLAUDE_STATUSLINE_NF=1' >> "$HOME/.bashrc"
  W="$(wslpath "$(cmd.exe /C 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")"
  for S in "$W"/Packages/Microsoft.WindowsTerminal*/LocalState/settings.json; do
    [ -f "$S" ] && python3 "$R/wsl/wt-profile.py" "$S" "$WSL_DISTRO_NAME" "wsl.exe -d $WSL_DISTRO_NAME -- $HOME/.local/bin/tmux-quad" "JetBrainsMono Nerd Font" || true
  done
  compgen -G "/mnt/c/Windows/Fonts/JetBrainsMonoNerdFont-*" >/dev/null || compgen -G "$W/Microsoft/Windows/Fonts/JetBrainsMonoNerdFont-*" >/dev/null \
    || echo "Install JetBrainsMono Nerd Font on Windows (https://www.nerdfonts.com/font-downloads) or the prompt shows boxes"

  # Windows Terminal resets to 100% in the volume mixer after reboots; set it to 18% each time WSL boots.
  # The .ps1 is copied (Windows runs it from %USERPROFILE%\Scripts), so rerun install.sh after editing it.
  WP="$(cmd.exe /C 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
  mkdir -p "$(wslpath "$WP")/Scripts"
  cp "$R/wsl/terminal-volume.ps1" "$(wslpath "$WP")/Scripts/terminal-volume.ps1"
  powershell.exe -NoProfile -Command "
    \$a = New-ScheduledTaskAction -Execute conhost.exe -Argument '--headless powershell.exe -MTA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $WP\\Scripts\\terminal-volume.ps1'
    \$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'Pin Windows Terminal Volume' -Action \$a -Settings \$s -Force | Out-Null"
  mkdir -p "$HOME/.config/systemd/user"
  link "$R/wsl/terminal-volume.service" "$HOME/.config/systemd/user/terminal-volume.service"
  systemctl --user daemon-reload && systemctl --user enable terminal-volume.service >/dev/null 2>&1 || true
  echo "Windows Terminal volume will be set to 18% each time WSL boots"
fi
