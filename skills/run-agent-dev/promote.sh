#!/usr/bin/env bash
# promote.sh [--dry]: plan 2026-11-15 R17. Run after lock-test.txt, results.csv, the chain captures and matrix.csv pass.
#   1. copies the dev MCP server to skills/run-agent/mcp/ (server.py, mcp.json pointing at the installed path);
#      in that path the dev-copy lock is off by itself (it keys on `run-agent-dev` in the file's real path)
#   2. registers it for every session: claude mcp add --transport stdio --scope user run-agent -- <server.py>
#   3. settings (the repo's settings.json and the installed ~/.claude/settings.json): permissions.allow gains
#      `mcp__run-agent__*` (the six Bash rules stay); autoMode.allow = "$defaults" + the run-agent sentence
#   4. the five agent files: apply_agents.py (tools: line + the run-agent lines)
#   5. skills/run-agent/SKILL.md gains the "MCP tools" paragraph of the dev SKILL.md
# It never touches the scripts in skills/run-agent/scripts/. A second run changes nothing. --dry prints the steps only.
set -euo pipefail
HERE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
R="$(dirname "$(dirname "$HERE")")"                      # the claude-config clone
C="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROD="$R/skills/run-agent"
INST="$HOME/.claude/skills/run-agent/mcp/server.py"      # the path sessions start the server from
DRY=""; [ "${1:-}" = "--dry" ] && DRY=1
say() { printf '%s\n' "$*"; }
run() { if [ -n "$DRY" ]; then say "would run: $*"; else "$@"; fi; }

say "1. server -> $PROD/mcp/"
run mkdir -p "$PROD/mcp"
run cp "$HERE/mcp/server.py" "$PROD/mcp/server.py"
run chmod +x "$PROD/mcp/server.py"
if [ -z "$DRY" ]; then
  printf '{"mcpServers": {"run-agent": {"type": "stdio", "command": "%s", "args": []}}}\n' "$INST" > "$PROD/mcp/mcp.json"
fi

say "2. register (user scope)"
if claude mcp get run-agent >/dev/null 2>&1; then say "   already registered"
else run claude mcp add --transport stdio --scope user run-agent -- "$INST"; fi

say "3. settings"
for f in "$R/settings.json" "$C/settings.json"; do
  [ -f "$f" ] || { say "   missing: $f"; continue; }
  run python3 - "$f" <<'PYEOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); before = json.dumps(d, sort_keys=True)
RULE = "mcp__run-agent__*"
SENT = ("Running the user's own run-agent tool (run-agent.sh, `run-agent`, launch.py, jobs.py, the run-agent MCP server) "
        "with any flags, alone or inside a compound command: starting, scheduling, handing off, listing or cancelling "
        "Claude Code agent sessions in tmux panes, including an agent scheduling its own successor and cancelling jobs "
        "it did not create.")
allow = d.setdefault("permissions", {}).setdefault("allow", [])
if RULE not in allow:
    allow.append(RULE)
am = d.setdefault("autoMode", {}).setdefault("allow", [])
for x in ("$defaults", SENT):
    if x not in am:
        am.append(x)
if json.dumps(d, sort_keys=True) != before:
    open(p, "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print("   changed:", p)
else:
    print("   unchanged:", p)
PYEOF
done

say "4. agent files"
if [ -n "$DRY" ]; then python3 "$HERE/apply_agents.py" "$R/agents" --check; else python3 "$HERE/apply_agents.py" "$R/agents"; fi

say "5. SKILL.md"
if grep -q 'mcp__run-agent__next' "$PROD/SKILL.md"; then say "   already names the tools"
elif [ -n "$DRY" ]; then say "   would append the MCP tools paragraph"
else sed -n '/^MCP tools (server `run-agent`/,$p' "$HERE/SKILL.md" | { printf '\n'; cat; } >> "$PROD/SKILL.md"; say "   appended"; fi

say "done. check: claude mcp list"
