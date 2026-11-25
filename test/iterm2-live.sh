#!/bin/bash
# usage: test/iterm2-live.sh      (the install workflow's macOS job; bash 3.2)
# Error 1d with the real app: iTerm2 is open and reading its preferences from the clone while the update runs.
# Every other test stands a fake `defaults` in for iTerm2 and never starts it. This one installs iTerm2 with
# Homebrew, makes a September install whose clone tracks iterm2/com.googlecode.iterm2.plist, points the real iTerm2
# at that folder, opens it, runs the update as UPDATING.md "Coming from an install before v1.3" gives it (install.sh
# through test/stock-mac.sh), and then checks: the plist iTerm2 was reading is still there, byte for byte; iTerm2 is
# still running; it no longer loads preferences from the clone; and the "Claude tmux" profile is in the file iTerm2
# loads profiles from.
# It changes the real iTerm2 preferences and the real ~/.claude of the account it runs in, so it refuses to run
# anywhere but a CI runner (GITHUB_ACTIONS=true), unless ITERM2_LIVE=1 says the account is a throwaway.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(uname -s)" = Darwin ] || { echo "iterm2-live.sh: macOS only" >&2; exit 2; }
[ "${GITHUB_ACTIONS:-}" = true ] || [ "${ITERM2_LIVE:-}" = 1 ] || { echo "iterm2-live.sh: refusing to run outside CI: it changes this account's real iTerm2 preferences and ~/.claude (ITERM2_LIVE=1 to run anyway)" >&2; exit 2; }
fails=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=$((fails+1)); }
expect() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
SEP_COMMIT=faaebbb   # the last commit that tracks the plist
PLIST=iterm2/com.googlecode.iterm2.plist
DOM=com.googlecode.iterm2
K="$HOME/files/claude-config-iterm2-live"; C="$HOME/.claude"; B="$C/iterm2-prefs-backup"
DP="$HOME/Library/Application Support/iTerm2/DynamicProfiles/claude-tmux.json"

if [ ! -d /Applications/iTerm.app ]; then
  BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"
  "$BREW" install --cask iterm2 2>&1 | tail -3
fi
expect "iterm2: /Applications/iTerm.app is installed" test -d /Applications/iTerm.app

# the September install: the clone at the commit that tracks the plist, the whole-folder links, iTerm2 told to
# load and save its preferences in the clone
head="$(git -C "$R" rev-parse HEAD)"
rm -rf "$K"; mkdir -p "$HOME/files" "$C"
git clone -q "$R" "$K" && git -C "$K" checkout -q -B main "$SEP_COMMIT" || { bad "iterm2: could not clone $R at $SEP_COMMIT"; echo "$fails failure(s)"; exit 1; }
expect "iterm2: the September commit tracks $PLIST" test -n "$(git -C "$K" ls-files "$PLIST")"
for f in agents commands hooks CLAUDE.md settings.json statusline.sh; do [ -e "$K/$f" ] && [ ! -e "$C/$f" ] && ln -s "$K/$f" "$C/$f"; done
defaults write "$DOM" PrefsCustomFolder -string "$K/iterm2"
defaults write "$DOM" LoadPrefsFromCustomFolder -bool true
open -a iTerm
i=0; while [ $i -lt 60 ] && ! pgrep -x iTerm2 >/dev/null; do sleep 1; i=$((i+1)); done
expect "iterm2: iTerm2 is running (pid $(pgrep -x iTerm2 | head -1), after $i s)" pgrep -x iTerm2
sleep 5   # let it read the folder
expect "iterm2: the real iTerm2 is set to load its preferences from the clone" test "$(defaults read "$DOM" PrefsCustomFolder 2>/dev/null)" = "$K/iterm2"
printf 'what iTerm2 saved while open\n' >> "$K/$PLIST"; cp "$K/$PLIST" "$HOME/iterm2-live.plist.orig"   # iTerm2 rewrites its file
expect "iterm2: git sees the rewritten plist as a local change" test -n "$(git -C "$K" status --porcelain -- iterm2)"

# UPDATING.md "Coming from an install before v1.3", steps 1 to 4, with iTerm2 open the whole time
mkdir -p "$B" && cp -p "$K/$PLIST" "$B/"                                                    # 1
git -C "$K" restore iterm2/                                                                 # 2
out="$(git -C "$K" merge --ff-only "$head" 2>&1)" || bad "iterm2: git merge --ff-only failed: $(printf '%s\n' "$out" | tail -1)"   # 3
expect "iterm2: the pull did delete the tracked plist (so step 3's copy back is what keeps it)" test ! -e "$K/$PLIST"
[ -e "$K/$PLIST" ] || cp -p "$B/$(basename "$PLIST")" "$K/$PLIST"
out="$(cd "$K" && /bin/bash "$R/test/stock-mac.sh" ./install.sh --projects "~/files" --terminal --statusline squid --settings replace 2>&1)"; rc=$?   # 4
printf '%s\n' "$out" | sed 's/^/     /'
expect "iterm2: install.sh under /bin/bash 3.2 and the stock PATH exits 0 (got $rc)" test "$rc" = 0

expect "iterm2: iTerm2 is still running after the update" pgrep -x iTerm2
expect "iterm2: the plist iTerm2 was reading exists" test -f "$K/$PLIST"
expect "iterm2: ... and is what iTerm2 last saved, byte for byte" cmp -s "$K/$PLIST" "$HOME/iterm2-live.plist.orig"
expect "iterm2: install.sh said it added the Claude tmux profile" sh -c 'printf "%s\n" "$1" | grep -q "iTerm2: added the \"Claude tmux\" profile"' _ "$out"
expect "iterm2: the profile file iTerm2 loads exists and resolves into the clone" test -f "$DP" -a "$DP" -ef "$K/iterm2/DynamicProfiles/claude-tmux.json"
name="$(plutil -extract Profiles.0.Name raw -o - "$DP" 2>&1)"
expect "iterm2: that file holds the \"Claude tmux\" profile (Profiles.0.Name: $name)" test "$name" = "Claude tmux"
expect "iterm2: plutil reads it as a valid property list" plutil -lint -s "$DP"
expect "iterm2: iTerm2 no longer loads its preferences from the clone" sh -c "! defaults read $DOM PrefsCustomFolder >/dev/null 2>&1 && [ \"\$(defaults read $DOM LoadPrefsFromCustomFolder)\" = 0 ]"
out="$(cd "$K" && /bin/bash "$R/test/stock-mac.sh" ./install.sh --check 2>&1)"; rc=$?
printf '%s\n' "$out" | sed 's/^/     /'
expect "iterm2: --check exits 0 and ends 'all checks passed' (got $rc)" test "$rc$(printf '%s\n' "$out" | tail -1)" = "0all checks passed"
expect "iterm2: --check has a PASS line for the iTerm2 profile" sh -c 'printf "%s\n" "$1" | grep -q "^PASS.*iTerm2 Claude tmux profile"' _ "$out"
# Asking the app itself needs macOS to let this shell send it Apple Events, which a runner may refuse. So the
# answer is printed and is not one of the checks.
ans="$(osascript -e 'with timeout of 20 seconds' -e 'tell application "iTerm2" to create window with profile "Claude tmux"' -e 'end timeout' 2>&1)"; arc=$?
echo "note iterm2: asking iTerm2 itself for a window with the profile: exit $arc, ${ans:-no output}"
pkill -x iTerm2 2>/dev/null
echo
if [ "$fails" = 0 ]; then echo "all iTerm2 checks passed"; else echo "$fails failure(s)"; fi
exit $(( fails > 0 ))
