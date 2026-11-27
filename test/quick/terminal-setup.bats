#!/usr/bin/env bats
# Terminal setup on a throwaway home: the four panes of tmux-quad, and what choosing (or not choosing) the Claude
# profile as the default does to Windows Terminal's settings and to iTerm2's.

load ../helpers/common
load ../helpers/bare-install

setup() { TQ=""; }
teardown() {
  [ -n "$TQ" ] || return 0
  "$REAL_TMUX" -S "$TQ/s" kill-server 2>/dev/null || true
  rm -rf "$TQ"
}

# bats test_tags=feature:terminal-setup
@test "opening the Claude terminal shows four panes" {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) skip "Windows Git Bash has no tmux" ;; esac
  temp_home
  unset CLAUDE_CONFIG_DIR TMUX TMUX_PANE
  REAL_TMUX="$(command -v tmux)"
  TQ="$(mktemp -d "${TMPDIR:-/tmp}/tq.XXXXXX")"   # short: a socket path has a length limit
  # The real tmux on a server of this test's own, detached because a test has no terminal.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" <<SH
#!/bin/sh
if [ "\$1" = new-session ]; then shift; set -- new-session -d -x 200 -y 50 "\$@"; fi
exec "$REAL_TMUX" -S "$TQ/s" -f /dev/null "\$@"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" SHELL=/bin/sh without_bats_fds bash "$REPO/bin/tmux-quad" >"$BATS_TEST_TMPDIR/quad.log" 2>&1 </dev/null
  run "$REAL_TMUX" -S "$TQ/s" list-panes -a -F pane
  assert_success
  assert_output "$(printf 'pane\npane\npane\npane')"
}

# bats test_tags=feature:terminal-setup
@test "Windows Terminal keeps your default profile when --default-profile is not chosen" {
  temp_home
  wt="$BATS_TEST_TMPDIR/settings.json"
  cp "$REPO/test/fixtures/wsl-tools/windows-terminal.json" "$wt"
  run python3 "$REPO/wsl/wt-profile.py" "$wt" Ubuntu "wsl.exe -d Ubuntu -- tmux-quad" "JetBrainsMono Nerd Font"
  assert_success
  run python3 -c 'import json,sys; sys.stdout.write(json.load(open(sys.argv[1], encoding="utf-8"))["defaultProfile"])' "$wt"
  assert_output "{powershell-guid}"
}

# bats test_tags=feature:terminal-setup
@test "macOS: making the Claude profile iTerm2's default remembers which profile was your default" {
  [ "$(uname -s)" = Darwin ] || skip "iTerm2 is a Mac app"
  [ -d /Applications/iTerm.app ] || skip "install.sh sets the default profile only where /Applications/iTerm.app exists"
  bare_home
  # present already, so that install.sh downloads nothing
  mkdir -p "$TEST_HOME/.local/bin"
  printf '#!/bin/sh\n' > "$TEST_HOME/.local/bin/starship"
  chmod +x "$TEST_HOME/.local/bin/starship"
  defaults write com.googlecode.iterm2 'Default Bookmark Guid' -string my-own-profile
  run bash "$REPO/install.sh" --projects "$TEST_HOME/files" --terminal --default-profile
  assert_success
  run defaults read com.googlecode.iterm2 'Default Bookmark Guid'
  assert_output claude-config-claude-tmux
  run python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("itermDefault"))' "$TEST_HOME/.claude/claude-config.json"
  assert_output my-own-profile
}
