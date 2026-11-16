#!/usr/bin/env python3
"""audit.py <out audit.txt> <worker transcript.jsonl>...   (plan R6)
Reads every Bash command of the worker's transcript(s) and writes to <out> each call the plan's R4 says may run only
inside `tmux -L run-agent-dev-test` that was made outside one; with none, <out> reads `none`.

R4-named calls: a session start (`claude` run as a command), a server call (mcp/server.py, proof/mcpclient.py), a
schedule / handoff / cancel / relaunch / next-with-run through run-agent.sh, `run-agent`, launch.py or jobs.py,
a replay (proof/replay.py, proof/matrix runs) and test.sh.
Not R4-named (allowed in the worker's own pane): run-agent.sh `--jobs`, `--next`, `--parse`, `--step`, which only
print; `claude mcp list|get|add|remove` and `claude --version`, which start no session.
Inside = the command line that makes the call is itself a `tmux -L run-agent-dev-test …` command, or is in a script
file that the transcript shows was only ever started by one (the file's path appears in such a command).
Bodies of here-documents that only write a file (`cat > f <<EOF`, `python3 - <<EOF` editing source) are text, not
calls, and are skipped; so are grep/sed/cat/ls/wc/head/tail lines that read a file whose name matches."""
import json, os, re, sys, time

out, paths = sys.argv[1], sys.argv[2:]
PRIV = re.compile(r"tmux\s+-L\s+run-agent-dev-test\b")
READ = re.compile(r"^\s*(grep|rg|sed|cat|ls|wc|head|tail|diff|md5sum|sha256sum|stat|chmod|cp|mv|rm|mkdir|echo|printf|git|cd|test|\[|find|touch|ln|file|jq|awk|sort|cut|tr|date|ps|pgrep|true|:)\b")
CALLS = [
    ("session start", re.compile(r"(?:^|[;&|(]\s*|\benv\s+(?:\S+\s+)*|\S+=\S*\s+)claude\s+(?!mcp\s+(?:list|get|add|remove)\b|--version\b|-v\b)")),
    ("server call", re.compile(r"mcpclient\.py|(?:uv run[^|;&]*|python3\s+)\S*mcp/server\.py|^\s*\S*mcp/server\.py")),
    ("replay", re.compile(r"python3\s+(?!-m\b)\S*proof/replay\.py|(?:^|\s)(?:bash|sh)\s+\S*(?:fixruns|matrixruns|chain)\.sh")),
    ("test.sh", re.compile(r"^\s*(?:\S+=\S*\s+)*(?:(?:bash|sh)\s+)?\S*test\.sh\b")),
    ("schedule/handoff/cancel", re.compile(r"(?:run-agent\.sh|bin/run-agent(?:-dev)?|\brun-agent(?:-dev)?)\s[^|;&\n]*(?:--at\b|--handoff\b|--cancel\b|--relaunch\b|\bcancel\s+\d|\bin \d+ min)")),
    ("schedule/handoff/cancel", re.compile(r"launch\.py\s+(?:relaunch|next\b[^|;&\n]*--run)|jobs\.py\s+(?:cancel|add|fire)")),
]
os.environ["TZ"] = "America/New_York"; time.tzset()


def et(ts):
    import datetime
    try:
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
        return time.strftime("%m-%d %I:%M:%S %p ET", time.localtime(t))
    except Exception:
        return ts


def strip_heredocs(cmd):
    """drop here-document bodies; return the remaining lines"""
    lines, outl, end = cmd.split("\n"), [], None
    for l in lines:
        if end is not None:
            if l.strip() == end:
                end = None
            continue
        m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", l)
        outl.append(l)
        if m:
            end = m.group(1)
    return outl


cmds = []  # (session, ts, command)
for p in paths:
    for line in open(p, encoding="utf-8"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        for c in (d.get("message") or {}).get("content") or []:
            if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "Bash":
                cmds.append((os.path.basename(p)[:8], d.get("timestamp", ""), c["input"].get("command", "")))

# script files started from a private-server command count as inside
inside_files = set()
for _, _, cmd in cmds:
    for l in cmd.split("\n"):
        if PRIV.search(l):
            inside_files.update(os.path.basename(x) for x in re.findall(r"[\w./$\"{}-]+\.(?:sh|py)\b", l))

found, n_private, n_cmds = [], 0, len(cmds)
for sid, ts, cmd in cmds:
    for l in strip_heredocs(cmd):
        if PRIV.search(l):
            n_private += 1
            continue
        # split on shell separators so `cd x && claude …` is judged piece by piece
        for piece in re.split(r"&&|\|\||;", l):
            if READ.match(piece) and not re.match(r"^\s*(cd|echo|printf|true|:)\b", piece):
                continue
            for kind, rx in CALLS:
                if rx.search(piece):
                    found.append(f"{et(ts)}  session {sid}  {kind}: {piece.strip()[:300]}")
                    break
with open(out, "w") as f:
    if not found:
        f.write("none\n")
    else:
        f.write("\n".join(found) + "\n")
print(f"{len(paths)} transcript(s), {n_cmds} Bash commands, {n_private} private-server command lines, {len(found)} outside calls -> {out}")
