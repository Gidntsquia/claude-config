#!/usr/bin/env bash
# usage: test/install-scenarios.sh [--terminal|--no-terminal]
# Runs install.sh in throwaway home folders and exits non-zero on any failure:
#   a) an empty ~/.claude
#   b) a ~/.claude that already has the user's settings.json (own model, statusLine and hooks), CLAUDE.md and agents/planner.md
#   sep22)  the layout install.sh made before v1.3 (agents, commands, hooks linked as whole folders; CLAUDE.md,
#           settings.json, statusline.sh linked as files) plus, on macOS, iTerm2 reading its preferences from the clone
#   moved)  install, mv the clone, plain ./install.sh from the new path
#   theirs) their own same-name agent, skill, command, hooks folder and settings.json: all stay byte-identical
#   stock)  /bin/bash with PATH /usr/bin:/bin:/usr/sbin:/sbin; python3 and tmux absent are named before any change
#   odd)    clone and projects under "My Files/Claude Config"
#   noguard)   the usage-guard script absent: each of the 7 settings.json hook commands still exits 0
#   assistant) --agent-clash keep with the user's own agents; the assistant linked into a project finds its MCP
#              server and guard hook inside the clone
#   oldtag)    v1.2.1's own install.sh installs, the clone is pulled to this version, the current install.sh runs
#   nokeychain) macOS: a throwaway home with no Library/Keychains fails the run before any claude command
#   nohook)    every hook command of the installed settings file exits 0 when the file it runs is missing
#   plist)     a September install with iTerm2 reading its preferences from the clone: the update as UPDATING.md
#              gives it leaves the plist iTerm2 is using in place, byte for byte
#   dirty)     an install at v1.2.1, and again at v1.3.0-beta.5, with the user's own edits (uncommitted edits to
#              tracked files, an edit that conflicts with the release, a link replaced with a real file), updated
#              with UPDATING.md steps 5 to 9 as shell commands: every edit survives and --check passes
# a and b run install.sh, then install.sh --check, the personal-path grep and claude doctor from this clone. The
# others run from a copy of the clone inside the throwaway home, and each ends with: --check prints
# `all checks passed`, the copy's `git status --porcelain` is empty, and no *.pre-link* exists under the home.
# Nothing outside the throwaway home is changed: on macOS a fake `defaults` stands in for iTerm2's preferences.
# Used by test/docker-install.sh and .github/workflows/install.yml. Needs bash, git, python3 (or python) and claude.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMFLAG="${1:---terminal}"
# On real WSL the install edits the Windows side (Windows Terminal profile, a scheduled task), which a throwaway
# home folder does not isolate. Run test/docker-install.sh there instead.
if [ -n "${WSL_DISTRO_NAME:-}" ] && [ "$TERMFLAG" = --terminal ]; then
  echo "install-scenarios.sh: refusing to run --terminal on WSL (it would change this PC's Windows Terminal); use test/docker-install.sh" >&2
  exit 2
fi
REAL_HOME="$HOME"
fails=0
ok()   { echo "ok   $*"; }
bad()  { echo "FAIL $*"; fails=$((fails+1)); }
# SCN_ONLY=<name>: run just that one of a, b, sep22, moved, theirs, stock, odd, noguard, assistant, oldtag, nokeychain,
#                  nohook, plist, dirty
# SCN_NEED_OLDTAG=1 (CI): a clone without the old tags and history is a failure, not a skip.
# SCN_LIB=1: define the functions and run nothing (test/rehearsal.sh sources this file for the dirty start state
#            and its checks).
# SCN_NO_PLIST_STEP=1: leave UPDATING.md's copy-the-plist step out of the plist scenario (the red run for error 1d).
want() { [ -z "${SCN_LIB:-}" ] && { [ -z "${SCN_ONLY:-}" ] || [ "$SCN_ONLY" = "$1" ]; }; }
expect() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
PY=python3; command -v python3 >/dev/null 2>&1 && python3 -c 1 >/dev/null 2>&1 || PY=python
# The mod dir as install.sh writes it: on Windows a native C:/... path in a ;-separated list.
MOD="$R/mods/defer-artifact"; SEP=":"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && MOD="$(cygpath -m "$R")/mods/defer-artifact"; SEP=";" ;; esac
# macOS: the run must leave the real keychain search list and default keychain as it found them. Both are written
# to a file here and compared at the end.
KC_START=""
if [ "$(uname -s)" = Darwin ]; then
  real_keychains() { HOME="$REAL_HOME" security list-keychains -d user 2>&1 && HOME="$REAL_HOME" security default-keychain 2>&1; }
  KC_START="$(mktemp "${TMPDIR:-/tmp}/cc-install-keychains.XXXX")"; real_keychains > "$KC_START"
fi
# Ctrl-C or kill: remove the throwaway home of the scenario that was running (its keychain is inside it).
CUR_H=""
cleanup() { [ -z "$CUR_H" ] || rm -rf "$CUR_H"; [ -z "$KC_START" ] || rm -f "$KC_START"; }
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
jget() { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d.get(sys.argv[2])))' "$1" "$2"; }

# The plain grep from the plan (patterns split so this file does not match itself), minus the excluded folders.
grep_clean() {
  local hits
  hits="$(cd "$R" && grep -rIl -e "jax""on" -e "/Us""ers/" -e "/ho""me/" -e "september""-trip" \
            --exclude-dir=.git --exclude-dir=wiki --exclude-dir=archive --exclude-dir=plans --exclude-dir=examples \
            --exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=__pycache__ . 2>/dev/null | grep -v '^\./agents/evals/')"
  [ -z "$hits" ] || { echo "$hits" | sed 's/^/     /'; return 1; }
}

FLAGS=(--projects "~/files" "$TERMFLAG" --statusline squid --settings merge --agent-clash replace)

# keychain_ready <H> <scenario name>: macOS only. No claude command may run in a home with no Library/Keychains: on
# a real Mac that raises the "Keychain Not Found" dialog (a hosted runner has no screen, so it cannot show there).
# One FAIL line naming the home; the scenario then stops before install.sh or claude runs.
keychain_ready() {
  [ "$(uname -s)" = Darwin ] || return 0
  [ -d "$1/Library/Keychains" ] && return 0
  bad "$2: the throwaway home $1 has no Library/Keychains, so install.sh and claude were not run in it (a real Mac would show the Keychain Not Found dialog)"
  return 1
}
# home_setup <H> <scenario name>: what every throwaway home gets before install.sh runs. Returns 1, after one FAIL
# line, when the home cannot be made safe to run claude in.
home_setup() {
  local H="$1" name="$2" err
  mkdir -p "$H/.claude" "$H/.local/bin"
  # claude keeps its install under ~/.local; let the throwaway home see it.
  [ -d "$REAL_HOME/.local/share/claude" ] && mkdir -p "$H/.local/share" && ln -s "$REAL_HOME/.local/share/claude" "$H/.local/share/claude" 2>/dev/null
  [ -f "$REAL_HOME/.claude.json" ] && cp "$REAL_HOME/.claude.json" "$H/.claude.json"
  # macOS: the Security framework looks for keychains in $HOME/Library/Keychains, and a home with no login keychain
  # there raises a "Keychain Not Found" dialog on every claude run. A link to the real folder stops the dialog but
  # breaks isolation: the test claude could read, refresh or overwrite the real Claude Code login. So each throwaway
  # home gets its own empty keychain, which goes when the home is removed. Never click "Reset To Defaults" in that
  # dialog and never script it: it makes a new login keychain and can cut you off from your saved passwords.
  # SCN_NO_KEYCHAIN=1 (the nokeychain scenario only) leaves the keychain out, to show keychain_ready stops the run.
  if [ "$(uname -s)" = Darwin ] && [ -z "${SCN_NO_KEYCHAIN:-}" ]; then
    err="$(mkdir -p "$H/Library/Keychains" 2>&1 && HOME="$H" security create-keychain -p "" "$H/Library/Keychains/login.keychain-db" 2>&1)" \
      || { bad "$name: no throwaway keychain, so install.sh and claude were not run in this home: $(printf '%s' "$err" | tr '\n' ' ')"; return 1; }
  fi
  # macOS: `defaults` ignores HOME and would read and write the real iTerm2 preferences. This one keeps each key as
  # a file under the throwaway home.
  if [ "$(uname -s)" = Darwin ]; then
    mkdir -p "$H/.fake-defaults"
    cat > "$H/.local/bin/defaults" <<'FAKE'
#!/bin/sh
d="$HOME/.fake-defaults"; k="$(printf %s "${3:-}" | tr ' /' '__')"
case "${1:-}" in
  read)   [ -f "$d/$k" ] && cat "$d/$k" || exit 1 ;;
  write)  shift 3; [ $# -gt 1 ] && shift; printf '%s\n' "${1:-}" > "$d/$k" ;;
  delete) [ -f "$d/$k" ] && rm "$d/$k" || exit 1 ;;
