#!/usr/bin/env bash
# usage: find-sessions.sh <stop-time> [projects-dir] [--since <time>]
# Lists the Claude Code sessions a WSL/Windows stop killed: a top-level <projects-dir>/<project>/<id>.jsonl counts if
#  (a) its mtime is within [stop - 60 min, stop + 5 s] ("recent"), or
#  (b) Claude's process file <sessions-dir>/<pid>.json for it survived (deleted on a clean exit), last written in
#      [since, stop + 5 s] ("open at stop"). since = --since (the stopped boot's start), else stop - 24 h.
# projects-dir defaults to $RS_PROJECTS or ~/.claude/projects. sessions-dir is $RS_SESSIONS, else ~/.claude/sessions
# unless a projects dir was given (tests): then (b) is off. Ignores <id>/subagents/ and memory/.
# Prints one TSV line per candidate, oldest mtime first:
#   session-id  cwd  agent  model  permission-mode  mid-task(yes/no)  mtime-ET  transcript-path  why(recent|open at stop)
# cwd is the directory the session was started in (its project folder), not where it last cd'ed: resuming
# elsewhere makes Claude continue in a new session under another project folder.
# Times are anything `date -d` reads, e.g. '2026-10-15 04:56:11' (local = ET) or 'Thu 2026-10-15 04:56:11 EDT'.
set -euo pipefail
pos=() since=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) pos+=("$1"); shift ;;
  esac
done
[ ${#pos[@]} -ge 1 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
stop=$(date -d "${pos[0]}" +%s) || { echo "find-sessions: cannot read stop time: ${pos[0]}" >&2; exit 2; }
if [ -n "$since" ]; then
  since=$(date -d "$since" +%s) || { echo "find-sessions: cannot read --since time" >&2; exit 2; }
else
  since=$((stop - 86400))
fi
sess="${RS_SESSIONS:-}"
if [ -z "$sess" ] && [ ${#pos[@]} -lt 2 ] && [ -z "${RS_PROJECTS:-}" ]; then sess="$HOME/.claude/sessions"; fi
dir="${pos[1]:-${RS_PROJECTS:-$HOME/.claude/projects}}"
[ -d "$dir" ] || { echo "find-sessions: no such projects dir: $dir" >&2; exit 2; }
dir=$(realpath -- "$dir")   # absolute, so no path ever starts with '-'

python3 -I - "$stop" "$dir" "$since" "$sess" <<'PY'
import glob, json, os, sys, time
stop, root, since, sessdir = int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4]
lo, hi = stop - 3600, stop + 5
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
            if d.get("cwd") and not cwd:
                cwd = d["cwd"]                 # first cwd = where the session was started
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

rows = {}
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
            rows[name[:-6]] = (mt, p, "recent")

def alive(d):
    try:
        with open("/proc/%d/stat" % int(d.get("pid")), encoding="utf-8") as fh:
            return fh.read().rsplit(")", 1)[1].split()[19] == str(d.get("procStart"))
    except (OSError, ValueError, TypeError, IndexError):
        return False

if sessdir and os.path.isdir(sessdir):
    for f in glob.glob(os.path.join(sessdir, "*.json")):
        try:
            fmt = os.stat(f).st_mtime
            d = json.load(open(f, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        sid = d.get("sessionId") if isinstance(d, dict) else None
        if not sid or sid in rows or not (since <= fmt <= hi) or d.get("kind", "interactive") != "interactive" or alive(d):
            continue
        hits = glob.glob(os.path.join(root, "*", sid + ".jsonl"))
        if hits:
            rows[sid] = (os.stat(hits[0]).st_mtime, hits[0], "open at stop")

for sid, (mt, p, why) in sorted(rows.items(), key=lambda kv: kv[1][0]):
    cwd, agent, model, mode, mid = scan(p)
    stamp = time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(mt))
    print("\t".join([sid, cwd, agent, model, mode, mid, stamp, p, why]))
PY
