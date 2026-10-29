#!/usr/bin/env bash
# Install this repo's Claude Code setup into ~/.claude. Existing files are kept unless a flag says otherwise.
# Run ./install.sh --help for the flags; INSTALL.md is the guided version a Claude session follows.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: ./install.sh [flags]          (no flags: reuse the choices saved in ~/.claude/claude-config.json)
  --projects DIR                     folder where your projects live (default ~/files); tmux panes open there
  --terminal | --no-terminal         tmux 4 panes, tmux.conf, starship prompt, Windows Terminal / iTerm2 "Claude tmux"
                                     profile (default: no)
  --default-profile | --no-default-profile
                                     with --terminal: make that profile the one new terminal windows open with
  --statusline squid|plane|keep      the squid or plane status line, or keep yours (default: squid when you have none)
  --settings merge|keep|replace      settings.json: add only the keys you lack (default), leave it, or link the repo's
  --agent-clash keep|replace|skip    what to do when ~/.claude/agents or ~/.claude/skills already has one of this
                                     repo's names: keep yours (repo copy added as <name>-claude-config), use the
                                     repo's (yours moved to <name>.pre-link), or skip it. Per name: planner=keep,worker=skip
  --check                            print one PASS/FAIL line per installed item; exit 1 on any FAIL
  --help                             this text
Exit codes: 0 ok, 1 error or a FAIL in --check, 2 bad flag, 3 an agent or skill name clash needs --agent-clash.
EOF
}

R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
C="$HOME/.claude"
CFG="$C/claude-config.json"
VERSION="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$R/pyproject.toml" 2>/dev/null | head -1)"

# ---- platform ---------------------------------------------------------------------------------------------------
OS=linux
case "$(uname -s)" in
  Darwin) OS=mac ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  # A Docker container on a WSL host shares its kernel (microsoft in /proc/version) but is not WSL.
  *) grep -qi microsoft /proc/version 2>/dev/null && [ -n "${WSL_DISTRO_NAME:-}" ] && command -v wslpath >/dev/null 2>&1 && OS=wsl ;;
esac
OS="${CLAUDE_CONFIG_INSTALL_OS:-$OS}"  # tests only: pretend to be linux|wsl|mac|windows
# Git Bash makes copies for ln -s unless told to make real Windows symlinks (needs Developer Mode or admin).
[ "$OS" = windows ] && export MSYS=winsymlinks:nativestrict
PY=""
for p in python3 python; do command -v "$p" >/dev/null 2>&1 && "$p" -c 'import json' >/dev/null 2>&1 && { PY="$p"; break; }; done
[ -n "$PY" ] || { echo "install.sh: needs python3 (for the settings merge); install it and rerun" >&2; exit 1; }