esac
FAKE
    chmod +x "$H/.local/bin/defaults"
  fi
  keychain_ready "$H" "$name" || return 1
  return 0
}

scenario() {  # $1 = a|b
  local name="$1" H
  H="$(mktemp -d "${TMPDIR:-/tmp}/cc-install-$name.XXXX")"
  CUR_H="$H"
  echo "== scenario $name ($H) ./install.sh ${FLAGS[*]}"
  (
    trap 'exit 130' INT; trap 'exit 143' TERM
    export HOME="$H" PATH="$H/.local/bin:$PATH"
    [ -n "${USERPROFILE:-}" ] && export USERPROFILE="$H"
    home_setup "$H" "$name" || exit "$fails"
    if [ "$name" = b ]; then
      mkdir -p "$H/.claude/agents"
      printf '%s\n' '{"model": "haiku", "statusLine": {"type": "command", "command": "echo my-status"}, "permissions": {"deny": ["Bash(rm -rf:*)"]}, "env": {"CLAUDE_CODE_PLUGIN_DIRS": "/opt/my-mod"}, "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo my-hook"}]}]}}' > "$H/.claude/settings.json"
      printf 'my own rules\n' > "$H/.claude/CLAUDE.md"
      printf -- '---\nname: planner\ndescription: my planner\n---\nmine\n' > "$H/.claude/agents/planner.md"
      cp "$H/.claude/CLAUDE.md" "$H/claude.md.orig"; cp "$H/.claude/agents/planner.md" "$H/planner.md.orig"
    fi
    cd "$R"
    out="$(./install.sh "${FLAGS[@]}" 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
    expect "$name: install.sh exits 0 (got $rc)" test "$rc" = 0
    out="$(./install.sh --check 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
    expect "$name: install.sh --check exits 0 (got $rc)" test "$rc" = 0
    expect "$name: personal-path grep prints nothing" grep_clean
    expect "$name: bin/find-personal-paths.sh prints nothing" bash "$R/bin/find-personal-paths.sh"
    expect "$name: claude doctor exits 0" sh -c 'claude doctor </dev/null >/dev/null 2>&1'
    expect "$name: claude-config.json names this clone" sh -c "grep -q '\"repo\"' '$H/.claude/claude-config.json'"
    s="$H/.claude/settings.json"
    if [ "$name" = a ]; then
      case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) expect "a: no statusLine on Windows without WSL" sh -c "! grep -q statusline.sh '$s'" ;;
        *) expect "a: settings.json has the repo's statusLine" sh -c "grep -q statusline.sh '$s'" ;;
      esac
      expect "a: CLAUDE.md is linked" test -L "$H/.claude/CLAUDE.md"
      expect "a: env.CLAUDE_CODE_PLUGIN_DIRS is the defer-artifact mod" test "$(jget "$s" env | "$PY" -c 'import json,sys; print(json.load(sys.stdin).get("CLAUDE_CODE_PLUGIN_DIRS",""))')" = "$MOD"
      expect "a: planner agent installed" test -e "$H/.claude/agents/planner.md"
    else
      expect "b: model unchanged" test "$(jget "$s" model)" = '"haiku"'
      expect "b: statusLine unchanged" test "$(jget "$s" statusLine)" = '{"type": "command", "command": "echo my-status"}'
      expect "b: deny list kept and unioned" "$PY" -c "import json,sys;d=json.load(open(sys.argv[1]))['permissions']['deny'];assert d[0]=='Bash(rm -rf:*)' and len(d)>1" "$s"
      expect "b: repo keys added (promptCacheTtl)" sh -c "grep -q promptCacheTtl '$s'"
      expect "b: your CLAUDE_CODE_PLUGIN_DIRS kept, mod joined after it" test "$(jget "$s" env | "$PY" -c 'import json,sys; print(json.load(sys.stdin).get("CLAUDE_CODE_PLUGIN_DIRS",""))')" = "/opt/my-mod$SEP$MOD"
      expect "b: your hooks key kept, every repo hook entry added to it (--settings merge)" "$PY" -c "
import json,sys
u=json.load(open(sys.argv[1])).get('hooks',{}); r=json.load(open(sys.argv[2])).get('hooks',{})
assert {'matcher':'Bash','hooks':[{'type':'command','command':'echo my-hook'}]} == u['PreToolUse'][0]
missing=[(e,h) for e in r for h in r[e] if h not in u.get(e,[])]
assert not missing, missing" "$s" "$R/settings.json"
      expect "b: CLAUDE.md byte-identical" cmp -s "$H/.claude/CLAUDE.md" "$H/claude.md.orig"
      expect "b: planner.md is now the repo's (--agent-clash replace)" sh -c "grep -q '^name: planner\$' '$H/.claude/agents/planner.md' && ! cmp -s '$H/.claude/agents/planner.md' '$H/planner.md.orig'"
    fi
    out="$(./install.sh 2>&1)"; rc=$?
    expect "$name: rerun with no flags exits 0 (got $rc)" test "$rc" = 0
    expect "$name: rerun with no flags reuses saved choices" sh -c "echo \"\$1\" | grep -q 'reusing saved choices'" _ "$out"
    expect "$name: rerun lists the mod dir once" test "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["env"]["CLAUDE_CODE_PLUGIN_DIRS"].split(sys.argv[3]).count(sys.argv[2]))' "$s" "$MOD" "$SEP")" = 1
    expect "$name: no .pre-link anywhere under the home" test -z "$(find "$H" -name '*.pre-link*' 2>/dev/null)"
    out="$(./install.sh --check 2>&1)"
    expect "$name: --check shows every repo agent installed or kept (no SKIP agent)" sh -c "! echo \"\$1\" | grep -q '^SKIP agent'" _ "$out"
    exit "$fails"
  )
  fails=$?   # the subshell started from this count
  rm -rf "$H"; CUR_H=""
}

want a && scenario a
want b && scenario b

