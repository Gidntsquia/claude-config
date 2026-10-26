#!/usr/bin/env bash
# usage: test/install-scenarios.sh [--terminal|--no-terminal]
# Runs install.sh from this clone in two throwaway home folders and exits non-zero on any failure:
#   a) an empty ~/.claude
#   b) a ~/.claude that already has the user's settings.json (own model and statusLine), CLAUDE.md and agents/planner.md
# Each scenario runs install.sh, then install.sh --check, the personal-path grep and claude doctor.
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
expect() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
PY=python3; command -v python3 >/dev/null 2>&1 && python3 -c 1 >/dev/null 2>&1 || PY=python
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

scenario() {  # $1 = a|b
  local name="$1" H
  H="$(mktemp -d "${TMPDIR:-/tmp}/cc-install-$name.XXXX")"
  echo "== scenario $name ($H) ./install.sh ${FLAGS[*]}"
  (
    export HOME="$H" PATH="$H/.local/bin:$PATH"
    [ -n "${USERPROFILE:-}" ] && export USERPROFILE="$H"
    mkdir -p "$H/.claude"
    # claude keeps its install under ~/.local; let the throwaway home see it.
    [ -d "$REAL_HOME/.local/share/claude" ] && mkdir -p "$H/.local/share" && ln -s "$REAL_HOME/.local/share/claude" "$H/.local/share/claude" 2>/dev/null
    [ -f "$REAL_HOME/.claude.json" ] && cp "$REAL_HOME/.claude.json" "$H/.claude.json"
    if [ "$name" = b ]; then
      mkdir -p "$H/.claude/agents"
      printf '%s\n' '{"model": "haiku", "statusLine": {"type": "command", "command": "echo my-status"}, "permissions": {"deny": ["Bash(rm -rf:*)"]}}' > "$H/.claude/settings.json"
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
      expect "a: planner agent installed" test -e "$H/.claude/agents/planner.md"
    else
      expect "b: model unchanged" test "$(jget "$s" model)" = '"haiku"'
      expect "b: statusLine unchanged" test "$(jget "$s" statusLine)" = '{"type": "command", "command": "echo my-status"}'
      expect "b: deny list kept and unioned" "$PY" -c "import json,sys;d=json.load(open(sys.argv[1]))['permissions']['deny'];assert d[0]=='Bash(rm -rf:*)' and len(d)>1" "$s"
      expect "b: repo keys added (promptCacheTtl)" sh -c "grep -q promptCacheTtl '$s'"
      expect "b: original settings kept as settings.json.pre-link" test -f "$s.pre-link"
      expect "b: CLAUDE.md byte-identical" cmp -s "$H/.claude/CLAUDE.md" "$H/claude.md.orig"
      expect "b: planner.md is now the repo's (--agent-clash replace)" sh -c "grep -q '^name: planner\$' '$H/.claude/agents/planner.md' && ! cmp -s '$H/.claude/agents/planner.md' '$H/planner.md.orig'"
      expect "b: your planner kept as planner.pre-link.md" cmp -s "$H/.claude/agents/planner.pre-link.md" "$H/planner.md.orig"
    fi
    out="$(./install.sh 2>&1 | head -1)"
    expect "$name: rerun with no flags reuses saved choices" sh -c "echo \"\$1\" | grep -q 'reusing saved choices'" _ "$out"
    exit "$fails"
  )
  fails=$((fails+$?))
  rm -rf "$H"
}

scenario a
scenario b
echo
if [ "$fails" = 0 ]; then echo "all install scenarios passed"; else echo "$fails failure(s)"; fi
exit $(( fails > 0 ))
