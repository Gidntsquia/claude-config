#!/usr/bin/env python3
# Watches ONE session transcript for the AskUserQuestion answer and fires evshow.sh fired <answer-time-ET>.
# argv: <transcript path> <mode first|next> <title> <state dir>     (the path is this session's own transcript,
# chosen once by evshow.sh at `arm first`; the watcher never looks at any other file)
import sys, os, time, json, subprocess, datetime, zoneinfo
path, mode, title, D = sys.argv[1:5]
ET = zoneinfo.ZoneInfo("America/New_York")
H = os.path.expanduser("~/.claude/local-tools")
os.environ["EVSHOW_STATE"] = D
def log(s):
    with open(os.path.join(D, "log"), "a") as f: f.write(s + "\n")
def et(ts):
    try:
        import re
        ts = re.sub(r"\.(\d{1,6})\d*", lambda m: "." + m.group(1).ljust(6, "0"), ts)   # at most 6 fraction digits
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(ET)
        return t.strftime("%H:%M:%S.%f")[:12]
    except Exception: return ts
if not os.path.exists(path): log(f"watcher: transcript {path} does not exist"); sys.exit(1)
log(f"watcher: following {os.path.basename(path)} for the {mode} answer")
pos = os.path.getsize(path); ask_ids = set(); buf = b""; idle_since = time.time()
while True:
    try: size = os.path.getsize(path)
    except OSError: time.sleep(0.2); continue
    if size <= pos:
        if time.time() - idle_since > 3600: log("watcher: idle 1 h, exiting"); sys.exit(0)
        time.sleep(0.05); continue
    idle_since = time.time()
    with open(path, "rb") as fh: fh.seek(pos); buf += fh.read(size - pos); pos = size
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        try: d = json.loads(line)
        except Exception: continue
        c = d.get("message", {}).get("content")
        if not isinstance(c, list): continue
        for b in c:
            if b.get("type") == "tool_use" and b.get("name") == "AskUserQuestion":
                ask_ids.add(b.get("id"))
                # The transcript gets this line together with the answer, so the capture while the question is open comes from
                # evshow.sh's gate loop; here we record when the question was emitted (= when it appeared in the terminal).
                q = et(d.get("timestamp", ""))
                with open(os.path.join(D, "question-ts"), "w") as f: f.write(q)
                try: shown = open(os.path.join(D, "last-shown")).read().strip()
                except OSError: shown = ""
                if shown:
                    dt = (datetime.datetime.strptime(q[:12], "%H:%M:%S.%f") - datetime.datetime.strptime(shown[:12], "%H:%M:%S.%f")).total_seconds()
                    log(f"question emitted {q} ET; previous item shown-at {shown}; shown -> question {dt:.2f} s")
                    with open(os.path.join(D, "history"), "a") as f: f.write(f"question emitted {q} ET (shown -> question {dt:.2f} s)\n")
                else:
                    log(f"question emitted {q} ET (readiness question)")
                    with open(os.path.join(D, "history"), "a") as f: f.write(f"question emitted {q} ET (readiness question)\n")
                if mode == "last": sys.exit(0)   # last item: only its question time was wanted
            elif b.get("type") == "tool_result" and b.get("tool_use_id") in ask_ids:
                cc = b.get("content")
                if isinstance(cc, list): cc = " ".join(x.get("text", "") for x in cc if isinstance(x, dict))
                cc = str(cc)
                if mode == "first" and '="Yes"' not in cc:
                    log(f"watcher: answer was not Yes ({cc[:80]!r}), waiting"); continue
                a = et(d.get("timestamp", ""))
                with open(os.path.join(D, "answer"), "w") as f: f.write(a)
                log(f"watcher: answer seen {a} (detected {datetime.datetime.now(ET).strftime('%H:%M:%S.%f')[:12]})")
                subprocess.call([os.path.join(H, "evshow.sh"), "fired", a])
                sys.exit(0)
