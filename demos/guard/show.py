#!/usr/bin/env python3
"""show.py <stream.jsonl>: a short readable transcript of a `claude -p --output-format stream-json` run:
each Bash / Agent call, the first lines of its result, the worker's text, and the cost line. Lines marked `◦` are
what the guard's hooks added to the worker's context: the count at session start (from the stream) and the count
after each allowed launch (from the session's own log under ~/.claude/projects, where Claude Code records it)."""
import glob, json, os, sys

def text(c):
    if isinstance(c, str):
        return c
    return "\n".join(b.get("text", "") for b in c or [] if isinstance(b, dict))

names, start, notes = {}, [], {}


def context(out):
    try:
        return (json.loads(out).get("hookSpecificOutput") or {}).get("additionalContext")
    except (ValueError, AttributeError):
        return None


def hook_notes(session):
    """tool_use_id -> the lines hooks added for that call, read from the session log"""
    found = {}
    for path in glob.glob(os.path.expanduser(f"~/.claude/projects/*/{session}.jsonl")):
        for line in open(path, errors="ignore"):
            if '"hook_additional_context"' not in line:
                continue
            try:
                a = json.loads(line).get("attachment") or {}
            except ValueError:
                continue
            if a.get("type") == "hook_additional_context" and a.get("toolUseID"):
                c = a.get("content")
                found.setdefault(a["toolUseID"], []).extend(c if isinstance(c, list) else [str(c)])
    return found


for line in open(sys.argv[1], errors="ignore"):
    try:
        r = json.loads(line)
    except ValueError:
        continue
    t = r.get("type")
    if t == "system" and r.get("subtype") == "hook_response" and r.get("hook_event") == "SessionStart":
        c = context(r.get("stdout") or r.get("output") or "")
        if c:
            start.append(c)
    elif t == "system" and r.get("subtype") == "init":
        print(f"[session {r.get('session_id')}  model {r.get('model')}]")
        notes = hook_notes(r.get("session_id"))
        for c in start:
            print("  ◦ at session start: " + c)
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
                for c in dict.fromkeys(notes.get(b.get("tool_use_id"), [])):
                    print("  ◦ " + c)
    elif t == "result":
        print(f"[result: {r.get('subtype')}  turns {r.get('num_turns')}  cost ${r.get('total_cost_usd', 0):.2f}]")
