#!/usr/bin/env python3
"""show.py <stream.jsonl>: a short readable transcript of a `claude -p --output-format stream-json` run:
each Bash / Agent call, the first lines of its result, the worker's text, and the cost line."""
import json, sys

def text(c):
    if isinstance(c, str):
        return c
    return "\n".join(b.get("text", "") for b in c or [] if isinstance(b, dict))

names = {}
for line in open(sys.argv[1], errors="ignore"):
    try:
        r = json.loads(line)
    except ValueError:
        continue
    t = r.get("type")
    if t == "system" and r.get("subtype") == "init":
        print(f"[session {r.get('session_id')}  model {r.get('model')}]")
    elif t == "assistant" and not r.get("parent_tool_use_id"):
        for b in r["message"].get("content", []):
            if b.get("type") == "text" and b["text"].strip():
                print("worker: " + b["text"].strip()[:400].replace("\n", "\n        "))
            elif b.get("type") == "tool_use":
                i = b.get("input", {})
                names[b["id"]] = b["name"]
                if b["name"] == "Bash":
                    print("  $ " + i.get("command", "")[:300].replace("\n", "\n    "))
                elif b["name"] == "Agent":
                    print(f"  Agent[{i.get('subagent_type', '-')}, model={i.get('model', '-')}] {i.get('description', '')}")
                else:
                    print(f"  {b['name']} {str(i.get('file_path', ''))}")
    elif t == "user" and not r.get("parent_tool_use_id"):
        for b in r["message"].get("content", []) if isinstance(r["message"].get("content"), list) else []:
            if b.get("type") == "tool_result" and names.get(b.get("tool_use_id")) in ("Bash", "Agent"):
                out = text(b.get("content")).strip()
                mark = "  ✗ " if "blocked by usage-guard" in out else "  → "
                print(mark + "\n    ".join(out.split("\n")[:6])[:600])
    elif t == "result":
        print(f"[result: {r.get('subtype')}  turns {r.get('num_turns')}  cost ${r.get('total_cost_usd', 0):.2f}]")