# ---- scenarios that run from a copy of the clone ------------------------------------------------------------------
# copy_clone <dst>: this clone's files (tracked and untracked, not git-ignored) as a git repo with one commit, so
# `git status --porcelain` shows anything install.sh changes in it.
copy_clone() {
  mkdir -p "$1" || return 1
  if git -C "$R" rev-parse --git-dir >/dev/null 2>&1; then
    ( cd "$R" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
      | tar --null -T - -cf - ) | tar -xf - -C "$1" || return 1
  else
    ( cd "$R" && tar --exclude=.git -cf - . ) | tar -xf - -C "$1" || return 1
  fi
  git -C "$1" init -q && git -C "$1" add -A >/dev/null 2>&1 && git -C "$1" -c user.name=test -c user.email=test@example.com commit -qm base
}
last() { printf '%s\n' "$1" | tail -1; }
has() { printf '%s\n' "$1" | grep -q -e "$2"; }
# closing <name> <H> <clone>: the three checks every scenario below ends with
closing() {
  local name="$1" H="$2" K="$3" out rc
  out="$(cd "$K" && ./install.sh --check 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "$name: --check exits 0 and ends 'all checks passed' (got $rc, '$(last "$out")')" test "$rc$(last "$out")" = "0all checks passed"
  expect "$name: the clone is unchanged (git status --porcelain is empty)" test -z "$(git -C "$K" status --porcelain 2>&1)"
  expect "$name: no .pre-link anywhere under the home" test -z "$(find "$H" -name '*.pre-link*' 2>/dev/null)"
}
# run_in <name> <function>: run the function in a subshell with a new home; its failures are added to the total
run_in() {
  want "$1" || return 0
  local name="$1" fn="$2" H
  H="$(mktemp -d "${TMPDIR:-/tmp}/cc-install-$name.XXXX")"; H="$(cd "$H" && pwd -P)"
  CUR_H="$H"
  echo "== scenario $name ($H)"
  (
    trap 'exit 130' INT; trap 'exit 143' TERM
    export HOME="$H" PATH="$H/.local/bin:$PATH"
    [ -n "${USERPROFILE:-}" ] && export USERPROFILE="$H"
    home_setup "$H" "$name" || exit "$fails"
    "$fn" "$H"
    exit "$fails"
  )
  fails=$?   # the subshell started from this count
  rm -rf "$H"; CUR_H=""
}
# Real symlinks are needed to build the older layouts by hand (a Windows account without symlink rights gets copies).
can_link() { local d; d="$(mktemp -d)"; : > "$d/a"; ln -s "$d/a" "$d/b" 2>/dev/null; [ -L "$d/b" ]; local rc=$?; rm -rf "$d"; return $rc; }

scn_sep22() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" out rc f
  copy_clone "$K" || { bad "sep22: could not copy the clone"; return; }
  # The Sep 22 install: whole-folder links for agents, commands, hooks; file links; one link per skill.
  for f in agents commands hooks CLAUDE.md settings.json statusline.sh; do ln -s "$K/$f" "$C/$f"; done
  mkdir -p "$C/skills"
  for f in run-agent write-readme retired-skill; do ln -s "$K/skills/$f" "$C/skills/$f"; done   # retired-skill: one the repo no longer has
  if [ "$(uname -s)" = Darwin ]; then   # the Sep 27 iTerm2 setting
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$K/iterm2"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
  fi
  out="$(cd "$K" && ./install.sh --projects "~/files" "$TERMFLAG" --statusline squid --settings replace 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "sep22: install.sh exits 0 (got $rc)" test "$rc" = 0
  expect "sep22: ~/.claude/hooks is now a real folder" sh -c "[ -d '$C/hooks' ] && [ ! -L '$C/hooks' ]"
  # usage-guard is not installed on Windows without WSL
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *) expect "sep22: ~/.claude/hooks/usage-guard is a link" test -L "$C/hooks/usage-guard" ;; esac
  expect "sep22: the clone's hooks/usage-guard is still a real folder" sh -c "[ -d '$K/hooks/usage-guard' ] && [ ! -L '$K/hooks/usage-guard' ]"
  expect "sep22: the commands link (gone from the repo) was removed and said so" sh -c "[ ! -L '$C/commands' ] && [ ! -e '$C/commands' ]"
  expect "sep22: 'removed' printed for commands and the old skill" test "$(printf '%s\n' "$out" | grep -c '^  removed ')" = 2
  expect "sep22: settings.json is a generated file, not a link" sh -c "[ -f '$C/settings.json' ] && [ ! -L '$C/settings.json' ]"
  if [ "$(uname -s)" = Darwin ]; then
    expect "sep22: iTerm2 no longer loads its preferences from the clone" sh -c "! defaults read com.googlecode.iterm2 PrefsCustomFolder >/dev/null 2>&1 && [ \"\$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder)\" = false ]"
  fi
  closing sep22 "$H" "$K"
  out="$(cd "$K" && ./install.sh 2>&1)"; rc=$?
  expect "sep22: rerun with no flags exits 0 (got $rc)" test "$rc" = 0
  closing "sep22 rerun" "$H" "$K"
}

scn_moved() {
  local H="$1" K="$1/old place/claude-config" N="$1/new place/claude-config" C="$1/.claude" out rc
  copy_clone "$K" || { bad "moved: could not copy the clone"; return; }
  out="$(cd "$K" && ./install.sh --projects "~/files" "$TERMFLAG" --statusline squid --settings merge 2>&1)"; rc=$?
  expect "moved: first install exits 0 (got $rc)" test "$rc" = 0
  mkdir -p "$H/new place" && mv "$K" "$N" && rmdir "$H/old place"
  out="$(cd "$N" && ./install.sh 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "moved: plain ./install.sh from the new path exits 0 (got $rc)" test "$rc" = 0
  expect "moved: it says what it relinked" has "$out" "^  relinked $C/skills/run-agent (was $K/skills/run-agent, now missing)\$"
  expect "moved: no clash and no 'kept yours' for our own broken links" sh -c "! printf '%s\n' \"\$1\" | grep -q -e 'clash' -e 'kept yours' -e 'you have your own'" _ "$out"
  expect "moved: no link under ~/.claude is broken" test -z "$(find "$C" -maxdepth 2 -type l ! -exec test -e {} \; -print 2>/dev/null | grep -v '/debug/')"
  # on Windows settings.json carries the clone's native path (C:/...)
  local NN="$N"; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && NN="$(cygpath -m "$N")" ;; esac
  expect "moved: settings.json names the new path only" sh -c "grep -q '$NN/skills/run-agent' '$C/settings.json' && ! grep -q 'old place' '$C/settings.json'"
  closing moved "$H" "$N"
  # Moved again, and this time ~/.claude/claude-config.json is gone too (an install from before the file existed, or
  # a home restored without it): nothing names the old clone, the links alone must be recognised as this installer's.
  local N2="$H/third place/claude-config"
  mkdir -p "$H/third place" && mv "$N" "$N2" && rmdir "$H/new place"; rm -f "$C/claude-config.json"
  out="$(cd "$N2" && ./install.sh 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "moved, no claude-config.json: plain ./install.sh exits 0 (got $rc)" test "$rc" = 0
  expect "moved, no claude-config.json: it says what it relinked" has "$out" "^  relinked $C/skills/run-agent (was $N/skills/run-agent, now missing)\$"
  expect "moved, no claude-config.json: no clash and no 'kept yours' for our own broken links" sh -c "! printf '%s\n' \"\$1\" | grep -q -e 'clash' -e 'kept yours' -e 'you have your own'" _ "$out"
  expect "moved, no claude-config.json: no link under ~/.claude is broken" test -z "$(find "$C" -maxdepth 2 -type l ! -exec test -e {} \; -print 2>/dev/null | grep -v '/debug/')"
  # with no saved choices, the broken links are the only record of what was chosen: the status line and the terminal setup stay
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *)
    expect "moved, no claude-config.json: the status line is still the repo's" sh -c "[ -e '$C/statusline.sh' ] && printf '%s\n' \"\$1\" | grep -q '^  status line: squid\$'" _ "$out"
    if [ "$TERMFLAG" = --terminal ]; then
      expect "moved, no claude-config.json: the terminal setup is still installed (tmux-quad, tmux.conf, starship.toml resolve)" test -e "$H/.local/bin/tmux-quad" -a -e "$H/.tmux.conf" -a -e "$H/.config/starship.toml"
    fi ;;
  esac
  closing "moved, no claude-config.json" "$H" "$N2"
}

