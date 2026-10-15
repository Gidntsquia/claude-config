#!/usr/bin/env bash
# usage: plan.sh --candidates FILE --out DIR [--stop TIME] [--boot TIME] [--prev TIME] [--projects DIR]
#                [--fix "cbf1bb64 -> 1:2"] [--fix "drop c7a00432"] ...
# Reads find-sessions.sh output and the live tmux panes / claude processes, and proposes where each session goes.
# Writes DIR/plan.tsv (one row per pane: target role how key id cwd agent model mode midtask pet),
#        DIR/skipped.tsv (id cwd reason), DIR/ops.tsv (what apply.sh runs), DIR/before.txt (tmux list-panes -a),
# and prints the plan as markdown: the table, then skipped sessions, idle panes reused, new sessions/windows.
# Never changes tmux. RS_TMUX_L=<name> uses a private tmux server (tmux -L <name>), for tests. RS_SEED fixes the pets.
# Corrections (--fix, any number, applied in order):
#   drop <id-prefix>          leave that session out
#   <id-prefix> -> S:W        put it in tmux session S, window W (next free pane; a new window if W does not exist)
#   <id-prefix> -> S:W.P      put it in pane P of S:W (an idle shell there is reused; a busy pane is refused)
#   <id-prefix> -> S          put it in the first window of session S with room
set -euo pipefail
tm() { if [ -n "${RS_TMUX_L:-}" ]; then tmux -L "$RS_TMUX_L" "$@"; else tmux "$@"; fi; }

cand="" out="" stop="" boot="" prev="" projects="${RS_PROJECTS:-$HOME/.claude/projects}"
fixes=()
while [ $# -gt 0 ]; do
  case "$1" in
    --candidates) cand="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --stop) stop="$2"; shift 2 ;;
    --boot) boot="$2"; shift 2 ;;
    --prev) prev="$2"; shift 2 ;;
    --projects) projects="$2"; shift 2 ;;
    --fix) fixes+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "plan.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$cand" ] && [ -f "$cand" ] || { echo "plan.sh: --candidates FILE is required" >&2; exit 2; }
[ -n "$out" ] || { echo "plan.sh: --out DIR is required" >&2; exit 2; }
mkdir -p "$out"
epoch() { [ -n "$1" ] && date -d "$1" +%s 2>/dev/null || echo 0; }

# Live state. A tmux server that is not running is not an error: every target session is then new.
panes="$out/panes.tsv"; : > "$panes"
if tm list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_pid}' > "$out/before.txt" 2>/dev/null; then
  tm list-panes -a -F "#{session_name}	#{window_index}	#{pane_index}	#{pane_id}	#{pane_current_command}	#{pane_pid}" |
  while IFS=$'\t' read -r s w p id cmd pid; do
    kids=$(ps -o args= --ppid "$pid" 2>/dev/null | tr '\n' '\037' || true)
    self=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$w" "$p" "$id" "$cmd" "$pid" "$self" "$kids"
  done > "$panes"
else
  echo "(no tmux server running)" > "$out/before.txt"
fi
base=$(tm show -gv base-index 2>/dev/null || echo 1)
pgrep -af 'claude' > "$out/procs.txt" 2>/dev/null || true

printf '%s\n' "${fixes[@]+"${fixes[@]}"}" > "$out/fixes.txt"
python3 -I - "$cand" "$out" "$panes" "$out/procs.txt" "$out/fixes.txt" "$(epoch "$boot")" "$(epoch "$prev")" \
  "$(epoch "$stop")" "$projects" "${base:-1}" "${RS_SEED:-}" \
  "$([ -n "$stop" ] && date -d "@$(epoch "$stop")" '+%a %Y-%m-%d %H:%M:%S %Z' 2>/dev/null)" <<'PY'
import os, random, re, sys, time
cand, out, panes_f, procs_f, fixes_f = sys.argv[1:6]
boot, prev, stop = (int(x) for x in sys.argv[6:9])
projects, base, seed, stop_s = sys.argv[9], int(sys.argv[10]), sys.argv[11], sys.argv[12]
rng = random.Random(seed) if seed else random.Random()
SHELLS = {"bash", "zsh", "sh", "fish", "dash"}
PETS = ["squid", "dog", "cat"]
TARGETS = ["0", "1"]
WINDOW_PANES = 4                                     # 2x2: pane 1 pet, panes 2-4 claude

def et(t): return time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(t))

