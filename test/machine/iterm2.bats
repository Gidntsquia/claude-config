#!/usr/bin/env bats
# iTerm2 on a real Mac. The first test needs a Mac without iTerm2, the others install it, so they stay in
# this order in this file. All change the account they run in, so they run on a CI runner only.
#
# From the second test on: error 1d with the real app. iTerm2 is open and reading its preferences from the clone
# while the update runs (a September install whose clone tracks the plist, then the steps UPDATING.md "Coming from
# an install before v1.3" gives). The update happens once, in the first of these tests that runs (`flow`), which
# records what it saw at each point; each test reads one of those records.

load ../helpers/common

ci_mac() { [ "$(uname -s)" = Darwin ] && { [ "${GITHUB_ACTIONS:-}" = true ] || [ "${ITERM2_LIVE:-}" = 1 ]; }; }

# bats test_tags=feature:terminal-setup
@test "macOS: --terminal with iTerm2 absent skips the profile and --check still passes" {
  if ! ci_mac; then skip "changes the account's real setup: a CI Mac only (ITERM2_LIVE=1 to run anyway)"; fi
  if [ -d /Applications/iTerm.app ]; then skip "iTerm2 is installed: this case needs a Mac without it"; fi
  temp_home
  cd "$REPO"
  run /bin/bash test/helpers/stock-mac.sh ./install.sh --projects "$(printf '\176/files')" --terminal --default-profile --statusline squid --settings merge
  assert_output --partial "iTerm2 is not installed"
  run /bin/bash test/helpers/stock-mac.sh ./install.sh --check
  assert_success
}

SEP_COMMIT=faaebbb   # the last commit that tracks the plist
PLIST=iterm2/com.googlecode.iterm2.plist
DOM=com.googlecode.iterm2