scn_theirs() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" out rc
  copy_clone "$K" || { bad "theirs: could not copy the clone"; return; }
  mkdir -p "$C/agents" "$C/skills/run-agent" "$C/commands" "$C/hooks"
  printf -- '---\nname: planner\ndescription: my planner\n---\nmine\n' > "$C/agents/planner.md"
  printf -- '---\nname: run-agent\ndescription: my own skill\n---\nmine\n' > "$C/skills/run-agent/SKILL.md"
  printf 'my own command\n' > "$C/commands/review.md"
  printf '#!/bin/sh\necho my-hook\n' > "$C/hooks/my-hook.sh"
  printf '%s\n' '{"model": "haiku", "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "sh ~/.claude/hooks/my-hook.sh"}]}]}}' > "$C/settings.json"
  mkdir -p "$H/orig" && cp -R "$C/agents" "$C/skills" "$C/commands" "$C/hooks" "$C/settings.json" "$H/orig/"
  out="$(cd "$K" && ./install.sh --projects "~/files" --no-terminal --statusline keep --settings keep 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "theirs: install.sh exits 0 with no --agent-clash (got $rc)" test "$rc" = 0
  expect "theirs: 'kept yours' printed for the agent" has "$out" "^  kept yours: $C/agents/planner.md (repo's not installed)\$"
  expect "theirs: 'kept yours' printed for the skill" has "$out" "^  kept yours: $C/skills/run-agent (repo's not installed)\$"
  expect "theirs: agent byte-identical" cmp -s "$C/agents/planner.md" "$H/orig/agents/planner.md"
  expect "theirs: skill byte-identical" diff -r "$C/skills/run-agent" "$H/orig/skills/run-agent"
  expect "theirs: command byte-identical" diff -r "$C/commands" "$H/orig/commands"
  expect "theirs: their hook file byte-identical" cmp -s "$C/hooks/my-hook.sh" "$H/orig/hooks/my-hook.sh"
  expect "theirs: settings.json byte-identical" cmp -s "$C/settings.json" "$H/orig/settings.json"
  expect "theirs: the repo's other agents and skills are installed next to theirs" sh -c "[ -e '$C/agents/worker.md' ] && [ -e '$C/skills/write-readme/SKILL.md' ]"
  # A file of the user's that git does not track and that names a home folder (notes, a kept copy): --check lists it
  # as WARN and still passes. The path is written in two halves so this script holds no such path itself.
  printf 'kept from my old machine: %s\n' "/Us""ers/someone/notes" > "$K/my-kept-notes.md"
  out="$(cd "$K" && ./install.sh --check 2>&1)"; rc=$?
  expect "theirs: an untracked file with a personal path is a WARN line naming it" has "$out" "^WARN personal paths in untracked files.*my-kept-notes.md"
  expect "theirs: ... and no FAIL line (exit $rc, '$(last "$out")')" sh -c "! printf '%s\n' \"\$1\" | grep -q '^FAIL' && [ \"\$2\" = '0all checks passed' ]" _ "$out" "$rc$(last "$out")"
  rm -f "$K/my-kept-notes.md"
  closing theirs "$H" "$K"
}

# snap <home>: every path under the home but the clone and Apple python's own bytecode cache (~/Library/Caches)
snap() { find "$1" \( -path "$1/files" -o -path "$1/Library/Caches" \) -prune -o -print | grep -vx "$1/Library" | sort; }
scn_stock() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" out rc bare t before after
  local STOCK="/usr/bin:/bin:/usr/sbin:/sbin"
  copy_clone "$K" || { bad "stock: could not copy the clone"; return; }
  # 1. python3 and tmux both absent: a PATH that holds only what install.sh runs before it looks for them.
  bare="$H/bare-bin"; mkdir -p "$bare"
  for t in uname sed head grep dirname basename cat; do ln -s "$(PATH="$STOCK" command -v "$t")" "$bare/$t"; done
  before="$(snap "$H")"
  out="$(cd "$K" && PATH="$bare" /bin/bash ./install.sh --projects "~/files" --terminal --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "stock: python3 and tmux absent: exits non-zero (got $rc)" test "$rc" != 0
  expect "stock: names python3 and its install command" has "$out" "python3 is missing.*Install it with: ..*"
  expect "stock: names tmux and its install command" has "$out" "tmux is missing.*Install it with: ..*tmux"
  expect "stock: nothing was changed" test "$before" = "$(snap "$H")"
  # 2. tmux absent, python3 present (a stock Mac after xcode-select --install; elsewhere the same PATH minus tmux).
  for t in $(PATH="$STOCK" /bin/bash -c 'IFS=:; for d in $PATH; do ls "$d" 2>/dev/null; done' | sort -u); do
    [ "$t" = tmux ] || [ -e "$bare/$t" ] || ln -s "$(PATH="$STOCK" command -v "$t" 2>/dev/null || echo /nonexistent)" "$bare/$t" 2>/dev/null
  done
  before="$(snap "$H")"
  if PATH="$bare" /bin/bash -c 'python3 -c "import json"' >/dev/null 2>&1; then
    out="$(cd "$K" && PATH="$bare" /bin/bash ./install.sh --projects "~/files" --terminal --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
    expect "stock: tmux absent with --terminal: exits non-zero (got $rc)" test "$rc" != 0
    expect "stock: names tmux and its install command" has "$out" "tmux is missing.*Install it with: ..*tmux"
    after="$(snap "$H")"
    expect "stock: nothing was changed" test "$before" = "$after"
    [ "$before" = "$after" ] || diff <(echo "$before") <(echo "$after") | sed 's/^/     /'
    # 3. /bin/bash (3.2 on macOS) with the stock PATH and no terminal setup: installs, and names the claude command to run.
    out="$(cd "$K" && PATH="$H/.local/bin:$bare" /bin/bash ./install.sh --projects "~/files" --no-terminal --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
    expect "stock: /bin/bash install with the stock PATH exits 0 (got $rc)" test "$rc" = 0
    expect "stock: claude absent: prints the claude mcp add command to run later" has "$out" "claude mcp add --transport stdio --scope user run-agent"
    # Claude Code installed afterwards: a plain rerun registers the server, and --check passes.
    out="$(cd "$K" && /bin/bash ./install.sh 2>&1)"; rc=$?
    expect "stock: rerun once claude is on PATH exits 0 (got $rc)" test "$rc" = 0
    closing stock "$H" "$K"
  else
    echo "skip stock 2-3: /usr/bin has no working python3 on this machine"
  fi
}

scn_odd() {
  local H="$1" K="$1/My Files/Claude Config" C="$1/.claude" out rc
  copy_clone "$K" || { bad "odd: could not copy the clone"; return; }
  out="$(cd "$K" && ./install.sh --projects "$H/My Files/My Projects" "$TERMFLAG" --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "odd: install.sh exits 0 from 'My Files/Claude Config' (got $rc)" test "$rc" = 0
  expect "odd: the projects folder with a space exists" test -d "$H/My Files/My Projects"
  expect "odd: claude-config.json keeps both paths whole" test "$(jget "$C/claude-config.json" repo)$(jget "$C/claude-config.json" projects)" = "\"$K\"\"$H/My Files/My Projects\""
  closing odd "$H" "$K"
  out="$(cd "$K" && ./install.sh 2>&1)"; rc=$?
  expect "odd: rerun with no flags exits 0 (got $rc)" test "$rc" = 0
  closing "odd rerun" "$H" "$K"
}

