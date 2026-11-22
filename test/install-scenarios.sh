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
# SCN_ONLY=<name>: run just that one of a, b, sep22, moved, theirs, stock, odd
want() { [ -z "${SCN_ONLY:-}" ] || [ "$SCN_ONLY" = "$1" ]; }
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
  if [ "$(uname -s)" = Darwin ]; then
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

if can_link; then run_in sep22 scn_sep22; run_in moved scn_moved
else echo "skip sep22, moved: this account cannot make symlinks, so the older layouts cannot be built"; fi
run_in theirs scn_theirs
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo "skip stock: the stock PATH is a macOS/Linux case" ;; *) run_in stock scn_stock ;; esac
run_in odd scn_odd
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
