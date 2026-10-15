#!/usr/bin/env bash
# usage: find-sessions.sh <stop-time> [projects-dir]
# Lists the Claude Code sessions a WSL/Windows stop killed: top-level <projects-dir>/<project>/<id>.jsonl
# whose mtime is within [stop - 10 min, stop + 5 s]. projects-dir defaults to $RS_PROJECTS or ~/.claude/projects.
# Ignores <id>/subagents/ and memory/. Prints one TSV line per candidate, oldest mtime first:
#   session-id  cwd  agent  model  permission-mode  mid-task(yes/no)  mtime-ET  transcript-path
# stop-time is anything `date -d` reads, e.g. '2026-10-15 04:56:11' (local = ET) or 'Thu 2026-10-15 04:56:11 EDT'.
set -euo pipefail
if [ $# -lt 1 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; [ $# -ge 1 ] && exit 0; exit 2
fi
stop=$(date -d "$1" +%s) || { echo "find-sessions: cannot read stop time: $1" >&2; exit 2; }
dir="${2:-${RS_PROJECTS:-$HOME/.claude/projects}}"
[ -d "$dir" ] || { echo "find-sessions: no such projects dir: $dir" >&2; exit 2; }
dir=$(realpath -- "$dir")   # absolute, so no path ever starts with '-'

python3 -I - "$stop" "$dir" <<'PY'
import json, os, sys, time
stop, root = int(sys.argv[1]), sys.argv[2]
lo, hi = stop - 600, stop + 5
CONV = {"user", "assistant", "system"}
END_SUBTYPES_MIDTASK = {"api_error"}           # a turn that died while retrying counts as mid-task

def parts(msg):
    c = (msg or {}).get("content")
    return [p for p in c if isinstance(p, dict)] if isinstance(c, list) else []

def scan(path):
    cwd = agent = model = mode = ""
    last = None                                # last conversation entry (user/assistant/system)
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            t = d.get("type")
            if d.get("cwd"):
                cwd = d["cwd"]
            if t == "agent-setting":
                agent = d.get("agentSetting") or ""
            elif t == "permission-mode":
                mode = d.get("permissionMode") or ""
            if t == "assistant":
                m = (d.get("message") or {}).get("model") or ""
                if m and m != "<synthetic>":
                    model = m
            if t in CONV:
                last = d
    mid = "no"
    if last is not None:
        t = last.get("type")
        kinds = {p.get("type") for p in parts(last.get("message"))}
        if t == "user" and "tool_result" in kinds:
            mid = "yes"
        elif t == "assistant" and ("tool_use" in kinds or (kinds and kinds <= {"thinking", "redacted_thinking"})):
            mid = "yes"
        elif t == "system" and last.get("subtype") in END_SUBTYPES_MIDTASK:
            mid = "yes"
    return cwd, agent, model, mode, mid

rows = []
for proj in sorted(os.listdir(root)):
    pdir = os.path.join(root, proj)
    if proj == "memory" or not os.path.isdir(pdir):
        continue
    for name in os.listdir(pdir):
        p = os.path.join(pdir, name)
        if not name.endswith(".jsonl") or not os.path.isfile(p):
            continue                           # <id>/subagents/ and memory/ are directories: skipped
        mt = os.stat(p).st_mtime
        if lo <= mt <= hi:
            rows.append((mt, name[:-6], p))

for mt, sid, p in sorted(rows):
    cwd, agent, model, mode, mid = scan(p)
    stamp = time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(mt))
    print("\t".join([sid, cwd, agent, model, mode, mid, stamp, p]))
PY