# The 7 usage-guard hook commands of the installed settings.json, run as Claude Code runs them (sh -c, the hook's
# JSON on stdin) with the script gone. Before 01304e8 each ended in exit 2, which blocks the tool call: with the
# script missing, no Bash, Agent or Edit call could run, so the session could not even repair itself.
scn_noguard() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" out rc n i G="usage-guard"
  copy_clone "$K" || { bad "noguard: could not copy the clone"; return; }
  out="$(cd "$K" && ./install.sh --projects "~/files" --no-terminal --statusline squid --settings replace 2>&1)"; rc=$?
  expect "noguard: install.sh exits 0 (got $rc)" test "$rc" = 0
  # the throwaway home's link to the clone's folder goes (it is never installed on Windows without WSL)
  if [ -L "$C/hooks/$G" ]; then rm "$C/hooks/$G"; fi
  expect "noguard: the guard script is absent from the throwaway home" test ! -e "$C/hooks/$G/usage_guard.py"
  mkdir -p "$H/hookcmds" "$H/hooktmp"
  n="$("$PY" - "$C/settings.json" "$H/hookcmds" <<'PYEOF'
import json, os, sys
n = 0
for entries in json.load(open(sys.argv[1])).get("hooks", {}).values():
    for e in entries:
        for h in e.get("hooks", []):
            if "usage_guard.py" in h.get("command", ""):
                n += 1
                open(os.path.join(sys.argv[2], str(n)), "w", newline="\n").write(h["command"])
print(n)
PYEOF
)"
  expect "noguard: the installed settings.json has 7 usage-guard hook commands (got $n)" test "$n" = 7
  i=1
  while [ "$i" -le "${n:-0}" ]; do
    out="$(printf '%s' '{"session_id": "scn-noguard", "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "true"}}' \
      | TMPDIR="$H/hooktmp" sh -c "$(cat "$H/hookcmds/$i")" 2>&1)"; rc=$?
    expect "noguard: hook command $i of $n exits 0 with the script absent (got $rc)" test "$rc" = 0
    if [ "$i" = 1 ]; then expect "noguard: the first call says the guard is off" has "$out" 'usage-guard: script missing at .*usage_guard.py, guard is off'
    else expect "noguard: call $i prints nothing more (one notice per session)" test -z "$out"; fi
    i=$((i+1))
  done
  out="$(cd "$K" && ./install.sh 2>&1)"; rc=$?   # puts the link back
  expect "noguard: rerun exits 0 (got $rc)" test "$rc" = 0
  closing noguard "$H" "$K"
}

# The beta.4 known issue: with --agent-clash keep the repo's assistant was installed as a renamed copy under
# ~/.claude/agents, and its frontmatter looked for mcp/server.py and hooks/guard.py next to that copy. Since e472f6a
# the agent lives in assistant/ and runs only from a project that links it.
scn_assistant() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" P="$1/files/my-project" out rc got
  copy_clone "$K" || { bad "assistant: could not copy the clone"; return; }
  mkdir -p "$C/agents"
  printf -- '---\nname: planner\ndescription: my planner\n---\nmine\n' > "$C/agents/planner.md"
  out="$(cd "$K" && ./install.sh --projects "~/files" --no-terminal --statusline squid --settings merge --agent-clash keep 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "assistant: install.sh --agent-clash keep exits 0 (got $rc)" test "$rc" = 0
  expect "assistant: keep made the renamed copy for the clashing agent (planner-claude-config)" test -f "$C/agents/planner-claude-config.md"
  expect "assistant: no assistant file or copy under ~/.claude/agents" test -z "$(ls "$C/agents" | grep -i assistant)"
  mkdir -p "$P/.claude/agents" && ln -s "$K/assistant/assistant.md" "$P/.claude/agents/assistant.md"
  # The two commands from the agent's frontmatter, run from the project as Claude Code runs them, with the program
  # they start (uv run --script) swapped for echo: what is printed is the file each would run.
  "$PY" - "$K/assistant/assistant.md" "$H/asst-mcp" "$H/asst-hook" <<'PYEOF'
import json, re, sys
front = open(sys.argv[1], encoding="utf-8").read().split("\n---", 1)[0]
args = json.loads(re.search(r"^\s*args:\s*(\[.*\])\s*$", front, re.M).group(1))
hook = json.loads(re.search(r"^\s*command:\s*(\"bash -c .*\")\s*$", front, re.M).group(1))
run = "exec uv run --script --quiet"
assert args[0] == "-c" and run in args[1] and run in hook
open(sys.argv[2], "w", newline="\n").write(args[1].replace(run, "echo"))
open(sys.argv[3], "w", newline="\n").write(hook.replace(run, "echo"))
PYEOF
  expect "assistant: both frontmatter commands were read from assistant.md" test -s "$H/asst-mcp" -a -s "$H/asst-hook"
  got="$(cd "$P" && bash -c "$(cat "$H/asst-mcp")" 2>&1)"
  expect "assistant: the MCP server resolves to the clone's assistant/mcp/server.py (got $got)" test -f "$got" -a "$got" -ef "$K/assistant/mcp/server.py"
  got="$(cd "$P" && sh -c "$(cat "$H/asst-hook")" 2>&1)"
  expect "assistant: the guard hook resolves to the clone's assistant/hooks/guard.py (got $got)" test -f "$got" -a "$got" -ef "$K/assistant/hooks/guard.py"
  out="$(cd "$K" && ./install.sh --check 2>&1)"
  expect "assistant: --check has a PASS line for the assistant agent" has "$out" "^PASS assistant agent"
  closing assistant "$H" "$K"
}

# A real older install, then the update as UPDATING.md gives it ("Coming from an install before v1.3"): v1.2.1's
# own install.sh, iTerm2 loading its preferences from the clone, pull, the current install.sh. sep22 builds the
# older layout by hand; this one lets the old script make it.
scn_oldtag() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" out rc head
  head="$(git -C "$R" rev-parse HEAD)"
  git clone -q "$R" "$K" 2>/dev/null && git -C "$K" checkout -q v1.2.1 2>/dev/null || { bad "oldtag: could not clone $R at v1.2.1"; return; }
  if [ "$(uname -s)" = Darwin ]; then   # the Sep 27 setting, still on the real Mac on Nov 21
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$K/iterm2"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
  fi
  out="$(cd "$K" && ./install.sh --projects "~/files" "$TERMFLAG" --statusline squid --settings replace 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "oldtag: v1.2.1's install.sh exits 0 (got $rc)" test "$rc" = 0
  expect "oldtag: v1.2.1 linked settings.json into the clone (the older layout)" test -L "$C/settings.json"
  if [ "$(uname -s)" = Darwin ]; then
    # v1.2.1 already undid that setting when it installed. The real Mac's install was older than v1.2.1 and still had
    # it at the pull, so it is put back here: the pull happens with iTerm2 pointed at the clone.
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$K/iterm2"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
  fi
  # The pull: to this clone's HEAD, then its uncommitted files on top (so the scripts under test are the ones here).
  git -C "$K" checkout -q "$head" || { bad "oldtag: could not check out $head"; return; }
  ( cd "$R" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
    | tar --null -T - -cf - ) | tar -xf - -C "$K" || { bad "oldtag: could not copy this clone's files"; return; }
  git -C "$K" add -A >/dev/null 2>&1; git -C "$K" diff --cached --quiet || git -C "$K" -c user.name=test -c user.email=test@example.com commit -qm "working tree"
  if [ "$(uname -s)" = Darwin ]; then
    expect "oldtag: after the pull, before install.sh, iTerm2 still points at the clone's iterm2/" test "$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null)" = "$K/iterm2"
  fi
  out="$(cd "$K" && ./install.sh 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "oldtag: the current install.sh, no flags, exits 0 (got $rc)" test "$rc" = 0
  expect "oldtag: ~/.claude/hooks is a real folder" sh -c "[ -d '$C/hooks' ] && [ ! -L '$C/hooks' ]"
  expect "oldtag: the clone's hooks/usage-guard is still a real folder" sh -c "[ -d '$K/hooks/usage-guard' ] && [ ! -L '$K/hooks/usage-guard' ]"
  expect "oldtag: settings.json is a generated file, not a link" sh -c "[ -f '$C/settings.json' ] && [ ! -L '$C/settings.json' ]"
  if [ "$(uname -s)" = Darwin ]; then
    expect "oldtag: iTerm2 no longer loads its preferences from the clone" sh -c "! defaults read com.googlecode.iterm2 PrefsCustomFolder >/dev/null 2>&1 && [ \"\$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder)\" = false ]"
  fi
  closing oldtag "$H" "$K"
}

