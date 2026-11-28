# Shared by the install scenarios (test/quick/install-*.bats through install-run.bash) and by bin/release/rehearsal.sh.
# Source it with REAL_HOME set to the home of the person running the tests; TERMFLAG may be set first
# (--terminal or --no-terminal). It defines functions and variables and installs the INT/TERM cleanup; it runs
# no install. Every throwaway home is made safe by home_setup before install.sh or claude runs in it.
: "${REAL_HOME:?set REAL_HOME to the real home before sourcing test/helpers/install-lib.bash}"
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_FIXTURES="$R/test/fixtures/install"
on_win_host() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac; }
if [ -z "${TERMFLAG:-}" ]; then
  TERMFLAG=--terminal
  if on_win_host || [ -n "${WSL_DISTRO_NAME:-}" ]; then TERMFLAG=--no-terminal; fi
fi
# On real WSL the install edits the Windows side (Windows Terminal profile, a scheduled task), which a throwaway
# home folder does not isolate. Run `test/run docker` there instead.
if [ -n "${WSL_DISTRO_NAME:-}" ] && [ "$TERMFLAG" = --terminal ]; then
  echo "install tests: refusing to run --terminal on WSL (it would change this PC's Windows Terminal); use test/run docker" >&2
  exit 2
fi
fails=0
# SCN_OUT set (the bats files): every ok/FAIL line is also kept in $SCN_OUT/checks, one "ok|FAIL <tab> label" line.
record() { [ -z "${SCN_OUT:-}" ] || printf '%s\t%s\n' "$1" "$(printf '%s' "$2" | tr '\n\t' '  ')" >> "$SCN_OUT/checks"; }
ok()   { echo "ok   $*"; record ok "$*"; }
bad()  { echo "FAIL $*"; record FAIL "$*"; fails=$((fails+1)); }
expect() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
PY=python3; command -v python3 >/dev/null 2>&1 && python3 -c 1 >/dev/null 2>&1 || PY=python
# The mod dir as install.sh writes it: on Windows a native C:/... path in a ;-separated list.
MOD="$R/mods/defer-artifact"; SEP=":"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && MOD="$(cygpath -m "$R")/mods/defer-artifact"; SEP=";" ;; esac
# macOS: the run must leave the real keychain search list and default keychain as it found them. kc_begin writes
# both to a file; kc_end compares.
KC_START=""
real_keychains() { HOME="$REAL_HOME" security list-keychains -d user 2>&1 && HOME="$REAL_HOME" security default-keychain 2>&1; }
kc_begin() {
  [ "$(uname -s)" = Darwin ] || return 0
  KC_START="$(mktemp "${TMPDIR:-/tmp}/cc-install-keychains.XXXX")"; real_keychains > "$KC_START"
}
kc_end() {
  [ "$(uname -s)" = Darwin ] || return 0
  local kc_was kc_now kc_rc
  kc_was="$(cat "$KC_START" 2>&1)"; kc_now="$(real_keychains)"; kc_rc=$?; rm -f "$KC_START"
  # A listing that fails proves nothing either way, so it is a failure too.
  if [ "$kc_rc" != 0 ]; then bad "the real keychain search list and default keychain could not be read: $(printf '%s' "$kc_now" | tr '\n' ' ')"
  elif [ "$kc_was" = "$kc_now" ]; then ok "the real keychain search list and default keychain are as they were at the start"
  else
    bad "the real keychain search list or default keychain changed during the run"
    echo "     at the start:"; printf '%s\n' "$kc_was" | sed 's/^/       /'
    echo "     now:";          printf '%s\n' "$kc_now" | sed 's/^/       /'
  fi
  KC_START=""
}
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

# The --projects value is a literal tilde path that install.sh itself expands under the throwaway HOME.
PROJECTS_FLAG="$(cat "$INSTALL_FIXTURES/projects-flag.txt")"
FLAGS=(--projects "$PROJECTS_FLAG" "$TERMFLAG" --statusline squid --settings merge --agent-clash replace)

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
    cp "$INSTALL_FIXTURES/defaults" "$H/.local/bin/defaults"
    chmod +x "$H/.local/bin/defaults"
  fi
  keychain_ready "$H" "$name" || return 1
  return 0
}

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
  local name="$1" fn="$2" H
  H="$(mktemp -d "${TMPDIR:-/tmp}/cc-install-$name.XXXX")"; H="$(cd "$H" && pwd -P)"
  CUR_H="$H"
  [ -z "${SCN_OUT:-}" ] || printf '%s\n' "$H" >> "$SCN_OUT/homes"
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