# readlink -f keeps Git Bash's /c/... form (Windows python would print C:\...); old macOS lacks it, so python is the fallback.
resolve() { readlink -f "$1" 2>/dev/null || "$PY" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
# in_clone <path> [repo path]: <path> is a link into this clone. On Windows, where an account without symlink rights
# gets copies, an identical copy of [repo path] counts too.
in_clone() {
  if [ -L "$1" ]; then case "$(resolve "$1")" in "$R"|"$R"/*) return 0 ;; esac; fi
  [ "$OS" = windows ] && [ -n "${2:-}" ] && [ -e "$1" ] && diff -rq "$1" "$2" >/dev/null 2>&1
}
expand() { case "$1" in "~") echo "$HOME" ;; "~/"*) echo "$HOME/${1#\~/}" ;; *) echo "$1" ;; esac; }
saved() { [ -f "$CFG" ] && "$PY" -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print("" if v is None else (str(v).lower() if isinstance(v,bool) else v))' "$CFG" "$1" 2>/dev/null || true; }

# ---- flags ------------------------------------------------------------------------------------------------------
PROJECTS="" TERMINAL="" DEFPROF="" STATUSLINE="" SETTINGS="" CLASH="" CHECK="" NFLAGS=0
need() { [ $# -ge 2 ] || { echo "install.sh: $1 needs a value" >&2; usage >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --projects)     need "$@"; PROJECTS="$2"; shift 2 ;;
    --projects=*)   PROJECTS="${1#*=}"; shift ;;
    --terminal)     TERMINAL=true; shift ;;
    --no-terminal)  TERMINAL=false; shift ;;
    --default-profile)    DEFPROF=true; shift ;;
    --no-default-profile) DEFPROF=false; shift ;;
    --statusline|--theme) need "$@"; STATUSLINE="$2"; shift 2 ;;
    --statusline=*|--theme=*) STATUSLINE="${1#*=}"; shift ;;
    --settings)     need "$@"; SETTINGS="$2"; shift 2 ;;
    --settings=*)   SETTINGS="${1#*=}"; shift ;;
    --agent-clash)  need "$@"; CLASH="$2"; shift 2 ;;
    --agent-clash=*) CLASH="${1#*=}"; shift ;;
    --check)        CHECK=1; shift; continue ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "install.sh: unknown flag $1" >&2; usage >&2; exit 2 ;;
  esac
  NFLAGS=$((NFLAGS + 1))
done
case "${STATUSLINE:-x}" in x|squid|plane|keep) ;; *) echo "install.sh: --statusline is squid, plane or keep" >&2; exit 2 ;; esac
case "${SETTINGS:-x}" in x|merge|keep|replace) ;; *) echo "install.sh: --settings is merge, keep or replace" >&2; exit 2 ;; esac

# Choices not given as flags come from the saved file, then from what is already installed, then the defaults.
reused=""
fill() {  # fill VAR savedKey fallback
  local var="$1" key="$2" fb="$3" cur s
  eval "cur=\${$var}"
  [ -n "$cur" ] && return 0
  s="$(saved "$key")"
  if [ -n "$s" ]; then eval "$var=\$s"; reused="$reused $key"; else eval "$var=\$fb"; fi
}
had_statusline() { [ -f "$C/settings.json" ] && "$PY" -c 'import json,sys; sys.exit(0 if "statusLine" in json.load(open(sys.argv[1])) else 1)' "$C/settings.json" 2>/dev/null; }
d_term=false; in_clone "$HOME/.local/bin/tmux-quad" && d_term=true
d_status=keep
if in_clone "$C/statusline.sh"; then
  d_status=squid; grep -qs 'CLAUDE_STATUSLINE_THEME=plane' "$HOME/.bashrc" "$HOME/.zshrc" && d_status=plane
elif ! had_statusline; then d_status=squid; fi
d_settings=merge; in_clone "$C/settings.json" && d_settings=replace
fill PROJECTS projects "$HOME/files"
fill TERMINAL terminal "$d_term"
fill DEFPROF defaultProfile false
fill STATUSLINE statusline "$d_status"
fill SETTINGS settings "$d_settings"
fill CLASH agentClash ""
PROJECTS="$(expand "$PROJECTS")"
[ -n "$reused" ] && echo "reusing saved choices from $CFG:$reused"

# ---- repo contents ----------------------------------------------------------------------------------------------
repo_agents() { for f in "$R"/agents/*.md; do head -5 "$f" | grep -q '^name:' && basename "$f" .md; done; }
repo_skills() { for s in "$R"/skills/*/; do [ -f "$s/SKILL.md" ] && basename "$s"; done; }
# ~/.claude/agents is either a link to the repo's agents/ (whole folder) or the user's own folder (one link per agent).
agents_whole() { [ ! -e "$C/agents" ] && [ ! -L "$C/agents" ] || in_clone "$C/agents" "$R/agents"; }

# =================================================================================================================
# --check
# =================================================================================================================
if [ -n "$CHECK" ]; then
  fails=0
  pass() { echo "PASS $*"; }
  fail() { echo "FAIL $*"; fails=$((fails + 1)); }
  skip() { echo "SKIP $*"; }
  linked() {  # linked <path> <label>: path is a symlink resolving into the clone (or, on Windows without symlinks, a copy)
    if in_clone "$1"; then pass "$2 -> $(resolve "$1")"
    elif [ "$OS" = windows ] && [ -e "$1" ] && [ -n "${3:-}" ] && diff -rq "$1" "$3" >/dev/null 2>&1; then pass "$2 (copy of $3)"
    else fail "$2: $1 is not a link into $R"; fi
  }
  if [ -f "$CFG" ] && [ "$(saved repo)" = "$R" ]; then pass "$CFG names this clone ($R)"
  else fail "$CFG missing or names another clone (run ./install.sh)"; fi
  if agents_whole; then linked "$C/agents" "agents" "$R/agents"
  else
    for a in $(repo_agents); do
      if in_clone "$C/agents/$a.md" "$R/agents/$a.md"; then pass "agent $a"
      elif [ -f "$C/agents/$a-claude-config.md" ]; then pass "agent $a (yours kept; repo copy is $a-claude-config)"
      elif [ -f "$C/agents/$a.md" ]; then skip "agent $a (yours kept, repo's skipped)"
      else fail "agent $a: $C/agents/$a.md missing"; fi
    done
  fi
  for s in $(repo_skills); do
    if in_clone "$C/skills/$s" "$R/skills/$s"; then pass "skill $s"
    elif [ -d "$C/skills/$s-claude-config" ]; then pass "skill $s (yours kept; repo copy is $s-claude-config)"
    elif [ -e "$C/skills/$s" ]; then skip "skill $s (yours kept, repo's skipped)"
    else fail "skill $s: $C/skills/$s missing"; fi
  done
  if [ -L "$C/CLAUDE.md" ] || [ ! -e "$C/CLAUDE.md" ]; then linked "$C/CLAUDE.md" "CLAUDE.md" "$R/CLAUDE.md"
  else skip "CLAUDE.md is yours (add @$R/CLAUDE.md to it to use the repo's rules)"; fi
  if [ -f "$C/settings.json" ] && "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$C/settings.json" 2>/dev/null; then
    pass "settings.json parses ($SETTINGS)"
  else fail "settings.json missing or not valid JSON"; fi
  [ "$SETTINGS" = replace ] && linked "$C/settings.json" "settings.json" "$R/settings.json"
  if command -v claude >/dev/null 2>&1; then
    if claude doctor </dev/null >/dev/null 2>&1; then pass "claude doctor"; else fail "claude doctor exited non-zero"; fi
  else fail "claude not on PATH (install: curl -fsSL https://claude.ai/install.sh | bash)"; fi
  if [ "$STATUSLINE" = keep ] || [ "$OS" = windows ]; then skip "status line ($([ "$OS" = windows ] && echo 'needs WSL' || echo 'kept yours'))"
  else
    linked "$C/statusline.sh" "statusline.sh" "$R/statusline.sh"
    n="$(bash "$C/statusline.sh" --preview "$STATUSLINE" 2>/dev/null | wc -l | tr -d ' ')" || n=0
    if [ "${n:-0}" -gt 0 ]; then pass "statusline.sh --preview $STATUSLINE ($n lines)"; else fail "statusline.sh --preview $STATUSLINE printed nothing"; fi
  fi
  if out="$(bash "$R/bin/find-personal-paths.sh" "$R")"; then pass "no personal paths in the clone"
  else fail "personal paths in: $(echo "$out" | tr '\n' ' ')"; fi
  if [ "$OS" != windows ]; then
    if in_clone "$HOME/.local/bin/run-agent"; then pass "run-agent shell command (~/.local/bin/run-agent)"
    else fail "run-agent shell command missing (rerun install.sh)"; fi
  fi
  if [ "$TERMINAL" = true ] && [ "$OS" != windows ]; then
    if [ "$(command -v tmux-quad 2>/dev/null)" ] && in_clone "$(command -v tmux-quad)"; then pass "tmux-quad on PATH"
    else fail "tmux-quad not on PATH (open a new terminal, or add ~/.local/bin to PATH)"; fi
    linked "$HOME/.tmux.conf" "tmux.conf"
    if command -v tmux >/dev/null 2>&1 && tmux -L claude-config-check -f "$HOME/.tmux.conf" start-server \; kill-server 2>/dev/null; then pass "tmux loads ~/.tmux.conf"
    else fail "tmux missing or ~/.tmux.conf has errors"; fi
    linked "$HOME/.config/starship.toml" "starship.toml"
    if systemctl --user is-enabled run-agent-revive.service >/dev/null 2>&1; then pass "run-agent-revive.service enabled"
    elif grep -qs 'run-agent.sh" --revive' "$HOME/$([ "$OS" = mac ] && echo .zshrc || echo .bashrc)"; then pass "shell rc revives scheduled /run-agent runs"
    else fail "nothing revives scheduled /run-agent runs after a reboot (rerun install.sh)"; fi
    if [ "$OS" = wsl ]; then
      W="$(wslpath "$(cmd.exe /C 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')" 2>/dev/null || true)"; wt=""
      for S in "$W"/Packages/Microsoft.WindowsTerminal*/LocalState/settings.json; do
        [ -f "$S" ] && "$PY" "$R/wsl/wt-profile.py" --check "$S" "$WSL_DISTRO_NAME" "wsl.exe -d $WSL_DISTRO_NAME -- $HOME/.local/bin/tmux-quad" >/dev/null 2>&1 && wt=1
      done
      if [ -n "$wt" ]; then pass "Windows Terminal $WSL_DISTRO_NAME profile runs tmux-quad"; else fail "Windows Terminal profile for $WSL_DISTRO_NAME does not run tmux-quad"; fi
      if schtasks.exe /query /tn "Pin Windows Terminal Volume" >/dev/null 2>&1; then pass "Windows Terminal volume task"
      else fail "Windows Terminal volume task not registered"; fi
    elif [ "$OS" = mac ]; then
      if [ -d /Applications/iTerm.app ]; then linked "$HOME/Library/Application Support/iTerm2/DynamicProfiles/claude-tmux.json" "iTerm2 Claude tmux profile"
      else skip "iTerm2 not installed: no Claude tmux profile"; fi
    fi
  else skip "terminal setup (not chosen$([ "$OS" = windows ] && echo '; needs WSL'))"; fi
  if [ "$OS" = wsl ]; then
    if [ -L "$C/CLAUDE.local.md" ] || [ ! -e "$C/CLAUDE.local.md" ]; then linked "$C/CLAUDE.local.md" "CLAUDE.local.md"
    else skip "CLAUDE.local.md is yours"; fi
    linked "$C/local-tools/win.sh" "local-tools"
  fi
  echo "$([ $fails -eq 0 ] && echo "all checks passed" || echo "$fails check(s) failed")"
  [ $fails -eq 0 ]; exit $?
fi

# =================================================================================================================
# install
# =================================================================================================================
clash_mode() {  # clash_mode <name>: keep|replace|skip from --agent-clash, or empty
  local item mode=""
  local IFS=,
  for item in $CLASH; do
    case "$item" in
      "$1="*) echo "${item#*=}"; return ;;
      keep|replace|skip) mode="$item" ;;
    esac
  done
  echo "$mode"
}
link() {  # link <src> <dst>: replace a link, move a real file to <dst>.pre-link
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then rm "$dst"
  elif [ -e "$dst" ] && in_clone "$dst" "$src"; then rm -rf "$dst"  # Windows: our own earlier copy
  elif [ -e "$dst" ]; then mv "$dst" "$dst.pre-link"; fi
  ln -s "$src" "$dst" 2>/dev/null || { [ "$OS" = windows ] && cp -R "$src" "$dst" && echo "  (copied $dst: this Windows account cannot make symlinks; rerun install.sh after updates)"; }
}
backup() { local f="$1" b="$2"; [ -e "$b" ] && b="$b.$(date +%Y%m%d%H%M%S)"; mv "$f" "$b"; echo "  moved your $(basename "$f") to $b"; }

