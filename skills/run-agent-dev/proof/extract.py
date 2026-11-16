#!/usr/bin/env python3
"""extract.py <out dir>: copy the 7 run-agent Bash commands the auto-mode classifier denied on 11-14/11-15 out of the
planner-building transcripts, character for character, into cmd-1.txt … cmd-7.txt (+ index.csv). `--check` re-reads the
transcripts and diffs each cmd-N.txt against its transcript command (prints `cmd-N: same|DIFFERENT`, exit 1 on a diff)."""
import csv, glob, json, os, sys, time

PROJ = os.path.expanduser("~/.claude/projects/-home-jaxon-files-planner-building")
SESSIONS = ["0632490f", "58a7a82d", "4709ebc0", "946e010a", "0d9c9c9c", "d049c927"]  # plans/research/run-agent-blocks.md
DENY = "Permission for this action was denied by the Claude Code auto mode classifier"
SINCE = "2026-11-15T03:00"  # 11-14 10:00 PM ET


def et(ts):
    os.environ["TZ"] = "America/New_York"; time.tzset()
    import datetime
    t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    return time.strftime("%m-%d %I:%M %p", time.localtime(t))


def blocked():
    rows = []
    for sid in SESSIONS:
        for path in sorted(glob.glob(os.path.join(PROJ, sid + "*.jsonl"))):
            uses, agent = {}, ""
            for line in open(path, encoding="utf-8"):
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                agent = d.get("agentSetting") or agent
                msg = d.get("message") or {}
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for c in content:
                    if not isinstance(c, dict):
                        continue
                    if c.get("type") == "tool_use" and c.get("name") == "Bash":
                        uses[c["id"]] = (c.get("input") or {}).get("command", "")
                    elif c.get("type") == "tool_result" and c.get("tool_use_id") in uses:
                        text = c.get("content")
                        if isinstance(text, list):
                            text = " ".join(x.get("text", "") for x in text if isinstance(x, dict))
                        text = text or ""
                        cmd = uses[c["tool_use_id"]]
                        if ("run-agent" in cmd and text.startswith(DENY) and d.get("toolDenialKind")
                                and d.get("timestamp", "") >= SINCE):
                            rows.append({"ts": d.get("timestamp", ""), "session": os.path.basename(path)[:8],
                                         "transcript": path, "tool_use_id": c["tool_use_id"], "agent": agent,
                                         "command": cmd, "reason": text[:300]})
    rows.sort(key=lambda r: r["ts"])
    return rows


def main():
    check = "--check" in sys.argv
    out = [a for a in sys.argv[1:] if a != "--check"][0]
    rows = blocked()
    if check:
        bad = 0
        for i, r in enumerate(rows, 1):
            same = open(os.path.join(out, f"cmd-{i}.txt"), encoding="utf-8", newline="").read() == r["command"]
            bad += not same
            print(f"cmd-{i}: {'same' if same else 'DIFFERENT'} ({len(r['command'])} chars, {r['session']} {et(r['ts'])} ET)")
        sys.exit(1 if bad or len(rows) != 7 else 0)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "index.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["n", "time_et", "session", "agent", "chars", "tool_use_id", "transcript", "reason"])
        for i, r in enumerate(rows, 1):
            open(os.path.join(out, f"cmd-{i}.txt"), "w", encoding="utf-8", newline="").write(r["command"])
            w.writerow([i, et(r["ts"]), r["session"], r["agent"], len(r["command"]), r["tool_use_id"], r["transcript"], r["reason"]])
            print(i, et(r["ts"]), r["session"], r["agent"], len(r["command"]), r["reason"][:120])


main()
