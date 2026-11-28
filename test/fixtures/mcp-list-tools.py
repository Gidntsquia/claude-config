"""mcp-list-tools.py <server command...>: start an MCP stdio server, ask tools/list, print the names."""
import json
import subprocess
import sys
import threading

p = subprocess.Popen(sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
watchdog = threading.Timer(180, p.kill)
watchdog.start()


def send(**msg):
    p.stdin.write(json.dumps({"jsonrpc": "2.0", **msg}) + "\n")
    p.stdin.flush()


def reply(i):
    for line in p.stdout:
        d = json.loads(line)
        if d.get("id") == i:
            return d
    sys.exit("the server closed before answering")


send(id=1, method="initialize", params={"protocolVersion": "2025-06-18", "capabilities": {},
                                        "clientInfo": {"name": "test", "version": "1"}})
reply(1)
send(method="notifications/initialized")
send(id=2, method="tools/list", params={})
print(" ".join(sorted(t["name"] for t in reply(2)["result"]["tools"])))
p.stdin.close()
p.wait()
watchdog.cancel()