# 1. Clashes first, before anything changes.
clashes=""
if ! agents_whole; then
  for a in $(repo_agents); do
    f="$C/agents/$a.md"
    { [ -e "$f" ] || [ -L "$f" ]; } && ! in_clone "$f" "$R/agents/$a.md" && [ -z "$(clash_mode "$a")" ] && clashes="$clashes agents/$a.md"
  done
fi
for s in $(repo_skills); do
  d="$C/skills/$s"
  { [ -e "$d" ] || [ -L "$d" ]; } && ! in_clone "$d" "$R/skills/$s" && [ -z "$(clash_mode "$s")" ] && clashes="$clashes skills/$s"
done
if [ -n "$clashes" ]; then
  echo "These are already in $C and are yours (not links into $R):"
  for c in $clashes; do echo "  clash: $c"; done
  echo "Rerun with --agent-clash keep|replace|skip (or per name, e.g. --agent-clash planner=keep,worker=replace)."
  exit 3
fi

mkdir -p "$C/skills" "$PROJECTS"
echo "installing claude-config $VERSION from $R into $C ($OS)"

# 2. Agents.
if agents_whole; then
  link "$R/agents" "$C/agents"; echo "  agents: linked $C/agents -> $R/agents"
else
  echo "  agents: you have your own $C/agents, so each repo agent is added next to yours"
  for a in $(repo_agents); do
    f="$C/agents/$a.md"
    if in_clone "$f" "$R/agents/$a.md" || [ ! -e "$f" ]; then link "$R/agents/$a.md" "$f"; continue; fi
    case "$(clash_mode "$a")" in
      keep)    sed "s/^name: *$a *\$/name: $a-claude-config/" "$R/agents/$a.md" > "$C/agents/$a-claude-config.md"
               echo "  agent $a: kept yours; the repo's is $a-claude-config (claude --agent $a-claude-config)" ;;
      replace) backup "$f" "$C/agents/$a.pre-link.md"; link "$R/agents/$a.md" "$f"; echo "  agent $a: now the repo's" ;;
      skip)    echo "  agent $a: kept yours, repo's skipped" ;;
    esac
  done
  for d in report-writer evals; do  # folders the report-writer agent reads
    if in_clone "$C/agents/$d" || [ ! -e "$C/agents/$d" ]; then link "$R/agents/$d" "$C/agents/$d"; else echo "  agents/$d is yours; left alone"; fi
  done
