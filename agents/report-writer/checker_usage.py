#!/usr/bin/env python3
"""Sums the report-checker subagent's tokens and wall seconds from this session's transcript.

    python3 -I checker_usage.py <since ISO-8601 UTC, e.g. 2026-10-21T18:02:11Z> [--json]

Looks under ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/<session>/subagents/agent-*.jsonl for subagent transcripts
whose first event is at or after <since>, and prints "tokens=N seconds=N agents=N" (every assistant event's
input + cache creation + cache read + output tokens; wall = first to last event timestamp, summed over agents).
Prints tokens=0 seconds=0 agents=0 when no subagent ran. Stdlib only.
"""
import glob, json, os, sys
from datetime import datetime, timezone


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    since = ts(a[0])
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    tokens = seconds = agents = 0
    per = []
    for f in glob.glob(os.path.join(cfg, "projects", "*", "*", "subagents", "agent-*.jsonl")):
        if datetime.fromtimestamp(os.path.getmtime(f), timezone.utc) < since:
            continue
        first = last = None
        t = 0
        for line in open(f, encoding="utf-8", errors="replace"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            when = d.get("timestamp")
            if not when:
                continue
            w = ts(when)
            first = w if first is None else min(first, w)
            last = w if last is None else max(last, w)
            u = (d.get("message") or {}).get("usage") if d.get("type") == "assistant" else None
            if u:
                t += sum(int(u.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"))
        if first is None or first < since:
            continue
        agents += 1
        tokens += t
        s = int(round((last - first).total_seconds()))
        seconds += s
        per.append({"file": f, "tokens": t, "seconds": s})
    if "--json" in a:
        print(json.dumps({"tokens": tokens, "seconds": seconds, "agents": agents, "per_agent": per}))
    else:
        print(f"tokens={tokens} seconds={seconds} agents={agents}")


if __name__ == "__main__":
    main()
