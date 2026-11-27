#!/usr/bin/env bash
# Install this repo's Claude Code setup into ~/.claude. Your own files stay unless a flag says otherwise; no backup
# copy (.pre-link) is ever made, and nothing inside the clone is changed.
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
  --settings merge|keep|replace      settings.json: add only the keys you lack (default), leave it, or use the
                                     repo's (yours is deleted, no copy kept)
  --agent-clash keep|replace|skip    what to do when ~/.claude/agents or ~/.claude/skills already has one of this
                                     repo's names. Without the flag yours stays and the repo's is not installed
                                     (same as skip). keep: yours stays, repo copy added as <name>-claude-config.
                                     replace: yours is deleted (no copy kept) and the repo's is linked.
                                     Per name: planner=keep,worker=replace
  --check                            print one PASS/FAIL line per installed item; exit 1 on any FAIL
  --help                             this text
Exit codes: 0 ok, 1 error or a FAIL in --check, 2 bad flag.
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
# Evaluator tools: local-tools/common/ is for every OS; each install gets its own OS's folder beside it and no other.
case "$OS" in wsl) TOOLS_OS=wsl ;; mac) TOOLS_OS=macos ;; *) TOOLS_OS="" ;; esac
tool_names() {  # tool_names <folder under local-tools/>...: the file names in them, one per line
  local d f
  for d in "$@"; do for f in "$R/local-tools/$d"/*; do [ -e "$f" ] && basename "$f"; done; done
  return 0
}
# Git Bash makes copies for ln -s unless told to make real Windows symlinks (needs Developer Mode or admin).
[ "$OS" = windows ] && export MSYS=winsymlinks:nativestrict
# Windows Python reads files as cp1252 by default; settings.json and the agents are UTF-8 (em dashes, emoji).
export PYTHONUTF8=1
# What to type to get a missing tool, per system.
how_python() { case "$OS" in mac) echo "xcode-select --install   (or: brew install python)" ;; windows) echo "winget install Python.Python.3.12" ;; *) echo "sudo apt-get install -y python3" ;; esac; }
how_tmux() { case "$OS" in mac) echo "brew install tmux   (Homebrew: https://brew.sh)" ;; *) echo "sudo apt-get install -y tmux" ;; esac; }
PY=""
for p in python3 python; do
  command -v "$p" >/dev/null 2>&1 || continue
  # A stock Mac has /usr/bin/python3 as a stub that opens an "install developer tools" window; do not start it.
  if [ "$OS" = mac ] && [ "$(uname -s)" = Darwin ] && [ "$(command -v "$p")" = "/usr/bin/$p" ] && ! xcode-select -p >/dev/null 2>&1; then continue; fi
  "$p" -c 'import json' >/dev/null 2>&1 && { PY="$p"; break; }
done
if [ -z "$PY" ]; then
  echo "install.sh: python3 is missing (the settings merge needs it). Install it with: $(how_python)" >&2
  case " $* " in *" --terminal "*) [ "$OS" = windows ] || command -v tmux >/dev/null 2>&1 || echo "install.sh: tmux is missing (--terminal needs it). Install it with: $(how_tmux)" >&2 ;; esac
  echo "install.sh: nothing was changed; install what is listed and rerun" >&2
  exit 1
fi

# readlink -f keeps Git Bash's /c/... form (Windows python would print C:\...); old macOS lacks it, so python is the fallback.
resolve() { readlink -f "$1" 2>/dev/null || "$PY" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
# in_clone <path> [repo path]: <path> is a link into this clone. On Windows, where an account without symlink rights
# gets copies, an identical copy of [repo path] counts too.
in_clone() {
  if [ -L "$1" ]; then case "$(resolve "$1")" in "$R"|"$R"/*) return 0 ;; esac; fi
  [ "$OS" = windows ] && [ -n "${2:-}" ] && [ -e "$1" ] && diff -rq "$1" "$2" >/dev/null 2>&1
}
# Windows copies: $C/claude-config.copies holds a hash for every file this installer copied. A copy whose files all
# still match was not edited, so a later run may replace it with the repo's newer one.
copies() {  # copies record|unedited <path>
  "$PY" - "$1" "$2" "$C/claude-config.copies" <<'PYEOF'
import hashlib, io, json, os, sys
mode, top, store = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3]
def files(p):
    if os.path.isfile(p):
        yield p
    for d, dirs, names in os.walk(p):
        dirs[:] = [x for x in dirs if x != "__pycache__"]
        for n in names:
            if n != ".DS_Store":
                yield os.path.join(d, n)
def digest(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()
try:
    with io.open(store, encoding="utf-8") as f:
        seen = json.load(f)
except (OSError, ValueError):
    seen = {}
if mode == "record":
    seen = {k: v for k, v in seen.items() if k != top and not k.startswith(top + os.sep)}
    seen.update((p, digest(p)) for p in files(top))
    with open(store, "w") as f:
        json.dump(seen, f, indent=0, sort_keys=True)
else:
    found = list(files(top))
    sys.exit(0 if found and all(seen.get(p) == digest(p) for p in found) else 1)
PYEOF
}
old_copy() { [ "$OS" = windows ] && [ ! -L "$1" ] && [ -e "$1" ] && copies unedited "$1"; }
# replaceable <path> <repo path>: this installer put it there and you have not changed it
replaceable() { in_clone "$1" "$2" || old_copy "$1"; }
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
# ours <link> <path in the repo>: the link points into this clone, or it is broken and its target ends in that repo
# path (this installer made it for a clone that has since moved). With no saved choices, what is installed is the
# only record of what was chosen, and a moved clone leaves every one of those links broken.
ours() { in_clone "$1" || { [ -L "$1" ] && [ ! -e "$1" ] && case "$(readlink "$1")" in */"$2") true ;; *) false ;; esac; }; }
d_term=false; ours "$HOME/.local/bin/tmux-quad" bin/tmux-quad && d_term=true
d_status=keep
if ours "$C/statusline.sh" statusline.sh; then
  d_status=squid; grep -qs 'CLAUDE_STATUSLINE_THEME=plane' "$HOME/.bashrc" "$HOME/.zshrc" && d_status=plane
