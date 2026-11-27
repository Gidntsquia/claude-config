# argv[1]: JSON overrides; stdin: the output of `run-agent.sh --parse`. Prints one line per key that differs
# from the base object plus the overrides; nothing when they are equal.
import json, sys
base = {"agent":"worker","agent_ok":True,"prompt":".","dir":"","dir_state":"","flags":"","confirm":0,"at":"","at_text":"",
        "at_shown":"","until":"","until_shown":"","reset":"","reset_shown":"","corrections":[],"unsure":[],"dry":0,
        "dir_typed":"","command":"claude --agent worker \".\" --name \"worker: repo (sonnet)\"","run":"S worker ."}
try:
    got = json.load(sys.stdin)
except Exception as e:
    print("not JSON: " + str(e)); sys.exit(0)
want = dict(base); over = json.loads(sys.argv[1]); want.update(over)
if "model_default" not in over:   # the default model named only when none was typed (the test's own agents folder)
    want["model_default"] = "" if "--model" in want.get("flags", "") or not want.get("agent") else \
        {"worker": "sonnet", "planner": "fable", "evaluator": "opus"}.get(want["agent"], "sonnet")
if got != want:
    for k in sorted(set(got) | set(want)):
        if got.get(k) != want.get(k):
            print("%s: got %r want %r" % (k, got.get(k), want.get(k)))
