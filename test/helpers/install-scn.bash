# The install scenarios, one function each. Source install-lib.bash and install-dirty.bash first.
#   a)      an empty .claude
#   b)      a .claude that already has the user's settings.json, CLAUDE.md and agents/planner.md
#   sep22   the layout install.sh made before v1.3, plus on macOS iTerm2 reading its preferences from the clone
#   moved   install, move the clone, plain ./install.sh from the new path
#   theirs  their own same-name agent, skill, command, hooks folder and settings.json stay byte-identical
#   stock   /bin/bash with the stock PATH; python3 and tmux absent are named before any change
#   odd     clone and projects under "My Files/Claude Config"
#   oswsl, osmac   CLAUDE_CONFIG_INSTALL_OS: which local-tools are linked and what --check says
#   noguard the usage-guard script absent: each of the 7 hook commands still exits 0
#   assistant  --agent-clash keep; the assistant linked into a project finds its MCP server and guard hook
#   oldtag  v1.2.1's own install.sh installs, the clone is pulled to this version, the current install.sh runs
#   nohook  every hook command of the installed settings file exits 0 when the file it runs is missing
#   plist   a September install: the update as UPDATING.md gives it leaves iTerm2's plist in place, byte for byte
# a and b run from this clone; the others from a copy of it inside the throwaway home, and each ends with
# closing: --check passes, the copy is unchanged, no *.pre-link* exists.
scenario() {  # $1 = a|b
  local name="$1" H
  H="$(mktemp -d "${TMPDIR:-/tmp}/cc-install-$name.XXXX")"
  CUR_H="$H"
  [ -z "${SCN_OUT:-}" ] || printf '%s\n' "$H" >> "$SCN_OUT/homes"
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
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" "$TERMFLAG" --statusline squid --settings replace 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "sep22: install.sh exits 0 (got $rc)" test "$rc" = 0
  expect "sep22: .claude/hooks is now a real folder" sh -c "[ -d '$C/hooks' ] && [ ! -L '$C/hooks' ]"
  # usage-guard is not installed on Windows without WSL
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *) expect "sep22: .claude/hooks/usage-guard is a link" test -L "$C/hooks/usage-guard" ;; esac
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
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" "$TERMFLAG" --statusline squid --settings merge 2>&1)"; rc=$?
  expect "moved: first install exits 0 (got $rc)" test "$rc" = 0
  mkdir -p "$H/new place" && mv "$K" "$N" && rmdir "$H/old place"
  out="$(cd "$N" && ./install.sh 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "moved: plain ./install.sh from the new path exits 0 (got $rc)" test "$rc" = 0
  expect "moved: it says what it relinked" has "$out" "^  relinked $C/skills/run-agent (was $K/skills/run-agent, now missing)\$"
  expect "moved: no clash and no 'kept yours' for our own broken links" sh -c "! printf '%s\n' \"\$1\" | grep -q -e 'clash' -e 'kept yours' -e 'you have your own'" _ "$out"
  expect "moved: no link under .claude is broken" test -z "$(find "$C" -maxdepth 2 -type l ! -exec test -e {} \; -print 2>/dev/null | grep -v '/debug/')"
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
  expect "moved, no claude-config.json: no link under .claude is broken" test -z "$(find "$C" -maxdepth 2 -type l ! -exec test -e {} \; -print 2>/dev/null | grep -v '/debug/')"
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
  cp "$INSTALL_FIXTURES/theirs-settings.json" "$C/settings.json"
  mkdir -p "$H/orig" && cp -R "$C/agents" "$C/skills" "$C/commands" "$C/hooks" "$C/settings.json" "$H/orig/"
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" --no-terminal --statusline keep --settings keep 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
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
  out="$(cd "$K" && PATH="$bare" /bin/bash ./install.sh --projects "$PROJECTS_FLAG" --terminal --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
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
    out="$(cd "$K" && PATH="$bare" /bin/bash ./install.sh --projects "$PROJECTS_FLAG" --terminal --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
    expect "stock: tmux absent with --terminal: exits non-zero (got $rc)" test "$rc" != 0
    expect "stock, tmux only: names tmux and its install command" has "$out" "tmux is missing.*Install it with: ..*tmux"
    after="$(snap "$H")"
    expect "stock, tmux only: nothing was changed" test "$before" = "$after"
    [ "$before" = "$after" ] || diff <(echo "$before") <(echo "$after") | sed 's/^/     /'
    # 3. /bin/bash (3.2 on macOS) with the stock PATH and no terminal setup: installs, and names the claude command to run.
    out="$(cd "$K" && PATH="$H/.local/bin:$bare" /bin/bash ./install.sh --projects "$PROJECTS_FLAG" --no-terminal --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
    expect "stock: /bin/bash install with the stock PATH exits 0 (got $rc)" test "$rc" = 0
    expect "stock: claude absent: prints the claude mcp add command to run later" has "$out" "claude mcp add --transport stdio --scope user run-agent"
    # Claude Code installed afterwards: a plain rerun registers the server, and --check passes.
    out="$(cd "$K" && /bin/bash ./install.sh 2>&1)"; rc=$?
    expect "stock: rerun once claude is on PATH exits 0 (got $rc)" test "$rc" = 0
    closing stock "$H" "$K"
  else
    bad "stock: /usr/bin has no working python3 on this machine, so the tmux-absent and stock-PATH installs could not run"
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