elif ! had_statusline; then d_status=squid; fi
d_settings=merge; ours "$C/settings.json" settings.json && d_settings=replace
fill PROJECTS projects "$HOME/files"
fill TERMINAL terminal "$d_term"
fill DEFPROF defaultProfile false
fill STATUSLINE statusline "$d_status"
fill SETTINGS settings "$d_settings"
fill CLASH agentClash ""
PROJECTS="$(expand "$PROJECTS")"
[ -n "$reused" ] && echo "reusing saved choices from $CFG:$reused"
if [ -z "$CHECK" ] && [ "$TERMINAL" = true ] && [ "$OS" != windows ] && ! command -v tmux >/dev/null 2>&1; then
  echo "install.sh: tmux is missing (--terminal needs it). Install it with: $(how_tmux)" >&2
  echo "install.sh: nothing was changed; install it and rerun, or pass --no-terminal" >&2
  exit 1
fi

# settings_rules <file>: rewrite the repo's two `~/files/claude-config/...` run-agent allow rules to this clone's
# absolute path ($R). Claude Code matches Bash rules on the literal command text, so a `~` rule never matches the
# absolute path an agent types; the committed settings.json keeps the `~` form (no personal path in the repo) and the
# installed copy carries the real one. Idempotent; drops duplicate rules.
# It also adds this clone's mods (mods/defer-artifact) to env.CLAUDE_CODE_PLUGIN_DIRS as absolute paths, after any
# directories already there (in <file>, in the installed settings.json, or in the shell's CLAUDE_CODE_PLUGIN_DIRS).
settings_rules() {
  local rn="$R"; [ "$OS" = windows ] && command -v cygpath >/dev/null 2>&1 && rn="$(cygpath -m "$R")"
  "$PY" - "$1" "$R" "$C/settings.json" "$OS" "$rn" <<'PYEOF'
import json, os, re, sys
f, repo, installed, osname, native = sys.argv[1:6]
s = json.load(open(f))
sep = ";" if osname == "windows" else ":"
def dirs_in(v):
    return [d for d in (v or "").split(sep) if d.strip()]
prior = []
try:
    prior = dirs_in(json.load(open(installed)).get("env", {}).get("CLAUDE_CODE_PLUGIN_DIRS"))
except Exception:
    pass
mods = [native.rstrip("/") + "/mods/" + m for m in sorted(os.listdir(os.path.join(repo, "mods")))
        if os.path.isfile(os.path.join(repo, "mods", m, ".claude-plugin", "plugin.json"))] if os.path.isdir(os.path.join(repo, "mods")) else []
def stale(path):
    """a path this installer wrote for a clone that has since moved or been deleted"""
    return os.path.isabs(os.path.expanduser(path)) and not os.path.exists(os.path.expanduser(path))
modnames = {m.rsplit("/", 1)[1] for m in mods}
dirs = []
for d in dirs_in(s.get("env", {}).get("CLAUDE_CODE_PLUGIN_DIRS")) + prior + dirs_in(os.environ.get("CLAUDE_CODE_PLUGIN_DIRS")) + mods:
    parts = d.replace("\\", "/").rstrip("/").rsplit("/", 2)
    if len(parts) == 3 and parts[1] == "mods" and parts[2] in modnames and d not in mods and stale(d):
        continue   # this mod under the clone's old path
    if d not in dirs:
        dirs.append(d)
if dirs:
    s.setdefault("env", {})["CLAUDE_CODE_PLUGIN_DIRS"] = sep.join(dirs)
allow = s.setdefault("permissions", {}).setdefault("allow", [])
out = []
for r in allow:
    for pre in ("Bash(~/files/claude-config/", "Bash(bash ~/files/claude-config/"):
        if r.startswith(pre):
            r = pre.replace("~/files/claude-config", repo) + r[len(pre):]
    old = re.match(r"Bash\((?:bash )?(.+)/skills/run-agent/scripts/(?:run-agent\.sh )?\*\)$", r)
    if old and old.group(1) not in (repo, "~/.claude") and stale(old.group(1)):
        continue   # a rule for the clone's old path
    if r not in out:
        out.append(r)
s["permissions"]["allow"] = out
json.dump(s, open(f, "w"), indent=2); open(f, "a").write("\n")
PYEOF
}
# settings_generate <dst>: the repo's settings.json with settings_rules applied (what `--settings replace` installs)
settings_generate() { cp "$R/settings.json" "$1" && settings_rules "$1"; }
# ---- repo contents ----------------------------------------------------------------------------------------------
repo_agents() { for f in "$R"/agents/*.md; do head -5 "$f" | grep -q '^name:' && basename "$f" .md; done; }
repo_skills() { for s in "$R"/skills/*/; do [ -f "$s/SKILL.md" ] && basename "$s"; done; }
# ~/.claude/agents is either a link to the repo's agents/ (whole folder) or the user's own folder (one link per agent).
agents_whole() { [ ! -e "$C/agents" ] && [ ! -L "$C/agents" ] || replaceable "$C/agents" "$R/agents"; }
# run-agent's MCP server (agents hand off through its tools, so the auto-mode classifier never reads a handoff).
# Registered for every session at user scope, from the installed skill path when that is a link into this clone.
mcp_server() { if in_clone "$C/skills/run-agent" "$R/skills/run-agent"; then echo "$C/skills/run-agent/mcp/server.py"; else echo "$R/skills/run-agent/mcp/server.py"; fi; }
mcp_add_cmd() { echo "claude mcp add --transport stdio --scope user run-agent -- $(mcp_server)"; }
# mcp_registered: ~/.claude.json has a user-scope run-agent server whose command is this clone's server.py
mcp_registered() {
  "$PY" - "$HOME/.claude.json" "$R/skills/run-agent/mcp/server.py" <<'EOF' 2>/dev/null
import json, os, sys
s = json.load(open(sys.argv[1])).get("mcpServers", {}).get("run-agent") or {}
c = s.get("command", "")
sys.exit(0 if c and os.path.realpath(os.path.expanduser(c)) == os.path.realpath(sys.argv[2]) else 1)
EOF
}