# ---- candidates and skips -------------------------------------------------------------------------------
rows = []
for line in open(cand, encoding="utf-8"):
    f = line.rstrip("\n").split("\t")
    if len(f) >= 8 and f[0]:
        rows.append(dict(id=f[0], cwd=f[1], agent=f[2], model=f[3], mode=f[4], mid=f[5], mtime=f[6], path=f[7]))
procs = [l.rstrip("\n") for l in open(procs_f, encoding="utf-8", errors="replace")]
def claude_args(l):
    parts = l.split(None, 1)
    if len(parts) < 2: return None
    argv = parts[1].split()
    return argv if argv and os.path.basename(argv[0]) == "claude" else None
running = [a for a in map(claude_args, procs) if a]

skipped, live = [], []
for r in rows:
    hit = next((a for a in running if any(x == r["id"] or x.endswith("=" + r["id"]) for x in a)), None)
    try: now_mt = os.stat(r["path"]).st_mtime
    except OSError: now_mt = 0
    if hit:
        skipped.append((r, "already running: " + " ".join(hit)))
    elif boot and now_mt > boot:
        skipped.append((r, "already running: transcript written at %s, after this boot started" % et(now_mt)))
    elif not os.path.isdir(r["cwd"] or "/nonexistent"):
        skipped.append((r, "cwd no longer exists: %s" % (r["cwd"] or "(none)")))
    else:
        live.append(r)

# Sessions that ended earlier in the stopped boot: newest top-level transcript per project, last written
# between that boot's start and the 60-minute window, with no surviving process file (find-sessions.sh adds those).
ended = []
if prev and stop and os.path.isdir(projects):
    cand_ids = {r["id"] for r in rows}
    for proj in sorted(os.listdir(projects)):
        pdir = os.path.join(projects, proj)
        if proj == "memory" or not os.path.isdir(pdir): continue
        best = None
        for n in os.listdir(pdir):
            p = os.path.join(pdir, n)
            if not n.endswith(".jsonl") or not os.path.isfile(p): continue
            mt = os.stat(p).st_mtime
            if prev <= mt < stop - 3600 and n[:-6] not in cand_ids and (best is None or mt > best[0]):
                best = (mt, n[:-6], p)
        if best:
            cwd = ""
            with open(best[2], encoding="utf-8", errors="replace") as fh:
                for l in fh:
                    m = re.search(r'"cwd":"((?:[^"\\]|\\.)*)"', l)
                    if m: cwd = m.group(1)
            ended.append((best[1], cwd, "ended earlier: last write %s, more than 60 min before the stop" % et(best[0])))

# ---- corrections ------------------------------------------------------------------------------------------
fixes = [l.strip() for l in open(fixes_f, encoding="utf-8") if l.strip()]
pins, errors = {}, []
def find(prefix):
    m = [r for r in live if r["id"].startswith(prefix)]
    if len(m) == 1: return m[0]
    errors.append("%s: %s" % (prefix, "no such session in the plan" if not m else "matches %d sessions" % len(m)))
for fx in fixes:
    m = re.fullmatch(r"(?:drop|remove|skip)\s+([0-9a-fA-F-]{4,})", fx, re.I)
    if m:
        r = find(m.group(1).lower())
        if r: live.remove(r); skipped.append((r, "dropped by user")); pins.pop(r["id"], None)
        continue
    m = re.fullmatch(r"([0-9a-fA-F-]{4,})\s*(?:->|=>|→|to)\s*([^\s:.]+)(?::(\d+)(?:\.(\d+))?)?", fx)
    if m:
        r = find(m.group(1).lower())
        if r: pins[r["id"]] = (m.group(2), m.group(3), m.group(4))
        continue
    errors.append("cannot read correction: %r (use 'drop <id>' or '<id> -> S:W[.P]')" % fx)

# ---- tmux model ---------------------------------------------------------------------------------------------
class Pane:
    def __init__(s, key, idx, cmd="", kids="", self_args="", new=False):
        s.key, s.idx, s.cmd, s.new = key, idx, cmd, new
        args = self_args + "\x1f" + kids
        s.pet = None
        if cmd == "terminal-pet" or "terminal-pet" in args:
            m = re.search(r"terminal-pet(?:\s+--pet\s+(\w+))?", args)
            s.pet = (m.group(1) if m and m.group(1) else "squid")
        s.idle = (not new) and cmd in SHELLS and not kids.strip("\x1f").strip()
        s.role, s.row, s.reuse = None, None, False
class Window:
    def __init__(s, sess, idx, exists): s.sess, s.idx, s.exists, s.panes, s.ops = sess, idx, exists, [], []
    def tgt(s): return "%s:%s" % (s.sess, s.idx)