# fact <name> <command...>: run it now, keep its output and exit status for the test that asks
fact() {
  local n="$1" r=0; shift
  "$@" >"$F/$n.out" 2>&1 || r=$?
  echo "$r" > "$F/$n.rc"
}
# saw <name>: the command recorded under that name succeeded
saw() {
  [ -f "$F/$1.rc" ] || { echo "the update run never got as far as '$1':"; cat "$F"/*.out; return 1; }
  cat "$F/$1.out"
  [ "$(cat "$F/$1.rc")" = 0 ]
}
flow() {
  if ! ci_mac; then skip "changes the account's real iTerm2 preferences: a CI Mac only (ITERM2_LIVE=1 to run anyway)"; fi
  F="$BATS_FILE_TMPDIR/flow"
  mkdir "$F" 2>/dev/null || return 0     # already run by an earlier test
  temp_home
  export HOME="$REAL_HOME"               # this one works in the account's own home
  update_run
}

in_clone() { (cd "$K" && /bin/bash "$REPO/test/helpers/stock-mac.sh" ./install.sh "$@"); }
clone_september() { git clone -q "$REPO" "$K" && git -C "$K" checkout -q -B main "$SEP_COMMIT"; }
tracks_plist() { [ -n "$(git -C "$K" ls-files "$PLIST")" ]; }
loads_from_clone() { [ "$(defaults read "$DOM" PrefsCustomFolder 2>/dev/null)" = "$K/iterm2" ]; }
sees_change() { [ -n "$(git -C "$K" status --porcelain -- iterm2)" ]; }
merge_head() { git -C "$K" merge --ff-only "$1" && [ ! -e "$K/$PLIST" ]; }
profile_linked() { [ -f "$DP" ] && [ "$DP" -ef "$K/iterm2/DynamicProfiles/claude-tmux.json" ]; }
profile_named() { local n; n="$(plutil -extract Profiles.0.Name raw -o - "$DP" 2>&1)"; echo "Profiles.0.Name: $n"; [ "$n" = "Claude tmux" ]; }
not_from_clone() { ! defaults read "$DOM" PrefsCustomFolder >/dev/null 2>&1 && [ "$(defaults read "$DOM" LoadPrefsFromCustomFolder)" = 0 ]; }
process_gone() { ! kill -0 "$1" 2>/dev/null; }

update_run() {
  local head f op brew C B
  K="$REAL_HOME/files/claude-config-iterm2-live"; C="$REAL_HOME/.claude"; B="$C/iterm2-prefs-backup"
  DP="$REAL_HOME/Library/Application Support/iTerm2/DynamicProfiles/claude-tmux.json"

  if [ ! -d /Applications/iTerm.app ]; then
    brew="$(command -v brew || echo /opt/homebrew/bin/brew)"
    "$brew" install --cask iterm2 >"$F/brew.log" 2>&1 || tail -3 "$F/brew.log"
  fi
  fact installed test -d /Applications/iTerm.app

  # the September install: the clone at the commit that tracks the plist, the whole-folder links, iTerm2 told to
  # load and save its preferences in the clone
  head="$(git -C "$REPO" rev-parse HEAD)"
  rm -rf "$K"; mkdir -p "$REAL_HOME/files" "$C"
  fact clone clone_september
  [ "$(cat "$F/clone.rc")" = 0 ] || return 0
  fact tracks tracks_plist
  for f in agents commands hooks CLAUDE.md settings.json statusline.sh; do
    if [ -e "$K/$f" ] && [ ! -e "$C/$f" ]; then ln -s "$K/$f" "$C/$f"; fi
  done
  defaults write "$DOM" PrefsCustomFolder -string "$K/iterm2"
  defaults write "$DOM" LoadPrefsFromCustomFolder -bool true
  xattr -dr com.apple.quarantine /Applications/iTerm.app 2>/dev/null || true
  # Each step says what it is about to do: the first run of this once hung here for 6 hours with nothing printed.
  # `open` runs in the background and is killed if it has not returned, so it cannot hold the job.
  echo "# iterm2: open -g -a iTerm" >&3
  : > "$F/launched"
  without_bats_fds open -g -a iTerm </dev/null >"$F/open.log" 2>&1 &
  op=$!
  if ! wait_until 20 pgrep -x iTerm2; then
    # a runner's login session may not let `open` start an app; the app's own program is the same iTerm2
    echo "# iterm2: open did not start it ($(head -3 "$F/open.log" | tr '\n' ' ')); starting the app's program itself" >&3
    without_bats_fds nohup /Applications/iTerm.app/Contents/MacOS/iTerm2 </dev/null >"$F/app.log" 2>&1 &
    wait_until 40 pgrep -x iTerm2 || head -5 "$F/app.log"
  fi
  wait_until 20 process_gone "$op" || kill "$op" 2>/dev/null || true
  fact running pgrep -x iTerm2
  # it has started far enough to have made its own folder
  wait_until 30 test -d "$REAL_HOME/Library/Application Support/iTerm2" || true
  fact reads_clone loads_from_clone
  printf 'what iTerm2 saved while open\n' >> "$K/$PLIST"; cp "$K/$PLIST" "$F/plist.orig"   # iTerm2 rewrites its file
  fact dirty sees_change

  # UPDATING.md "Coming from an install before v1.3", steps 1 to 4, with iTerm2 open the whole time
  mkdir -p "$B" && cp -p "$K/$PLIST" "$B/"                                                 # 1
  git -C "$K" restore iterm2/                                                              # 2
  fact pulled merge_head "$head"                                                           # 3
  [ -e "$K/$PLIST" ] || cp -p "$B/$(basename "$PLIST")" "$K/$PLIST"
  fact install in_clone --projects "$(printf '\176/files')" --terminal --statusline squid --settings replace   # 4

  fact still_running pgrep -x iTerm2
  fact plist_there test -f "$K/$PLIST"
  fact plist_same cmp "$K/$PLIST" "$F/plist.orig"
  fact said_added grep 'iTerm2: added the "Claude tmux" profile' "$F/install.out"
  fact linked profile_linked
  fact named profile_named
  fact converts plutil -convert xml1 -o /dev/null "$DP"
  fact unloaded not_from_clone
  fact check in_clone --check
  fact check_line grep '^PASS.*iTerm2 Claude tmux profile' "$F/check.out"
  # Asking the app itself needs macOS to let this shell send it Apple Events, which a runner may refuse. So the
  # answer is printed and is not one of the checks.
  local ans arc=0
  ans="$(osascript -e 'with timeout of 20 seconds' -e 'tell application "iTerm2" to create window with profile "Claude tmux"' -e 'end timeout' 2>&1)" || arc=$?
  echo "# note iterm2: asking iTerm2 itself for a window with the profile: exit $arc, ${ans:-no output}" >&3
}

teardown_file() {
  if [ -f "$BATS_FILE_TMPDIR/flow/launched" ]; then pkill -x iTerm2 || true; fi
}

# bats test_tags=feature:terminal-setup,escape:1d
@test "macOS: the update starts as it did on the real Mac: iTerm2 running on the clone's plist, its own write a local change, the pull deleting it" {
  flow
  saw installed
  saw clone
  saw tracks
  saw running
  saw reads_clone
  saw dirty
  saw pulled
}

# bats test_tags=feature:terminal-setup,escape:1d
@test "macOS: install.sh under bash 3.2 and the stock PATH succeeds during the update and iTerm2 stays running" {
  flow
  saw install
  saw still_running
}

# bats test_tags=feature:terminal-setup,escape:1d
@test "macOS: an update run while the real iTerm2 reads its preferences from the clone keeps its plist, byte for byte" {
  flow
  saw plist_there
  saw plist_same
}

# bats test_tags=feature:terminal-setup,escape:1d
@test "macOS: the Claude tmux profile is added as a file iTerm2 can read, linked into the clone, and iTerm2 no longer loads its preferences from the clone" {
  flow
  saw said_added
  saw linked
  saw named
  saw converts
  saw unloaded
}

# bats test_tags=feature:terminal-setup,escape:1d
@test "macOS: install.sh --check after the update ends all checks passed and passes the iTerm2 profile" {
  flow
  saw check
  assert_equal "$(tail -n 1 "$F/check.out")" "all checks passed"
  saw check_line
}