# =================================================================================================================
# --check
# =================================================================================================================
if [ -n "$CHECK" ]; then
  fails=0
  pass() { echo "PASS $*"; }
  fail() { echo "FAIL $*"; fails=$((fails + 1)); }
  skip() { echo "SKIP $*"; }
  warn() { echo "WARN $*"; }
  linked() {  # linked <path> <label>: path is a symlink resolving into the clone (or, on Windows without symlinks, a copy)
    if in_clone "$1"; then pass "$2 -> $(resolve "$1")"
    elif [ "$OS" = windows ] && [ -e "$1" ] && [ -n "${3:-}" ] && diff -rq "$1" "$3" >/dev/null 2>&1; then pass "$2 (copy of $3)"
    elif [ -e "$1" ] && [ ! -L "$1" ]; then skip "$2: $1 is yours (kept; repo's not installed)"
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
  # the assistant agent lives in assistant/ (not agents/, so it is not installed for every folder); a project links
  # its .claude/agents/assistant.md to it, and the frontmatter starts mcp/server.py and hooks/guard.py next to the real file
  if [ -f "$R/assistant/assistant.md" ]; then
    ad="$R/assistant"; am="$(grep -c -F '$(readlink -f \"$f\")\")/mcp/server.py' "$ad/assistant.md")"; ah="$(grep -c -F '$(readlink -f \"$f\")\")/hooks/guard.py' "$ad/assistant.md")"
    if [ -e "$C/agents/assistant.md" ] || [ -L "$C/agents/assistant.md" ]; then fail "assistant agent: $C/agents/assistant.md exists, so it starts in every folder (remove it; the agent is linked into one project from $ad/assistant.md)"
    elif [ "$am" = 1 ] && [ "$ah" = 1 ] && [ -f "$ad/mcp/server.py" ] && [ -f "$ad/hooks/guard.py" ]; then pass "assistant agent (agent file, MCP server and guard hook in $(cd "$ad" && pwd -P); starts only where a project links it)"
    else fail "assistant agent: the frontmatter of $ad/assistant.md does not resolve to $ad/mcp/server.py and $ad/hooks/guard.py"; fi
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
  if [ "$SETTINGS" = keep ]; then skip "defer-artifact mod (settings.json kept; add $R/mods/defer-artifact to env.CLAUDE_CODE_PLUGIN_DIRS to load it)"
  elif "$PY" -c 'import json,sys,os; v=json.load(open(sys.argv[1])).get("env",{}).get("CLAUDE_CODE_PLUGIN_DIRS",""); d=sys.argv[2]; sys.exit(0 if d in v.split(";" if sys.argv[3] == "windows" else ":") and os.path.isfile(os.path.join(d,".claude-plugin","plugin.json")) else 1)' "$C/settings.json" "$(if [ "$OS" = windows ] && command -v cygpath >/dev/null 2>&1; then cygpath -m "$R"; else echo "$R"; fi)/mods/defer-artifact" "$OS" 2>/dev/null; then
    pass "defer-artifact mod in env.CLAUDE_CODE_PLUGIN_DIRS ($R/mods/defer-artifact)"
  else fail "defer-artifact mod missing from env.CLAUDE_CODE_PLUGIN_DIRS in settings.json (rerun install.sh)"; fi
  if [ "$SETTINGS" = replace ]; then
    gen="$C/.settings.check.$$"
    if settings_generate "$gen" 2>/dev/null && [ -f "$C/settings.json" ] && ! [ -L "$C/settings.json" ] && \
       "$PY" -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))==json.load(open(sys.argv[2])) else 1)' "$gen" "$C/settings.json" 2>/dev/null; then
      pass "settings.json generated from the repo's (run-agent rules naming $R)"
    elif [ -L "$C/settings.json" ]; then fail "settings.json is still a link to the repo's (rerun install.sh: the installed copy must name $R in its run-agent rules)"
    else skip "settings.json differs from the repo's (edited since install; rerun install.sh to regenerate)"; fi
    rm -f "$gen"
  fi
  if command -v claude >/dev/null 2>&1; then
    if claude doctor </dev/null >/dev/null 2>&1; then pass "claude doctor"; else fail "claude doctor exited non-zero"; fi
  else fail "claude not on PATH (install: curl -fsSL https://claude.ai/install.sh | bash)"; fi
  if [ "$STATUSLINE" = keep ] || [ "$OS" = windows ]; then skip "status line ($([ "$OS" = windows ] && echo 'needs WSL' || echo 'kept yours'))"
  else
    linked "$C/statusline.sh" "statusline.sh" "$R/statusline.sh"
    n="$(bash "$C/statusline.sh" --preview "$STATUSLINE" 2>/dev/null | wc -l | tr -d ' ')" || n=0
    if [ "${n:-0}" -gt 0 ]; then pass "statusline.sh --preview $STATUSLINE ($n lines)"; else fail "statusline.sh --preview $STATUSLINE printed nothing"; fi
  fi
  # tracked files fail; a file git does not track (yours, never pushed) is only listed
  if out="$(bash "$R/bin/find-personal-paths.sh" "$R")"; then pass "no personal paths in the clone's tracked files"
  else fail "personal paths in: $(echo "$out" | grep -v '^WARN ' | tr '\n' ' ')"; fi
  w="$(echo "$out" | sed -n 's/^WARN //p' | tr '\n' ' ')"
  [ -n "$w" ] && warn "personal paths in untracked files (not pushed, so not a failure): $w"
  # a leftover backup from an older install.sh: a .pre-link skill or agent still loads in every session
  while IFS= read -r l; do [ -n "$l" ] && warn "leftover from an older install, safe to delete: $l"; done < <(find "$C" -maxdepth 3 -name '*.pre-link*' 2>/dev/null | grep -v -e "^$C/projects/" -e "^$C/file-history/" || true)
  if [ "$OS" != windows ]; then
    if in_clone "$HOME/.local/bin/run-agent"; then pass "run-agent shell command (~/.local/bin/run-agent)"
    else fail "run-agent shell command missing (rerun install.sh)"; fi
    if in_clone "$HOME/.local/bin/guard" && [ -f "$C/hooks/usage-guard/usage_guard.py" ]; then pass "usage-guard (~/.claude/hooks/usage-guard, ~/.local/bin/guard)"
    else fail "usage-guard links missing (rerun install.sh)"; fi
    if [ "$SETTINGS" = keep ]; then skip "usage-guard hooks, /run-agent hook and run-agent allow rules (settings.json kept; copy them from $R/settings.json to use them)"
    else
    if grep -qs 'usage-guard/usage_guard.py' "$C/settings.json"; then pass "usage-guard hooks in settings.json"
    else fail "usage-guard hooks missing from ~/.claude/settings.json (rerun install.sh)"; fi
    # a typed /run-agent runs through this hook with no model turn (zero tokens); the skill is the fallback
    if "$PY" -c 'import json,sys; s=json.load(open(sys.argv[1])); hs=s.get("hooks",{}).get("UserPromptExpansion",[]); sys.exit(0 if any(h.get("matcher")=="run-agent" and any("run-agent.sh" in x.get("command","") and "--hook" in x.get("command","") and int(x.get("timeout",0))>=60 for x in h.get("hooks",[])) for h in hs) else 1)' "$C/settings.json" 2>/dev/null; then
      pass "/run-agent hook (UserPromptExpansion, matcher run-agent, timeout >= 60 s) in settings.json"
    else fail "/run-agent hook missing from settings.json (rerun install.sh with --settings merge or replace)"; fi
    # every form run-agent is called in has a narrow allow rule, so auto mode never sends one to the classifier
    rules=$("$PY" - "$C/settings.json" "$R" <<'PYEOF'
import json, sys
s = json.load(open(sys.argv[1])); repo = sys.argv[2]
have = set(s.get("permissions", {}).get("allow", []))
want = ["Bash(~/.claude/skills/run-agent/scripts/run-agent.sh *)", f"Bash({repo}/skills/run-agent/scripts/run-agent.sh *)",
        "Bash(bash ~/.claude/skills/run-agent/scripts/*)", f"Bash(bash {repo}/skills/run-agent/scripts/*)",
        "Bash(~/.local/bin/run-agent *)", "Bash(run-agent *)"]
missing = [w for w in want if w not in have]
print(("MISSING " + " ".join(missing)) if missing else ("OK " + "  ".join(want)))
PYEOF
)
    case "$rules" in
      OK*) pass "run-agent allow rules (6): ${rules#OK }" ;;
      *) fail "run-agent allow rule missing: ${rules#MISSING } (rerun install.sh)" ;;
    esac
    fi
    if mcp_registered; then pass "run-agent MCP server registered (user scope, $(mcp_server))"
    else fail "run-agent MCP server not registered in ~/.claude.json (run: $(mcp_add_cmd))"; fi
    command -v uv >/dev/null 2>&1 || echo "NOTE uv is not on PATH: the run-agent and assistant MCP servers start with uv (https://docs.astral.sh/uv/)"
    # runs that failed or were skipped since a human last looked (run-agent jobs marks them seen)
    while IFS= read -r l; do [ -n "$l" ] && echo "NOTE scheduled run $l"; done < <(bash "$R/skills/run-agent/scripts/run-agent.sh" --failures 2>/dev/null)
    if out="$(bash "$R/skills/run-agent/scripts/run-agent.sh" --health 2>&1)"; then pass "scheduled /run-agent runs: $(grep -c '^ok' <<<"$out" || true) pending, every runner sleeping"
    else fail "a scheduled /run-agent run's runner is dead or errored: $(grep '^FAIL' <<<"$out" | head -1) (cancel it or run run-agent.sh --revive)"; fi
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
  fi
  # Evaluator tools: one line per tool of this OS, and a FAIL for a tool of another OS found installed.
  for d in common $TOOLS_OS; do
    for f in "$R/local-tools/$d"/*; do n="$(basename "$f")"; linked "$C/local-tools/$n" "local-tools/$n ($d)" "$f"; done
  done
  mine=" $(tool_names common $TOOLS_OS | tr '\n' ' ')"
  for d in wsl macos; do
    [ "$d" = "$TOOLS_OS" ] && continue
    for n in $(tool_names "$d"); do
      case "$mine" in *" $n "*) continue ;; esac
      if [ -e "$C/local-tools/$n" ] || [ -L "$C/local-tools/$n" ]; then fail "local-tools/$n is a $d tool; this install is ${TOOLS_OS:-neither wsl nor macos} (run ./install.sh)"; fi
    done
  done
  if [ "$OS" = mac ]; then
    if [ -d "${CLAUDE_CONFIG_FIREFOX_APP:-/Applications/Firefox.app}" ]; then pass "Firefox installed (the evaluator shows each item as a page in a Firefox of its own; phone pictures come from it)"
    else warn "Firefox not installed: items open in the default browser, no phone pictures"; fi
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
# link <src> <dst>: make <dst> a link to <src>. A link already there is replaced; a real file of yours stays where it
# is and the repo's is not installed. It never writes inside the clone and never fails without saying why.
link() {
  local src="$1" dst="$2" rdst err
  rdst="$(resolve "$(dirname "$dst")")/$(basename "$dst")"
  case "$rdst" in "$R"|"$R"/*)
    echo "install: refusing to link $dst: it resolves to $rdst, inside the clone ($R). Remove the link at $(dirname "$dst") and rerun." >&2; exit 1 ;;
  esac
  if [ -L "$dst" ]; then rm "$dst"
  elif [ -e "$dst" ] && replaceable "$dst" "$src"; then rm -rf "$dst"  # Windows: our own earlier copy
  elif [ -e "$dst" ]; then echo "  kept yours: $dst (repo's not installed)"; return 0; fi
  if err="$(ln -s "$src" "$dst" 2>&1)"; then return 0; fi
  if [ "$OS" = windows ] && cp -R "$src" "$dst" 2>/dev/null; then
    copies record "$dst"
    echo "  (copied $dst: this Windows account cannot make symlinks; rerun install.sh after updates)"; return 0
  fi
  echo "install: could not link $dst: ${err:-ln -s failed}" >&2; exit 1
}

echo "installing claude-config $VERSION from $R into $C ($OS)"
mkdir -p "$C" "$PROJECTS"

# 1. Links left by an earlier install: a clone that has since moved, or the layout before v1.3.
#    A link under ~/.claude whose target ends in its own path below ~/.claude (skills/<name> -> .../skills/<name>) and is
#    now missing, or sits in another clone of this repo, came from this installer. It is pointed at this clone, or
#    removed when this repo no longer has that file. Nothing of yours matches: your files are not such links.
for p in "$C"/* "$C"/skills/* "$C"/agents/* "$C"/hooks/*; do
  [ -L "$p" ] || continue
  if [ -e "$p" ] && in_clone "$p"; then continue; fi   # a working link into this clone
  t="$(readlink "$p")"; rel="${p#"$C"/}"
  case "$t" in */"$rel") root="${t%/"$rel"}" ;; *) continue ;; esac
  if [ -e "$p" ]; then
    { [ -f "$root/install.sh" ] && [ -d "$root/skills/run-agent" ]; } || continue   # a live link of yours
    was="was $t, another clone"
  else was="was $t, now missing"; fi
  rm "$p"
  if [ -e "$R/$rel" ]; then
    err="$(ln -s "$R/$rel" "$p" 2>&1)" || { echo "install: could not link $p: $err" >&2; exit 1; }
    echo "  relinked $p ($was)"
  else echo "  removed $p ($was; this repo has no $rel any more)"; fi