sessions = {}                                       # name -> {window idx -> Window}, in order
for l in open(panes_f, encoding="utf-8"):
    f = l.rstrip("\n").split("\t")
    if len(f) < 8: continue
    s, w, p, pid_, cmd, ppid, selfa, kids = f[:8]
    W = sessions.setdefault(s, {}).setdefault(int(w), Window(s, int(w), True))
    W.panes.append(Pane(pid_, int(p), cmd, kids, selfa))
for ws in sessions.values():
    for W in ws.values(): W.panes.sort(key=lambda p: p.idx)

newkey = [0]
def new_pane(W):
    newkey[0] += 1
    p = Pane("new:%d" % newkey[0], (max([q.idx for q in W.panes]) + 1) if W.panes else base, new=True)
    W.panes.append(p); return p
new_sessions, new_windows, notes = [], [], []
def get_window(s, w=None):
    ws = sessions.get(s)
    if ws is None:
        ws = sessions[s] = {}; new_sessions.append(s)
    if not ws and w is not None and w != base:
        notes.append("%s:%d asked for, but tmux session %s is new, so its first window is %s:%d" % (s, w, s, s, base))
    if w is None or not ws: w = (max(ws) + 1) if ws else base   # a new session's first window is always base
    if w not in ws:
        W = ws[w] = Window(s, w, False)
        first = Pane("new:%d" % (newkey[0] + 1), base); newkey[0] += 1
        first.idle = True; first.cmd = "bash"; first.fresh = True
        W.panes.append(first)
        if s not in new_sessions: new_windows.append(W.tgt())
    return ws[w]

used_pets = {p.pet for ws in sessions.values() for W in ws.values() for p in W.panes if p.pet}
def pick_pet():
    pool = [k for k in PETS if k not in used_pets]
    if not pool: used_pets.clear(); pool = list(PETS)
    k = rng.choice(pool); used_pets.add(k); return k

prepared = set()
def prepare(W):
    """Give W a pet in its top-left pane (plan only)."""
    if W.tgt() in prepared: return
    prepared.add(W.tgt())
    top = min(p.idx for p in W.panes)
    pets = [p for p in W.panes if p.pet]
    p1 = next(p for p in W.panes if p.idx == top)
    if pets:
        pet = pets[0]
        if pet is not p1:
            W.ops.append(("swap", pet.key, p1.key)); pet.idx, p1.idx = p1.idx, pet.idx
        pet.role = "pet-existing"
    elif p1.idle:
        p1.role, p1.reuse = "pet", not getattr(p1, "fresh", False); p1.kind = pick_pet()
    else:
        p = new_pane(W); W.ops.append(("split", p.key))
        W.ops.append(("swap", p.key, p1.key)); p.idx, p1.idx = p1.idx, p.idx
        p.role = "pet"; p.kind = pick_pet()

def free_slot(W, force=False, pane=None):
    prepare(W)
    if pane is not None:
        p = next((q for q in W.panes if q.idx == pane), None)
        if p is not None:
            if p.role: errors.append("%s.%d already holds %s" % (W.tgt(), pane, p.role)); return None
            if not p.idle: errors.append("%s.%d is busy (%s), pick an idle pane or a window" % (W.tgt(), pane, p.cmd)); return None
            p.reuse = not getattr(p, "fresh", False); return p
    for p in W.panes:
        if p.idle and not p.role: p.reuse = not getattr(p, "fresh", False); return p
    if force or len(W.panes) < WINDOW_PANES:
        p = new_pane(W); W.ops.append(("split", p.key)); return p
    return None

def place(r, p):
    p.role, p.row = "claude", r

# every existing window of the target sessions gets its pet first (top-left pane)
for s in TARGETS:
    for wi in sorted(sessions.get(s, {})): prepare(sessions[s][wi])
def has_room(X):
    prepare(X); return any(p.idle and not p.role for p in X.panes) or len(X.panes) < WINDOW_PANES
# pinned first
for r in [x for x in live if x["id"] in pins]:
    s, w, pn = pins[r["id"]]
    if w: W = get_window(s, int(w))
    elif s not in sessions: W = get_window(s)
    else: W = next((sessions[s][k] for k in sorted(sessions[s]) if has_room(sessions[s][k])), None) or get_window(s)
    p = free_slot(W, force=True, pane=int(pn) if pn else None)
    if p: place(r, p)
    else: pins.pop(r["id"])