# tools_set <H> <clone> <name> <os folder>: ~/.claude/local-tools is exactly local-tools/common + local-tools/<os folder>,
# each a link to its file in the clone; no file of the other OS's folder is there.
tools_set() {
  local H="$1" K="$2" name="$3" d="$4" other f n want_names got_names bad_links=""
  [ "$d" = wsl ] && other=macos || other=wsl
  want_names="$( (ls "$K/local-tools/common"; ls "$K/local-tools/$d") | sort | tr '\n' ' ')"
  got_names="$(ls "$H/.claude/local-tools" 2>/dev/null | grep -v '^evshow\.state$' | sort | tr '\n' ' ')"
  expect "$name: local-tools holds exactly common + $d ($(echo "$got_names" | wc -w | tr -d ' ') names)" test "$got_names" = "$want_names"
  for f in "$K/local-tools/common"/* "$K/local-tools/$d"/*; do n="$(basename "$f")"
    [ -L "$H/.claude/local-tools/$n" ] && [ "$(cd "$(dirname "$(readlink "$H/.claude/local-tools/$n")")" 2>/dev/null && pwd -P)" = "$(cd "$(dirname "$f")" && pwd -P)" ] || bad_links="$bad_links $n"
  done
  expect "$name: every tool is a link into local-tools/common or local-tools/$d (not:$bad_links)" test -z "$bad_links"
  for n in $(ls "$K/local-tools/$other"); do
    [ -e "$K/local-tools/$d/$n" ] && continue
    [ -e "$H/.claude/local-tools/$n" ] || [ -L "$H/.claude/local-tools/$n" ] && { bad "$name: $n of local-tools/$other is installed"; return; }
  done
  ok "$name: no tool of local-tools/$other is installed"
}
scn_oswsl() {
  local H="$1" K="$1/clone" out rc
  copy_clone "$K" || { bad "oswsl: could not copy the clone"; return; }
  out="$(cd "$K" && CLAUDE_CONFIG_INSTALL_OS=wsl ./install.sh --projects "$H/files" --no-terminal --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "oswsl: install.sh as WSL exits 0 (got $rc)" test "$rc" = 0
  tools_set "$H" "$K" oswsl wsl
  expect "oswsl: winctl.ps1 and screen-capture.ps1 are linked" test -L "$H/.claude/local-tools/winctl.ps1" -a -L "$H/.claude/local-tools/screen-capture.ps1"
  out="$(cd "$K" && CLAUDE_CONFIG_INSTALL_OS=wsl ./install.sh --check 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "oswsl: --check as WSL exits 0 and ends 'all checks passed' (got $rc, '$(last "$out")')" test "$rc$(last "$out")" = "0all checks passed"
  expect "oswsl: --check prints a PASS line for win.sh (wsl) and for evshow.sh (common)" test "$(printf '%s\n' "$out" | grep -c -e 'PASS.*local-tools/win\.sh (wsl)' -e 'PASS.*local-tools/evshow\.sh (common)')" = 2
  out="$(cd "$K" && CLAUDE_CONFIG_INSTALL_OS=mac CLAUDE_CONFIG_FIREFOX_APP="$H" ./install.sh --check 2>&1)"; rc=$?
  expect "oswsl: --check as a Mac FAILs on the WSL tools found installed (got $rc)" test "$rc" != 0
  expect "oswsl: ... and names winctl.ps1 as a wsl tool" has "$out" 'FAIL.*local-tools/winctl\.ps1 is a wsl tool'
  out="$(cd "$K" && CLAUDE_CONFIG_INSTALL_OS=mac ./install.sh 2>&1)"; rc=$?
  expect "oswsl: a rerun as a Mac exits 0 (got $rc)" test "$rc" = 0
  tools_set "$H" "$K" "oswsl rerun as mac" macos
  expect "oswsl: the clone is unchanged (git status --porcelain is empty)" test -z "$(git -C "$K" status --porcelain 2>&1)"
}
scn_osmac() {
  local H="$1" K="$1/clone" out rc
  copy_clone "$K" || { bad "osmac: could not copy the clone"; return; }
  out="$(cd "$K" && CLAUDE_CONFIG_INSTALL_OS=mac ./install.sh --projects "$H/files" --no-terminal --statusline squid --settings merge 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "osmac: install.sh as a Mac exits 0 (got $rc)" test "$rc" = 0
  tools_set "$H" "$K" osmac macos
  expect "osmac: no .ps1 is installed" test -z "$(ls "$H/.claude/local-tools" | grep '\.ps1$')"
  out="$(cd "$K" && CLAUDE_CONFIG_INSTALL_OS=mac CLAUDE_CONFIG_FIREFOX_APP="$H" ./install.sh --check 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "osmac: --check exits 0 and ends 'all checks passed' (got $rc, '$(last "$out")')" test "$rc$(last "$out")" = "0all checks passed"
  expect "osmac: --check prints a PASS line for win.sh (macos) and for evshow.sh (common)" test "$(printf '%s\n' "$out" | grep -c -e 'PASS.*local-tools/win\.sh (macos)' -e 'PASS.*local-tools/evshow\.sh (common)')" = 2
  expect "osmac: --check with Firefox present prints 'PASS Firefox installed'" has "$out" '^PASS Firefox installed'
  out="$(cd "$K" && CLAUDE_CONFIG_INSTALL_OS=mac CLAUDE_CONFIG_FIREFOX_APP="$H/no-Firefox.app" ./install.sh --check 2>&1)"; rc=$?
  expect "osmac: --check without Firefox prints 'WARN Firefox not installed: items open in the default browser, no phone pictures'" has "$out" '^WARN Firefox not installed: items open in the default browser, no phone pictures$'
  expect "osmac: ... and still exits 0 with 'all checks passed' (got $rc)" test "$rc$(last "$out")" = "0all checks passed"
  out="$(cd "$K" && CLAUDE_CONFIG_INSTALL_OS=linux ./install.sh 2>&1)"; rc=$?
  expect "osmac: a rerun as plain Linux leaves only local-tools/common ($(ls "$H/.claude/local-tools" | grep -v evshow.state | wc -l | tr -d ' ') names)" test "$(ls "$H/.claude/local-tools" | grep -v '^evshow\.state$' | sort | tr '\n' ' ')" = "$(ls "$K/local-tools/common" | sort | tr '\n' ' ')"
  expect "osmac: the clone is unchanged (git status --porcelain is empty)" test -z "$(git -C "$K" status --porcelain 2>&1)"
}

# The 7 usage-guard hook commands of the installed settings.json, run as Claude Code runs them (sh -c, the hook's
# JSON on stdin) with the script gone. Before 01304e8 each ended in exit 2, which blocks the tool call: with the
# script missing, no Bash, Agent or Edit call could run, so the session could not even repair itself.
scn_noguard() {
  local H="$1" K="$1/files/claude-config" C="$1/.claude" out rc n i G="usage-guard"
  copy_clone "$K" || { bad "noguard: could not copy the clone"; return; }
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" --no-terminal --statusline squid --settings replace 2>&1)"; rc=$?
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
  [ -z "${SCN_OUT:-}" ] || printf '%s\n' "$n" > "$SCN_OUT/hooks"
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
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" --no-terminal --statusline squid --settings merge --agent-clash keep 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
  expect "assistant: install.sh --agent-clash keep exits 0 (got $rc)" test "$rc" = 0
  expect "assistant: keep made the renamed copy for the clashing agent (planner-claude-config)" test -f "$C/agents/planner-claude-config.md"
  expect "assistant: no assistant file or copy under .claude/agents" test -z "$(ls "$C/agents" | grep -i assistant)"
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
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" "$TERMFLAG" --statusline squid --settings replace 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
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
  expect "oldtag: .claude/hooks is a real folder" sh -c "[ -d '$C/hooks' ] && [ ! -L '$C/hooks' ]"
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
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" --no-terminal --statusline squid --settings replace 2>&1)"; rc=$?
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
  [ -z "${SCN_OUT:-}" ] || printf '%s\n' "$n" > "$SCN_OUT/hooks"
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
  out="$(cd "$K" && ./install.sh --projects "$PROJECTS_FLAG" "$TERMFLAG" --statusline squid --settings replace 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'   # 4
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