done
#    Folders this script fills one item at a time must be real folders. Before v1.3 ~/.claude/hooks was one link to
#    the clone's hooks/, and filling it wrote into the clone.
for d in skills hooks; do
  if [ -L "$C/$d" ] && { in_clone "$C/$d" || [ ! -e "$C/$d" ]; }; then
    rm "$C/$d"; echo "  $C/$d was a link (older layout); it is now a folder of its own"
  fi
done
mkdir -p "$C/skills" "$C/hooks"

ITERM_OLD="$(saved itermDefault)"
if [ -f "$C/claude-config.iterm-default.pre-link" ]; then
  [ -n "$ITERM_OLD" ] || ITERM_OLD="$(head -1 "$C/claude-config.iterm-default.pre-link")"
  rm "$C/claude-config.iterm-default.pre-link"
fi

# 2. Agents.
if agents_whole; then
  link "$R/agents" "$C/agents"; echo "  agents: linked $C/agents -> $R/agents"
else
  echo "  agents: you have your own $C/agents, so each repo agent is added next to yours"
  for a in $(repo_agents); do
    f="$C/agents/$a.md"
    if replaceable "$f" "$R/agents/$a.md" || [ ! -e "$f" ]; then link "$R/agents/$a.md" "$f"; continue; fi
    case "$(clash_mode "$a")" in
      keep)    sed "s/^name: *$a *\$/name: $a-claude-config/" "$R/agents/$a.md" > "$C/agents/$a-claude-config.md"
               echo "  agent $a: kept yours; the repo's is $a-claude-config (claude --agent $a-claude-config)" ;;
      replace) rm -f "$f"; link "$R/agents/$a.md" "$f"; echo "  agent $a: now the repo's (yours deleted)" ;;
      skip)    echo "  agent $a: kept yours, repo's skipped" ;;
      *)       echo "  kept yours: $f (repo's not installed)" ;;
    esac
  done
  for d in report-writer evals; do  # folders the report-writer agent reads
    if replaceable "$C/agents/$d" "$R/agents/$d" || [ ! -e "$C/agents/$d" ]; then link "$R/agents/$d" "$C/agents/$d"; else echo "  agents/$d is yours; left alone"; fi
  done