fi

# 3. Skills.
for s in $(repo_skills); do
  d="$C/skills/$s"
  if in_clone "$d" "$R/skills/$s" || { [ ! -e "$d" ] && [ ! -L "$d" ]; }; then link "$R/skills/$s" "$d"; continue; fi
  case "$(clash_mode "$s")" in
    keep)    k="$C/skills/$s-claude-config"; rm -rf "$k"; mkdir -p "$k"
             for f in "$R/skills/$s"/*; do [ "$(basename "$f")" = SKILL.md ] || link "$f" "$k/$(basename "$f")"; done
             sed "s/^name: *$s *\$/name: $s-claude-config/" "$R/skills/$s/SKILL.md" > "$k/SKILL.md"
             echo "  skill $s: kept yours; the repo's is /$s-claude-config" ;;
    replace) backup "$d" "$d.pre-link"; link "$R/skills/$s" "$d"; echo "  skill $s: now the repo's" ;;
    skip)    echo "  skill $s: kept yours, repo's skipped" ;;
  esac
done
echo "  skills: $(repo_skills | tr '\n' ' ')"

# 4. CLAUDE.md: linked only when you have none.
if [ ! -e "$C/CLAUDE.md" ] || in_clone "$C/CLAUDE.md" "$R/CLAUDE.md"; then link "$R/CLAUDE.md" "$C/CLAUDE.md"; echo "  CLAUDE.md: linked"
else
  echo "  CLAUDE.md: yours is left as it is. To use the repo's rules too, add this line to $C/CLAUDE.md:"
  echo "      @$R/CLAUDE.md"
fi

# 5. settings.json.
statusline_on=false
[ "$STATUSLINE" != keep ] && [ "$OS" != windows ] && statusline_on=true
case "$SETTINGS" in
  replace) link "$R/settings.json" "$C/settings.json"; echo "  settings.json: linked to the repo's (yours, if any, is settings.json.pre-link)" ;;
  keep)    echo "  settings.json: left as it is"
           $statusline_on && ! grep -qs 'statusline.sh' "$C/settings.json" && \
             echo "  to see the status line, add to settings.json: \"statusLine\": {\"type\": \"command\", \"command\": \"bash ~/.claude/statusline.sh\"}" ;;
  merge)
    args=()
    # Your values win, statusLine included: with squid/plane the repo's statusLine is added only when you have none.
    $statusline_on || args=(--drop-key statusLine)
    tmp="$C/.settings.merge.$$"
    "$PY" "$R/bin/merge-settings.py" "$R/settings.json" "$C/settings.json" "$tmp" ${args[@]+"${args[@]}"} | sed 's/^/  /'
    if $statusline_on && ! grep -qs 'statusline.sh' "$tmp"; then
      echo "  your settings.json has its own statusLine, which the merge keeps. To use this repo's, set it to:"
      echo "      \"statusLine\": {\"type\": \"command\", \"command\": \"bash ~/.claude/statusline.sh\"}"
    fi
    if [ -L "$C/settings.json" ]; then rm "$C/settings.json"
    elif [ -f "$C/settings.json" ] && [ ! -e "$C/settings.json.pre-link" ]; then cp "$C/settings.json" "$C/settings.json.pre-link"; echo "  your original settings.json is kept as settings.json.pre-link"; fi
    mv "$tmp" "$C/settings.json" ;;
esac

# 6. Status line.
if $statusline_on; then
  link "$R/statusline.sh" "$C/statusline.sh"
  if [ "$OS" = mac ]; then P="$HOME/.zshrc"; else P="$HOME/.bashrc"; fi
  if [ "$STATUSLINE" = plane ]; then
    grep -qx 'export CLAUDE_STATUSLINE_THEME=plane' "$P" 2>/dev/null || echo 'export CLAUDE_STATUSLINE_THEME=plane' >> "$P"
    echo "  status line: plane (open a new terminal, or run: export CLAUDE_STATUSLINE_THEME=plane)"
  else echo "  status line: squid"; fi
elif [ "$OS" = windows ]; then echo "  status line: skipped (needs WSL, see https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-WSL)"
else echo "  status line: kept yours"; fi

# 7. Mac: undo what older versions of this script set (iTerm2 reading its whole preferences from this repo,
#    and dynamic profiles that pointed at folders that exist on one machine only).
if [ "$OS" = mac ]; then
  pf="$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || true)"
  case "$pf" in "$R"*|*/claude-config/iterm2*)
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool false 2>/dev/null || true
    defaults delete com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || true
    echo "  iTerm2: stopped loading preferences from $pf (restart iTerm2)" ;;
  esac
  D="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  for f in "$D"/*.json; do [ -L "$f" ] && [ ! -e "$f" ] && rm "$f" && echo "  iTerm2: removed broken profile link $(basename "$f")"; done
  [ "$(defaults read com.googlecode.iterm2 'Default Bookmark Guid' 2>/dev/null || true)" = "september""-trip-tmux-autostart" ] && \
    defaults delete com.googlecode.iterm2 'Default Bookmark Guid' 2>/dev/null && echo "  iTerm2: default profile reset to iTerm2's own"
