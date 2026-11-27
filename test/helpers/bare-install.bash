# For tests that run ./install.sh themselves:   load ../helpers/bare-install
# bare_home: a throwaway home, the stand-in `defaults` first on PATH (macOS `defaults` ignores HOME) and no
# Claude Code on PATH (running it in a home without a keychain opens a dialog on a Mac).
bare_home() {
  temp_home
  unset CLAUDE_CONFIG_DIR CLAUDE_CODE_PLUGIN_DIRS CLAUDE_CONFIG_INSTALL_OS
  BARE_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BARE_BIN"
  cp "$REPO/test/fixtures/install/defaults" "$BARE_BIN/defaults"
  chmod +x "$BARE_BIN/defaults"
  local d kept="$BARE_BIN" dirs
  IFS=: read -r -a dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    [ -x "$d/claude" ] || [ -x "$d/claude.exe" ] || [ -f "$d/claude.cmd" ] || kept="$kept:$d"
  done
  export PATH="$kept"
  # Stop here, before any install, if either of the two is not as said above.
  [ "$(command -v defaults)" = "$BARE_BIN/defaults" ] && [ -z "$(command -v claude)" ]
}