# Every hook command of the installed settings file, whatever it runs, with every file under ~/.claude gone (HOME is
# an empty folder for the call). noguard covers the 7 usage-guard commands with one script removed; this covers every
# command in the file, so a hook added later that runs a linked file without looking for it first fails here.
scn_nohook() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" out rc n i
  copy_clone "$K" || { bad "nohook: could not copy the clone"; return; }
  out="$(cd "$K" && ./install.sh --projects "~/files" --no-terminal --statusline squid --settings replace 2>&1)"; rc=$?
  expect "nohook: install.sh exits 0 (got $rc)" test "$rc" = 0
  mkdir -p "$H/hookcmds" "$H/hooktmp" "$H/empty-home"
  n="$("$PY" - "$C/settings.json" "$H/hookcmds" <<'PYEOF'
import json, os, sys
n = 0
for event, entries in sorted(json.load(open(sys.argv[1], encoding="utf-8")).get("hooks", {}).items()):
    for e in entries:
        for h in e.get("hooks", []):
            if h.get("type") == "command" and h.get("command"):
                n += 1
                open(os.path.join(sys.argv[2], str(n)), "w", newline="\n", encoding="utf-8").write(h["command"])
                open(os.path.join(sys.argv[2], str(n) + ".name"), "w", encoding="utf-8").write("%s %s" % (event, e.get("matcher", "(any)")))
print(n)
PYEOF
)"
  expect "nohook: the installed settings file has at least 8 hook commands (got $n)" test "${n:-0}" -ge 8
  i=1
  while [ "$i" -le "${n:-0}" ]; do
    out="$(printf '%s' '{"session_id": "scn-nohook", "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "true"}, "prompt": "/run-agent jobs"}' \
      | HOME="$H/empty-home" TMPDIR="$H/hooktmp" sh -c "$(cat "$H/hookcmds/$i")" 2>&1)"; rc=$?
    expect "nohook: hook $i of $n ($(cat "$H/hookcmds/$i.name")) exits 0 with the file it runs missing (got $rc: $(printf '%s' "$out" | head -1 | cut -c1-120))" test "$rc" = 0
    i=$((i+1))
  done
  closing nohook "$H" "$K"
}

# ---- updating an install that has the user's own edits ---------------------------------------------------------------
GITID=(-c user.name=test -c user.email=test@example.com)
# target_commit <scratch dir>: prints a commit that holds this clone's HEAD plus its uncommitted files (the release
# under test), made in a scratch clone so nothing is written to this one.
target_commit() {
  local T="$1" head
  head="$(git -C "$R" rev-parse HEAD)" || return 1
  git clone -q "$R" "$T" 2>/dev/null && git -C "$T" checkout -q "$head" 2>/dev/null || return 1
  ( cd "$R" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
    | tar --null -T - -cf - ) | tar -xf - -C "$T" || return 1
  ( cd "$R" && git ls-files -z --deleted ) | ( cd "$T" && xargs -0 rm -f -- 2>/dev/null )
  git -C "$T" add -A >/dev/null 2>&1
  git -C "$T" diff --cached --quiet || git -C "$T" "${GITID[@]}" commit -qm "working tree" || return 1
  git -C "$T" rev-parse HEAD
}
# old_clone <clone> <start commit> <target repo> <target commit>: the user's clone as it stands before the update:
# branch main at the start commit, with the release under test fetched and waiting.
old_clone() {
  git clone -q "$R" "$1" 2>/dev/null || return 1
  git -C "$1" fetch -q "$3" HEAD 2>/dev/null || return 1
  git -C "$1" checkout -q -B main "$2" 2>/dev/null
}
# update_steps <clone> <target commit>: UPDATING.md steps 5 to 8 as the shell commands the file gives.
# Never reset --hard, clean or a forced push (UPDATING.md "Rules").
update_steps() {
  local K="$1" to="$2" stashed="" out rc
  if [ -n "$(git -C "$K" status --porcelain)" ]; then                                   # step 5
    git -C "$K" "${GITID[@]}" stash push --include-untracked -q -m "pre-update $(date +%F)" || { bad "update: git stash push failed"; return 1; }
    stashed=1
  fi
  out="$(git -C "$K" merge --ff-only "$to" 2>&1)" || { bad "update: git merge --ff-only failed: $(last "$out")"; return 1; }   # step 6
  if [ -n "$stashed" ]; then                                                           # step 7
    out="$(git -C "$K" "${GITID[@]}" stash pop 2>&1)"; rc=$?
    UPDATE_POP_CONFLICTS="$(git -C "$K" diff --name-only --diff-filter=U | tr '\n' ' ')"
    if [ "$rc" != 0 ]; then
      out="$("$PY" "$K/bin/resolve-kept-edits.py" "$K" 2>&1)" || { bad "update: resolve-kept-edits.py left a conflict: $(printf '%s' "$out" | tr '\n' ' ')"; return 1; }
      echo "$out" | sed 's/^/     /'
      git -C "$K" stash drop -q || { bad "update: git stash drop failed"; return 1; }
    fi
  fi
  out="$(cd "$K" && ./install.sh 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'           # step 8
  UPDATE_INSTALL_OUT="$out"
  expect "update: the current install.sh, no flags, exits 0 (got $rc)" test "$rc" = 0
}