# then the rest, in mtime order: session 0's windows, session 1's windows, then new windows in the last session
rest = [x for x in live if x["id"] not in pins]
for r in rest:
    p = None
    for s in TARGETS:                      # session 0 first; a target session that does not exist yet is created
        if s not in sessions: get_window(s)
        for wi in sorted(sessions[s]):
            p = free_slot(sessions[s][wi])
            if p: break
        if p: break
    if p is None: p = free_slot(get_window(TARGETS[-1]))   # all full: new window in the last target session
    place(r, p)

# ---- output -------------------------------------------------------------------------------------------------
sorder = lambda s: (TARGETS.index(s) if s in TARGETS else len(TARGETS), s)
new_sessions.sort(key=sorder)
windows = [W for s in sorted(sessions, key=sorder) for W in sessions[s].values() if W.ops or any(p.role in ("pet", "claude") or p.new for p in W.panes)]
plan, ops = [], []
for s in new_sessions: ops.append(("new-session", s, str(min(sessions[s]))))
for W in windows:
    if not W.exists and W.sess not in new_sessions: ops.append(("new-window", W.sess, str(W.idx)))
    first = next((p for p in W.panes if getattr(p, "fresh", False)), None)
    if first: ops.append(("first-pane", W.tgt(), first.key))
    for op in W.ops: ops.append((op[0], W.tgt()) + op[1:])
    ops.append(("layout", W.tgt()))
    for p in sorted(W.panes, key=lambda p: p.idx):
        tgt = "%s.%d" % (W.tgt(), p.idx)
        how = "new pane" if p.new or getattr(p, "fresh", False) else ("idle shell reused" if p.reuse else "existing")
        if p.role == "pet":
            ops.append(("pet", W.tgt(), p.key, p.kind))
            plan.append([tgt, "pet", how, p.key, "", "", "", "", "", "", p.kind])
        elif p.role == "pet-existing":
            plan.append([tgt, "pet", "existing pet", p.key, "", "", "", "", "", "", p.pet])
        elif p.role == "claude":
            r = p.row
            ops.append(("resume", W.tgt(), p.key, r["cwd"], r["id"]))
            plan.append([tgt, "claude", how, p.key, r["id"], r["cwd"], r["agent"], r["model"], r["mode"], r["mid"], ""])
for s in new_sessions: ops.append(("wt", s))

def w(name, rows_):
    with open(os.path.join(out, name), "w", encoding="utf-8") as f:
        for r in rows_: f.write("\t".join(str(x) for x in r) + "\n")
w("plan.tsv", plan)
w("skipped.tsv", [(r["id"], r["cwd"], why) for r, why in skipped] + list(ended))
w("ops.tsv", ops)

def short(m): return m.replace("claude-", "") if m else ""
def tilde(c): return (c or "").replace(os.path.expanduser("~"), "~")
print("| tmux session:window.pane | session id | cwd | agent | model | mode | mid-task |")
print("|---|---|---|---|---|---|---|")
for t in plan:
    if t[1] == "pet":
        print("| %s | pet: %s (%s) | ~ | | | | |" % (t[0], t[10], t[2]))
    else:
        print("| %s | %s | %s | %s | %s | %s | %s |" % (t[0], t[4], t[5].replace(os.path.expanduser("~"), "~"),
              t[6] or "(none)", short(t[7]) or "?", t[8] or "?", t[9]))
if not plan: print("| (nothing to open) | | | | | | |")
print()
print("Skipped (not reopened):" if skipped or ended else "Skipped: none")
for r, why in skipped: print("- %s %s: %s" % (r["id"][:8], (r["cwd"] or "").replace(os.path.expanduser("~"), "~"), why))
for sid, cwd, why in ended: print("- %s %s: %s" % (sid[:8], cwd.replace(os.path.expanduser("~"), "~"), why))
reused = [t[0] for t in plan if t[2] == "idle shell reused"]
if reused: print("Idle shell panes reused (nothing running in them now): " + ", ".join(reused))
if new_sessions: print("New tmux sessions (each gets a new Windows Terminal window): " + ", ".join(new_sessions))
if new_windows: print("New tmux windows: " + ", ".join(new_windows))
noagent = [t[4][:8] for t in plan if t[1] == "claude" and not t[6]]
if noagent: print("No agent in the transcript (comes back without one): " + ", ".join(noagent))
for n in notes: print("Note: " + n)
for e in errors: print("CORRECTION NOT APPLIED: " + e)
sys.exit(3 if errors else 0)
PY