fi

# 3. Skills.
for s in $(repo_skills); do
  d="$C/skills/$s"
  if replaceable "$d" "$R/skills/$s" || { [ ! -e "$d" ] && [ ! -L "$d" ]; }; then link "$R/skills/$s" "$d"; continue; fi
  case "$(clash_mode "$s")" in
    keep)    k="$C/skills/$s-claude-config"; rm -rf "$k"; mkdir -p "$k"
             for f in "$R/skills/$s"/*; do [ "$(basename "$f")" = SKILL.md ] || link "$f" "$k/$(basename "$f")"; done
             sed "s/^name: *$s *\$/name: $s-claude-config/" "$R/skills/$s/SKILL.md" > "$k/SKILL.md"
             echo "  skill $s: kept yours; the repo's is /$s-claude-config" ;;
    replace) rm -rf "$d"; link "$R/skills/$s" "$d"; echo "  skill $s: now the repo's (yours deleted)" ;;
    skip)    echo "  skill $s: kept yours, repo's skipped" ;;
    *)       echo "  kept yours: $d (repo's not installed)" ;;
  esac
done
echo "  skills: $(repo_skills | tr '\n' ' ')"

# 4. CLAUDE.md: linked only when you have none.
if [ ! -e "$C/CLAUDE.md" ] || replaceable "$C/CLAUDE.md" "$R/CLAUDE.md"; then link "$R/CLAUDE.md" "$C/CLAUDE.md"; echo "  CLAUDE.md: linked"
else
  echo "  CLAUDE.md: yours is left as it is. To use the repo's rules too, add this line to $C/CLAUDE.md:"
  echo "      @$R/CLAUDE.md"
fi

# 5. settings.json.
statusline_on=false
[ "$STATUSLINE" != keep ] && [ "$OS" != windows ] && statusline_on=true
case "$SETTINGS" in
  replace)
    # a generated copy, not a link: the installed file names this clone's absolute path in the run-agent allow
    # rules (settings_rules), which the committed repo file must not carry. Rerun install.sh after editing the repo's.
    [ -L "$C/settings.json" ] && rm "$C/settings.json"   # an older install linked it; a real file of yours is overwritten, no copy kept
    settings_generate "$C/settings.json"
    echo "  settings.json: generated from the repo's, run-agent allow rules naming $R (rerun install.sh after editing the repo's)" ;;
  keep)    echo "  settings.json: left as it is"
           $statusline_on && ! grep -qs 'statusline.sh' "$C/settings.json" && \
             echo "  to see the status line, add to settings.json: \"statusLine\": {\"type\": \"command\", \"command\": \"bash ~/.claude/statusline.sh\"}" ;;
  merge)
    args=()
    # Your values win, statusLine included: with squid/plane the repo's statusLine is added only when you have none.
    $statusline_on || args=(--drop-key statusLine)
    tmp="$C/.settings.merge.$$"
    "$PY" "$R/bin/merge-settings.py" "$R/settings.json" "$C/settings.json" "$tmp" ${args[@]+"${args[@]}"} | sed 's/^/  /'
    settings_rules "$tmp"
    if $statusline_on && ! grep -qs 'statusline.sh' "$tmp"; then
      echo "  your settings.json has its own statusLine, which the merge keeps. To use this repo's, set it to:"
      echo "      \"statusLine\": {\"type\": \"command\", \"command\": \"bash ~/.claude/statusline.sh\"}"
    fi
    [ -L "$C/settings.json" ] && rm "$C/settings.json"
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
  # usage-guard: the worker's launch limits (hooks in settings.json) and the user's `guard` command
  mkdir -p "$C/hooks"
  link "$R/hooks/usage-guard" "$C/hooks/usage-guard"
  link "$R/hooks/usage-guard/guard" "$HOME/.local/bin/guard"
  # run-agent's MCP server, for every session
  if ! command -v claude >/dev/null 2>&1; then
    echo "  run-agent MCP server: claude is not on PATH. After installing Claude Code, run:"
    echo "      $(mcp_add_cmd)"
  elif mcp_registered; then echo "  run-agent MCP server: already registered"
  else
    claude mcp remove --scope user run-agent >/dev/null 2>&1 || true   # an older registration pointing elsewhere
    if claude mcp add --transport stdio --scope user run-agent -- "$(mcp_server)" >/dev/null 2>&1; then echo "  run-agent MCP server: registered (user scope, $(mcp_server))"
    else echo "  run-agent MCP server: not registered (claude mcp add failed). Run: $(mcp_add_cmd)"; fi
  fi
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
  fi
  # No systemd, or a user manager that would not enable the unit (CI runners, containers): the shell rc does it.
  if ! systemctl --user is-enabled run-agent-revive.service >/dev/null 2>&1; then
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
          [ -n "$old" ] && ITERM_OLD="$old"   # saved in claude-config.json (step 10) as itermDefault
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

# 9. Evaluator tools (open, place, show and close the windows of an evaluator run; phone pictures; file pages):
#    local-tools/common/* on every OS, plus local-tools/wsl/* on WSL or local-tools/macos/* on a Mac, and no other OS's.
mkdir -p "$C/local-tools"
mine=" $(tool_names common $TOOLS_OS | tr '\n' ' ')"
for p in "$C"/local-tools/*; do   # a link from an earlier install (the old wsl/local-tools/, another OS's folder, a moved clone)
  [ -L "$p" ] || continue
  case "$mine" in *" $(basename "$p") "*) continue ;; esac   # relinked below
  t="$(readlink "$p")"
  case "$t" in */wsl/local-tools/*|*/local-tools/wsl/*|*/local-tools/macos/*|*/local-tools/common/*) ;; *) continue ;; esac   # this installer's
  rm "$p"; echo "  removed $p (was $t: not a tool of this OS)"
done
for d in common $TOOLS_OS; do
  for f in "$R/local-tools/$d"/*; do link "$f" "$C/local-tools/$(basename "$f")"; done
done
echo "  evaluator tools: local-tools/common${TOOLS_OS:+ and local-tools/$TOOLS_OS} linked into $C/local-tools"
if [ "$OS" = mac ] && [ ! -d "${CLAUDE_CONFIG_FIREFOX_APP:-/Applications/Firefox.app}" ]; then
  echo "  Firefox is not installed: the evaluator opens each item in your default browser and cannot make phone pictures (brew install --cask firefox)."
fi
if [ "$OS" = wsl ]; then
  if [ ! -e "$C/CLAUDE.local.md" ] || in_clone "$C/CLAUDE.local.md"; then link "$R/wsl/CLAUDE.local.md" "$C/CLAUDE.local.md"
  else echo "  CLAUDE.local.md is yours; the WSL notes are in $R/wsl/CLAUDE.local.md"; fi
  echo "  WSL: local-tools and CLAUDE.local.md"
fi

# 10. Save the choices so a plain ./install.sh (or an update) reapplies them. itermDefault is the iTerm2 default
#     profile from before --default-profile (older versions kept it in claude-config.iterm-default.pre-link).
"$PY" - "$CFG" "$ITERM_OLD" <<EOF
import json, sys
d = {"projects": """$PROJECTS""", "terminal": $([ "$TERMINAL" = true ] && echo True || echo False),
     "defaultProfile": $([ "$DEFPROF" = true ] && echo True || echo False), "statusline": "$STATUSLINE",
     "settings": "$SETTINGS", "agentClash": "$CLASH", "repo": """$R""", "version": "$VERSION"}
if sys.argv[2]:
    d["itermDefault"] = sys.argv[2]
json.dump(d, open(sys.argv[1], "w"), indent=2)
open(sys.argv[1], "a").write("\n")
EOF
echo "  choices saved in $CFG"
[ "$OS" = windows ] && echo "Skipped on Windows without WSL: status line, tmux and terminal setup (https://github.com/Gidntsquia/claude-config/wiki/Setting-Up-WSL)"
echo "done. Check it with: ./install.sh --check"