# The start state for `dirty` and for test/rehearsal.sh: the start commit's own install.sh, then four things the
# user did since. dirty_setup <home> <clone> <start commit> <target repo> <target commit>
MINE_RULE="- my own rule: say which file you changed"
MINE_NOTE="My own note for the helper: I work in Eastern time."
dirty_setup() {
  local H="$1" K="$2" from="$3" C="$1/.claude" out rc
  old_clone "$K" "$from" "$4" "$5" || { bad "dirty: could not clone $R at $from"; return 1; }
  out="$(cd "$K" && ./install.sh --projects "~/files" "$TERMFLAG" --statusline squid --settings replace 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "dirty: the install.sh of $from exits 0 (got $rc)" test "$rc" = 0
  expect "dirty: the clone is clean after that install" test -z "$(git -C "$K" status --porcelain 2>&1)"
  # 1. uncommitted edits to tracked files
  printf '\n%s\n' "$MINE_RULE" >> "$K/CLAUDE.md"
  printf '\n%s\n' "$MINE_NOTE" >> "$K/agents/helper.md"
  printf 'notes I keep in the clone\n' > "$K/my-notes.md"
  # 2. an edit that conflicts with the release: the first line of the settings file that the release changed and
  #    that holds a rule or a hook command becomes his own.
  out="$("$PY" - "$K/settings.json" <(git -C "$K" show "$5:settings.json") <<'PYEOF'
import difflib, re, sys
old = open(sys.argv[1], encoding="utf-8").read().split("\n")
new = open(sys.argv[2], encoding="utf-8").read().split("\n")
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
    if tag not in ("replace", "delete"):
        continue
    for i in range(i1, i2):
        m = re.match(r'^(\s*)"command": "(.*)"(,?)$', old[i])
        if m:
            old[i] = '%s"command": "echo my-own-hook >/dev/null; %s"%s' % m.groups()
        elif re.match(r'^\s*"[^"]*",?$', old[i]) and i > 0 and old[i - 1].rstrip().endswith(("[", ",")):
            old[i] = re.sub(r'"[^"]*"', '"Bash(my-own-tool:*)"', old[i], count=1)
        else:
            continue
        open(sys.argv[1], "w", encoding="utf-8", newline="\n").write("\n".join(old))
        print("line %d: %s" % (i + 1, old[i].strip()[:100]))
        sys.exit(0)
sys.exit("no line of the settings file that the release changed holds a rule or a hook command")
PYEOF
)" || { bad "dirty: could not make the conflicting edit: $out"; return 1; }
  echo "     his conflicting edit, settings file $out"
  # 3. a link he replaced with a real file: his own skill folder where the installer's link was
  expect "dirty: ~/.claude/skills/review-skill is a link before he replaces it" test -L "$C/skills/review-skill"
  rm -f "$C/skills/review-skill" && mkdir -p "$C/skills/review-skill"
  printf -- '---\nname: review-skill\ndescription: my own review skill\n---\nmine, not a link\n' > "$C/skills/review-skill/SKILL.md"
  mkdir -p "$H/orig" && cp -R "$C/skills/review-skill" "$H/orig/review-skill"
  git -C "$K" rev-parse HEAD > "$H/start-commit"
}
# links_outside <dir> <clone>: the links up to two levels under <dir> that do not resolve inside <clone>
links_outside() {
  local f t
  find "$1" -maxdepth 2 -type l 2>/dev/null | grep -v '/debug/' | while IFS= read -r f; do
    t="$(cd "$(dirname "$f")" 2>/dev/null && cd "$(dirname "$(readlink "$f")")" 2>/dev/null && pwd -P)"
    case "$t/" in ("$2"/*) ;; (*) printf '%s ' "$f" ;; esac
  done
}
# dirty_asserts <home> <clone> <target commit>: plans R7, R8, R9 and the closing checks
dirty_asserts() {
  local H="$1" K="$2" to="$3" C="$1/.claude" out rc f
  expect "dirty: the clone is at the release ($(git -C "$K" rev-parse --short HEAD 2>&1))" test "$(git -C "$K" rev-parse HEAD 2>&1)" = "$to"
  # R7
  expect "dirty: his line is still in CLAUDE.md" grep -qxF -- "$MINE_RULE" "$K/CLAUDE.md"
  expect "dirty: his line is still in agents/helper.md" grep -qxF -- "$MINE_NOTE" "$K/agents/helper.md"
  expect "dirty: his untracked notes file is still in the clone" test "$(cat "$K/my-notes.md" 2>&1)" = "notes I keep in the clone"
  expect "dirty: git stash list is empty" test -z "$(git -C "$K" stash list 2>&1)"
  expect "dirty: ~/.claude/CLAUDE.md shows his line too" grep -qxF -- "$MINE_RULE" "$C/CLAUDE.md"
  # R8
  f="$K/settings.json"
  expect "dirty: his edit is still in the clone's settings file" grep -q -e 'my-own-hook' -e 'my-own-tool' "$f"
  expect "dirty: no conflict markers in the files he edited" test -z "$(grep -l -E '^(<<<<<<< |>>>>>>> |=======$)' "$f" "$K/CLAUDE.md" "$K/agents/helper.md" 2>/dev/null)"
  expect "dirty: the settings file parses as JSON and holds every line of the release's beside his" "$PY" - "$f" <(git -C "$K" show "$to:settings.json") <<'PYEOF'
import json, sys
mine = json.load(open(sys.argv[1], encoding="utf-8")); rel = json.load(open(sys.argv[2], encoding="utf-8"))
def missing(m, r, path=""):
    if isinstance(r, dict):
        if not isinstance(m, dict): return [path]
        return [x for k, v in r.items() for x in (missing(m[k], v, path + "/" + k) if k in m else [path + "/" + k])]
    if isinstance(r, list):
        if not isinstance(m, list): return [path]
        return [path + "[%d]" % i for i, x in enumerate(r) if x not in m]
    return [] if m == r else [path]
gone = missing(mine, rel)
assert not gone, "the release's values missing from the merged file: %s" % gone[:6]
PYEOF
  expect "dirty: ~/.claude's settings file holds his edit too" grep -q -e 'my-own-hook' -e 'my-own-tool' "$C/settings.json"
  expect "dirty: ~/.claude's settings file parses as JSON" "$PY" -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$C/settings.json"
  # R9
  expect "dirty: his real folder ~/.claude/skills/review-skill is byte-identical" diff -r "$C/skills/review-skill" "$H/orig/review-skill"
  expect "dirty: ... and is still a real folder, not a link" sh -c "[ -d '$C/skills/review-skill' ] && [ ! -L '$C/skills/review-skill' ]"
  out=""; for f in "$K"/skills/*/; do f="$(basename "$f")"; [ "$f" = review-skill ] && continue
    [ -L "$C/skills/$f" ] && [ "$C/skills/$f" -ef "$K/skills/$f" ] || out="$out $f"; done
  expect "dirty: every other skill is a link into the clone (not:$out)" test -z "$out"
  expect "dirty: the agents resolve into the clone" test "$C/agents/planner.md" -ef "$K/agents/planner.md"
  out="$(links_outside "$C" "$K")"
  expect "dirty: every link under ~/.claude points into the clone (not: $out)" test -z "$out"
  # closing: --check, no backup copies, nothing but his edits differs from the release
  out="$(cd "$K" && ./install.sh --check 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "dirty: --check exits 0 and ends 'all checks passed' (got $rc, '$(last "$out")')" test "$rc$(last "$out")" = "0all checks passed"
  expect "dirty: no .pre-link anywhere under the home" test -z "$(find "$H" -name '*.pre-link*' 2>/dev/null)"
  out="$(git -C "$K" status --porcelain 2>&1 | sed 's/^...//' | LC_ALL=C sort | tr '\n' ' ')"
  expect "dirty: git status lists his four files and nothing else (lists: $out)" test "$out" = "CLAUDE.md agents/helper.md my-notes.md settings.json "
}
scn_dirty_from() {  # <home> <start commit>
  local H="$1" from="$2" K="$1/files/claude-config" to
  to="$(target_commit "$H/target")" || { bad "dirty from $from: could not build the release commit"; return; }
  dirty_setup "$H" "$K" "$from" "$H/target" "$to" || return
  UPDATE_POP_CONFLICTS=""; UPDATE_INSTALL_OUT=""
  update_steps "$K" "$to" || return
  expect "dirty from $from: the stash pop did stop on a conflict in the settings file (conflicted: ${UPDATE_POP_CONFLICTS:-none})" has "$UPDATE_POP_CONFLICTS" 'settings\.json'
  expect "dirty from $from: install.sh said it kept his skill" has "$UPDATE_INSTALL_OUT" "^  kept yours: $H/.claude/skills/review-skill (repo's not installed)\$"
  dirty_asserts "$H" "$K" "$to"
}
scn_dirty_v121() { scn_dirty_from "$1" v1.2.1; }
scn_dirty_beta5() { scn_dirty_from "$1" v1.3.0-beta.5; }

# Error 1d, the harm itself: a September install tracked iterm2/com.googlecode.iterm2.plist, iTerm2 was set to load
# and save its preferences there, and the release deletes that file, so a pull takes away the file iTerm2 is using.
# UPDATING.md "Coming from an install before v1.3" copies it out first and puts it back after the pull.
SEP_COMMIT=faaebbb   # the last commit that tracks the plist (the parent of f3fd85b, 2026-10-26)
PLIST=iterm2/com.googlecode.iterm2.plist
scn_plist() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" B="$1/.claude/iterm2-prefs-backup" to f out rc
  to="$(target_commit "$H/target")" || { bad "plist: could not build the release commit"; return; }
  old_clone "$K" "$SEP_COMMIT" "$H/target" "$to" || { bad "plist: could not clone $R at $SEP_COMMIT"; return; }
  expect "plist: the September commit tracks $PLIST" test -n "$(git -C "$K" ls-files "$PLIST")"
  # the September layout, as sep22 builds it
  for f in agents commands hooks CLAUDE.md settings.json statusline.sh; do [ -e "$K/$f" ] && ln -s "$K/$f" "$C/$f"; done
  if [ "$(uname -s)" = Darwin ]; then
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$K/iterm2"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
  fi
  printf 'what iTerm2 saved on quit\n' >> "$K/$PLIST"; cp "$K/$PLIST" "$H/plist.orig"   # iTerm2 rewrites its file
  expect "plist: git sees iTerm2's write as a local change" test -n "$(git -C "$K" status --porcelain -- iterm2)"
  # UPDATING.md "Coming from an install before v1.3", steps 1 to 4
  if [ -z "${SCN_NO_PLIST_STEP:-}" ]; then mkdir -p "$B" && cp -p "$K/$PLIST" "$B/"; fi                  # 1
  git -C "$K" restore iterm2/                                                                              # 2
  out="$(git -C "$K" merge --ff-only "$to" 2>&1)" || { bad "plist: git merge --ff-only failed: $(last "$out")"; return; }   # 3
  if [ -z "${SCN_NO_PLIST_STEP:-}" ] && [ ! -e "$K/$PLIST" ]; then cp -p "$B/$(basename "$PLIST")" "$K/$PLIST"; fi
  expect "plist: after the pull the plist iTerm2 is using is in place" test -f "$K/$PLIST"
  expect "plist: ... and is what iTerm2 last saved, byte for byte" cmp -s "$K/$PLIST" "$H/plist.orig"
  expect "plist: the copy outside the clone is byte-identical too" cmp -s "$B/$(basename "$PLIST")" "$H/plist.orig"
  out="$(cd "$K" && ./install.sh --projects "~/files" "$TERMFLAG" --statusline squid --settings replace 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'   # 4
  expect "plist: the current install.sh exits 0 (got $rc)" test "$rc" = 0
  expect "plist: install.sh left the plist alone" cmp -s "$K/$PLIST" "$H/plist.orig"
  if [ "$(uname -s)" = Darwin ]; then
    expect "plist: iTerm2 no longer loads its preferences from the clone" sh -c "! defaults read com.googlecode.iterm2 PrefsCustomFolder >/dev/null 2>&1 && [ \"\$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder)\" = false ]"
  fi
  out="$(cd "$K" && ./install.sh --check 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "plist: --check exits 0 and ends 'all checks passed' (got $rc, '$(last "$out")')" test "$rc$(last "$out")" = "0all checks passed"
  expect "plist: the kept plist is the only thing git status lists" test "$(git -C "$K" status --porcelain 2>&1)" = "?? $PLIST"
  expect "plist: no .pre-link anywhere under the home" test -z "$(find "$H" -name '*.pre-link*' 2>/dev/null)"
}