fi

# 7b. run-agent as a shell command.
if [ "$OS" != windows ]; then
  mkdir -p "$HOME/.local/bin"
  link "$R/bin/run-agent" "$HOME/.local/bin/run-agent"
fi

# 8. Terminal setup.
if [ "$TERMINAL" = true ] && [ "$OS" = windows ]; then
  echo "  terminal setup: skipped (tmux needs WSL, see https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-WSL)"
elif [ "$TERMINAL" = true ]; then
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
  link "$R/bin/tmux-quad" "$HOME/.local/bin/tmux-quad"
  if [ "$OS" = mac ]; then RC="$HOME/.zshrc"; SH=zsh; else RC="$HOME/.bashrc"; SH=bash; fi
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
    grep -qs '.local/bin' "$RC" || { printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"; echo "  added ~/.local/bin to PATH in $RC"; } ;;
  esac
  command -v tmux >/dev/null 2>&1 || echo "  tmux is not installed: $([ "$OS" = mac ] && echo 'brew install tmux' || echo 'sudo apt install tmux')"
  link "$R/wsl/tmux.conf" "$HOME/.tmux.conf"
  # Starship prompt (gruvbox-rainbow preset). The terminal needs a Nerd Font for the glyphs.
  if ! command -v starship >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/starship" ]; then
    curl -fsS "https://starship.rs/install.sh" | sh -s -- -y -b "$HOME/.local/bin" >/dev/null 2>&1 || echo "  starship install failed; see https://starship.rs"
  fi
  link "$R/wsl/starship.toml" "$HOME/.config/starship.toml"
  grep -qs "starship init $SH" "$RC" || printf '\neval "$(starship init %s)"\n' "$SH" >> "$RC"
  grep -qs 'CLAUDE_STATUSLINE_NF' "$RC" || echo 'export CLAUDE_STATUSLINE_NF=1' >> "$RC"
  # A reboot or WSL restart kills the runners of scheduled /run-agent runs. A systemd user service restarts them
  # at boot, silently (overdue runs are skipped); without systemd (macOS) the shell rc does it.
  if systemctl --user show-environment >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/systemd/user"
    link "$R/skills/run-agent/run-agent-revive.service" "$HOME/.config/systemd/user/run-agent-revive.service"
    systemctl --user is-enabled run-agent-revive.service >/dev/null 2>&1 || \
      { systemctl --user daemon-reload && systemctl --user enable run-agent-revive.service; } >/dev/null 2>&1 || true
  else
    grep -qs 'run-agent.sh" --revive' "$RC" || printf '%s\n' \
      '[ -x "$HOME/.claude/skills/run-agent/scripts/run-agent.sh" ] && "$HOME/.claude/skills/run-agent/scripts/run-agent.sh" --revive  # restart /run-agent runs a reboot stopped' >> "$RC"
  fi
  echo "  terminal: tmux-quad (4 panes in $PROJECTS), tmux.conf, starship prompt"

  if [ "$OS" = wsl ]; then
    W="$(wslpath "$(cmd.exe /C 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")"
    dp=(); [ "$DEFPROF" = true ] && dp=(--default)
    for S in "$W"/Packages/Microsoft.WindowsTerminal*/LocalState/settings.json; do
      [ -f "$S" ] && "$PY" "$R/wsl/wt-profile.py" "$S" "$WSL_DISTRO_NAME" "wsl.exe -d $WSL_DISTRO_NAME -- $HOME/.local/bin/tmux-quad" "JetBrainsMono Nerd Font" ${dp[@]+"${dp[@]}"} | sed 's/^/  /' || true
    done
    compgen -G "/mnt/c/Windows/Fonts/JetBrainsMonoNerdFont-*" >/dev/null || compgen -G "$W/Microsoft/Windows/Fonts/JetBrainsMonoNerdFont-*" >/dev/null \
      || echo "  Install JetBrainsMono Nerd Font on Windows (https://www.nerdfonts.com/font-downloads) or the prompt shows boxes"
    # Windows Terminal resets to 100% in the volume mixer after reboots; set it to 18% each time WSL boots.
    # The .ps1 is copied (Windows runs it from %USERPROFILE%\Scripts), so rerun install.sh after editing it.
    WP="$(cmd.exe /C 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
    mkdir -p "$(wslpath "$WP")/Scripts"
    cp "$R/wsl/terminal-volume.ps1" "$(wslpath "$WP")/Scripts/terminal-volume.ps1"
    if schtasks.exe /query /tn "Pin Windows Terminal Volume" >/dev/null 2>&1; then :; else powershell.exe -NoProfile -Command "
      \$a = New-ScheduledTaskAction -Execute conhost.exe -Argument '--headless powershell.exe -MTA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $WP\\Scripts\\terminal-volume.ps1'
      \$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
      Register-ScheduledTask -TaskName 'Pin Windows Terminal Volume' -Action \$a -Settings \$s -Force | Out-Null" || true; fi
    mkdir -p "$HOME/.config/systemd/user"
    link "$R/wsl/terminal-volume.service" "$HOME/.config/systemd/user/terminal-volume.service"
    systemctl --user is-enabled terminal-volume.service >/dev/null 2>&1 || \
      { systemctl --user daemon-reload && systemctl --user enable terminal-volume.service; } >/dev/null 2>&1 || true
    echo "  Windows Terminal volume will be set to 18% each time WSL boots"
  elif [ "$OS" = mac ]; then
    if [ -d /Applications/iTerm.app ]; then
      D="$HOME/Library/Application Support/iTerm2/DynamicProfiles"; mkdir -p "$D"
      link "$R/iterm2/DynamicProfiles/claude-tmux.json" "$D/claude-tmux.json"
      echo "  iTerm2: added the \"Claude tmux\" profile (Settings > Profiles); colors also in $R/iterm2/claude-colors.itermcolors"
      if [ "$DEFPROF" = true ]; then
        old="$(defaults read com.googlecode.iterm2 'Default Bookmark Guid' 2>/dev/null || true)"
        if [ "$old" != claude-config-claude-tmux ]; then
          [ -n "$old" ] && echo "$old" > "$C/claude-config.iterm-default.pre-link"
          defaults write com.googlecode.iterm2 'Default Bookmark Guid' -string claude-config-claude-tmux
          echo "  iTerm2: \"Claude tmux\" is now the default profile (restart iTerm2). To undo:"
          if [ -n "$old" ]; then echo "      defaults write com.googlecode.iterm2 'Default Bookmark Guid' -string '$old'"
          else echo "      defaults delete com.googlecode.iterm2 'Default Bookmark Guid'"; fi
        fi
      fi
      ls "$HOME/Library/Fonts"/JetBrainsMono*Nerd* >/dev/null 2>&1 || ls /Library/Fonts/JetBrainsMono*Nerd* >/dev/null 2>&1 \
        || echo "  Install the Nerd Font or the prompt shows boxes: brew install --cask font-jetbrains-mono-nerd-font"
    else
      echo "  iTerm2 is not installed (/Applications/iTerm.app): skipped the Claude tmux profile. Run tmux-quad in any terminal."
    fi
  else
    command -v fc-list >/dev/null 2>&1 && ! fc-list 2>/dev/null | grep -qi 'nerd font' && \
      echo "  Install a Nerd Font (https://www.nerdfonts.com/font-downloads) or the prompt shows boxes"
  fi
else
  echo "  terminal setup: not chosen"
fi

# 9. WSL helpers Claude uses (open files in Firefox/VS Code, place and screenshot windows).
if [ "$OS" = wsl ]; then
  mkdir -p "$C/local-tools"
  for f in "$R"/wsl/local-tools/*; do link "$f" "$C/local-tools/$(basename "$f")"; done
  if [ ! -e "$C/CLAUDE.local.md" ] || in_clone "$C/CLAUDE.local.md"; then link "$R/wsl/CLAUDE.local.md" "$C/CLAUDE.local.md"
  else echo "  CLAUDE.local.md is yours; the WSL notes are in $R/wsl/CLAUDE.local.md"; fi
  echo "  WSL: local-tools and CLAUDE.local.md"
fi

# 10. Save the choices so a plain ./install.sh (or an update) reapplies them.
"$PY" - "$CFG" <<EOF
import json, sys
json.dump({"projects": """$PROJECTS""", "terminal": $([ "$TERMINAL" = true ] && echo True || echo False),
           "defaultProfile": $([ "$DEFPROF" = true ] && echo True || echo False), "statusline": "$STATUSLINE",
           "settings": "$SETTINGS", "agentClash": "$CLASH", "repo": """$R""", "version": "$VERSION"},
          open(sys.argv[1], "w"), indent=2)
open(sys.argv[1], "a").write("\n")
EOF
echo "  choices saved in $CFG"
[ "$OS" = windows ] && echo "Skipped on Windows without WSL: status line, tmux and terminal setup (https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-WSL)"
echo "done. Check it with: ./install.sh --check"
