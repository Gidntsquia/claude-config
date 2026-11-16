#!/usr/bin/env python3
"""mcpclient.py <server.py> [tool json-args]...: start the server over stdio, print its tool names (tools/list), then
call each given tool. Example: mcpclient.py server.py jobs '{}' next '{"agent":"worker","prompt":"."}'"""
import json, subprocess, sys

p = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
n = 0


def rpc(method, params=None, notify=False):
    global n
    msg = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        msg["params"] = params
    if not notify:
        n += 1; msg["id"] = n
    p.stdin.write(json.dumps(msg) + "\n"); p.stdin.flush()
    if notify:
        return None
    while True:
        d = json.loads(p.stdout.readline())
        if d.get("id") == n:
            return d


r = rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "mcpclient", "version": "1"}})
print("server:", r["result"]["serverInfo"]["name"])
rpc("notifications/initialized", notify=True)
tools = rpc("tools/list", {})["result"]["tools"]
print("tools:", len(tools), " ".join(t["name"] for t in tools))
if "--schema" in sys.argv:
    print(json.dumps(tools, indent=1))
a = [x for x in sys.argv[2:] if x != "--schema"]
for name, args in zip(a[::2], a[1::2]):
    r = rpc("tools/call", {"name": name, "arguments": json.loads(args)})
    print(f"--- {name} {args}")
    for c in r.get("result", {}).get("content", []):
        print(c.get("text", c))
p.stdin.close(); p.wait(timeout=10)