if [ -n "${SCN_LIB:-}" ]; then return 0 2>/dev/null || exit 0; fi
if can_link; then run_in sep22 scn_sep22; run_in moved scn_moved
else echo "skip sep22, moved: this account cannot make symlinks, so the older layouts cannot be built"; fi
run_in theirs scn_theirs
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo "skip stock: the stock PATH is a macOS/Linux case" ;; *) run_in stock scn_stock ;; esac
run_in odd scn_odd
run_in noguard scn_noguard
if can_link; then run_in assistant scn_assistant
else echo "skip assistant: this account cannot make symlinks, so a project cannot link the agent"; fi
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "skip oldtag: v1.2.1's install.sh was never run on Windows without WSL" ;;
  *) if git -C "$R" rev-parse -q --verify 'refs/tags/v1.2.1^{commit}' >/dev/null 2>&1; then run_in oldtag scn_oldtag
     elif want oldtag && [ -n "${SCN_NEED_OLDTAG:-}" ]; then bad "oldtag: $R has no v1.2.1 tag (a shallow or tagless checkout; fetch with full history and tags)"
     elif want oldtag; then echo "skip oldtag: $R has no v1.2.1 tag (not a git checkout, or fetched without tags)"; fi ;;
esac
run_in nohook scn_nohook
# The scenarios that start from an older commit need this clone's history and tags.
has_history() { git -C "$R" rev-parse -q --verify 'refs/tags/v1.2.1^{commit}' >/dev/null 2>&1 && git -C "$R" rev-parse -q --verify 'refs/tags/v1.3.0-beta.5^{commit}' >/dev/null 2>&1 && git -C "$R" rev-parse -q --verify "$SEP_COMMIT^{commit}" >/dev/null 2>&1; }
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "skip plist, dirty: the older installers were never run on Windows without WSL" ;;
  *) if has_history; then
       run_in plist scn_plist
       if want dirty; then run_in dirty scn_dirty_v121; run_in dirty scn_dirty_beta5; fi
     elif { want plist || want dirty; } && [ -n "${SCN_NEED_OLDTAG:-}" ]; then bad "plist, dirty: $R lacks the v1.2.1 or v1.3.0-beta.5 tag or commit $SEP_COMMIT (a shallow or tagless checkout; fetch with full history and tags)"
     elif want plist || want dirty; then echo "skip plist, dirty: $R lacks the old tags or commit $SEP_COMMIT (not a git checkout, or fetched without tags)"; fi ;;
esac
# nokeychain: this script run again for scenario a with the keychain left out of the home. It must stop at
# keychain_ready: exit 1, a FAIL line naming the home, and neither install.sh nor claude started.
if want nokeychain && [ "$(uname -s)" = Darwin ] && [ -z "${SCN_NO_KEYCHAIN:-}" ]; then
  echo "== scenario nokeychain (scenario a in a home with no Library/Keychains)"
  out="$(SCN_ONLY=a SCN_NO_KEYCHAIN=1 bash "${BASH_SOURCE[0]}" "$TERMFLAG" 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "nokeychain: the run fails (exit $rc)" test "$rc" = 1
  expect "nokeychain: the FAIL line names the home" has "$out" '^FAIL a: the throwaway home /.*cc-install-a\.[A-Za-z0-9]* has no Library/Keychains'
  expect "nokeychain: neither install.sh nor claude ran in it" sh -c '! printf "%s\n" "$1" | grep -q -e "installing claude-config" -e "claude doctor" -e "^ok   a:"' _ "$out"
fi
if [ "$(uname -s)" = Darwin ]; then
  kc_was="$(cat "$KC_START" 2>&1)"; kc_now="$(real_keychains)"; kc_rc=$?; rm -f "$KC_START"
  # A listing that fails proves nothing either way, so it is a failure too.
  if [ "$kc_rc" != 0 ]; then bad "the real keychain search list and default keychain could not be read: $(printf '%s' "$kc_now" | tr '\n' ' ')"
  elif [ "$kc_was" = "$kc_now" ]; then ok "the real keychain search list and default keychain are as they were at the start"
  else
    bad "the real keychain search list or default keychain changed during the run"
    echo "     at the start:"; printf '%s\n' "$kc_was" | sed 's/^/       /'
    echo "     now:";          printf '%s\n' "$kc_now" | sed 's/^/       /'
  fi
fi
echo
if [ "$fails" = 0 ]; then echo "all install scenarios passed"; else echo "$fails failure(s)"; fi
exit $(( fails > 0 ))
