"""The `guard` command: the user's side of usage-guard. See README.md.

  guard status                     today's count, unlock, live runs for the project of the current directory
  guard allow <2h|45m|until 9pm>   lift the parallel limit and the daily cap for this project until then
  guard revoke                     end the unlock now
  guard log [n]                    last n decisions (default 20)
  guard usage [today|week|YYYY-MM-DD] [project]   FE tokens and API-$ by main session / subagents / headless
"""
import json
import os
import re
import sys
from datetime import datetime, timedelta

import usage_guard as ug

MAX_ALLOW = 24 * 3600


def inside_claude():
    """True when this command was started by a Claude session rather than typed by the user"""
    if os.environ.get("CLAUDECODE") or os.environ.get("CLAUDE_CODE_ENTRYPOINT"):
        return True
    p = os.getppid()
    while p > 1:
        try:
            argv = open(f"/proc/{p}/cmdline", "rb").read().decode("utf-8", "replace").split("\0")
            if os.path.basename(argv[0]) == "claude" or (len(argv) > 1 and os.path.basename(argv[1]) == "claude"):
                return True
            p = int(open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return False


def sandbox():
    """a test HOME (not the account's real one): the session check does not apply, nothing real is unlocked"""
    try:
        import pwd
        return os.path.realpath(ug.HOME) != os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir)
    except (ImportError, KeyError):
        return False


def parse_until(words):
    """epoch for `2h`, `45m`, `1h30m`, `until 9pm`, `until 21:30`; None when unreadable"""
    text = " ".join(words).strip().lower()
    now = ug.now()
    m = re.fullmatch(r"(?:(\d+(?:\.\d+)?)\s*h)?\s*(?:(\d+)\s*m)?", text)
    if text and m and (m.group(1) or m.group(2)):
        return now + float(m.group(1) or 0) * 3600 + int(m.group(2) or 0) * 60
    m = re.fullmatch(r"(?:until\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", text)
    if m and (text.startswith("until") or m.group(3) or m.group(2)):
        h, mi, ap = int(m.group(1)), int(m.group(2) or 0), m.group(3)
        if ap:
            if not 1 <= h <= 12:
                return None
            h = h % 12 + (12 if ap == "pm" else 0)
        if h > 23 or mi > 59:
            return None
        t = ug.et()
        target = t.replace(hour=h, minute=mi, second=0, microsecond=0)
        if target <= t:
            target += timedelta(days=1)
        return target.timestamp()
    return None


def stamp(ts):
    return ug.et(ts).strftime("%-I:%M %p ET") + ("" if ug.et(ts).date() == ug.et().date() else ug.et(ts).strftime(" %a %b %-d"))


def cmd_allow(args, slug):
    exp = parse_until(args)
    if exp is None:
        print("usage: guard allow <2h|45m|until 9pm>", file=sys.stderr)
        return 2
    if not sandbox() and inside_claude():
        print("guard allow is for the user: run it in your own terminal, not from a Claude session", file=sys.stderr)
        return 1
    if exp - ug.now() > MAX_ALLOW:
        print("guard allow: at most 24 hours", file=sys.stderr)
        return 2
    with open(os.path.join(ug.pdir(slug), "allow"), "w") as f:
        f.write(f"{int(exp)}\n{stamp(exp)}\n")
    ug.log(slug, "UNLOCK", ug.read_count(slug), "guard allow " + " ".join(args), f"until {stamp(exp)}")
    print(f"{slug}: parallel limit and daily cap lifted until {stamp(exp)} (budget and turn flags still required)")
    return 0


def cmd_revoke(slug):
    if not sandbox() and inside_claude():
        print("guard revoke is for the user: run it in your own terminal", file=sys.stderr)
        return 1
    try:
        os.unlink(os.path.join(ug.pdir(slug), "allow"))
        ug.log(slug, "REVOKE", ug.read_count(slug), "guard revoke", "")
        print(f"{slug}: unlock ended")
    except OSError:
        print(f"{slug}: no unlock to end")
    return 0


def cmd_status(slug):
    exp = ug.allow_until(slug)
    live = os.path.join(ug.pdir(slug), "live")
    n_live = len([n for n in os.listdir(live) if ug.now() - os.path.getmtime(os.path.join(live, n)) < ug.STALE_LIVE])
    print(f"project   {slug}")
    print(f"today     {ug.read_count(slug)}/{ug.DAILY} launches ({ug.today()} ET)")
    print(f"unlock    {'until ' + stamp(exp) if exp else 'none'}")
    print(f"running   {ug.live_headless()} headless claude, {n_live} subagents")
    return 0


def cmd_log(args):
    n = int(args[0]) if args and args[0].isdigit() else 20
    try:
        lines = open(os.path.join(ug.G, "log")).read().splitlines()
    except OSError:
        lines = []
    print("\n".join(lines[-n:]) if lines else "no decisions logged yet")
    return 0


# ---- usage --------------------------------------------------------------------------------------------------------
def gather():
    """the weekly roundup's pricing module (rates are imported from it, never copied)"""
    for d in (os.path.join(ug.REPO, "skills", "weekly-roundup"), os.path.join(ug.HOME, ".claude", "skills", "weekly-roundup")):
        if os.path.exists(os.path.join(d, "gather_data.py")):
            sys.path.insert(0, d)
            import gather_data
            return gather_data
    raise SystemExit("guard usage: skills/weekly-roundup/gather_data.py not found")


def project_dirs(project):
    """Claude log directories for a project name, a path, or (None) the current directory"""
    base = os.path.join(ug.HOME, ".claude", "projects")
    if project and os.path.isdir(project) and os.sep in project:
        root = os.path.abspath(project)
    elif project:
        hits = [os.path.join(base, d) for d in sorted(os.listdir(base)) if d.endswith("-" + project)] if os.path.isdir(base) else []
        return hits, project
    else:
        root = ug.project_root(os.getcwd())
    d = os.path.join(base, re.sub(r"[^A-Za-z0-9]", "-", root))
    return ([d] if os.path.isdir(d) else []), os.path.basename(root)


def window(when):
    """(start, end, label) as naive local datetimes, the clock gather_data uses"""
    t = ug.et().replace(tzinfo=None)
    day = t.replace(hour=0, minute=0, second=0, microsecond=0)
    if when == "week":
        return day - timedelta(days=6), None, f"last 7 days to {t.strftime('%-I:%M %p ET')}"
    if when != "today":
        d = datetime.strptime(when, "%Y-%m-%d")
        return d, d + timedelta(days=1), when
    return day, None, f"today to {t.strftime('%-I:%M %p ET')}"


def scan(dirs, start, end, gd):
    """{kind: {tier: counts}}, {subagent label: {tier: counts}} with gather_data's dedup: one count per
    (message id, model), later records of the same message add only their extra output tokens"""
    kinds = {"main": {}, "subagents": {}, "headless": {}}
    agents, seen, seen_long = {}, {}, {}
    floor = start.timestamp() - 86400
    for d in dirs:
        for root, _, files in os.walk(d):
            for name in files:
                if not name.endswith(".jsonl"):
                    continue
                path = os.path.join(root, name)
                try:
                    if os.path.getmtime(path) < floor:
                        continue
                    lines = open(path, errors="ignore").read().splitlines()
                except OSError:
                    continue
                sub = os.path.basename(root) == "subagents"
                label = None
                if sub:
                    try:
                        meta = json.load(open(path[:-6] + ".meta.json"))
                    except (OSError, ValueError):
                        meta = {}
                    label = f"{meta.get('description') or name[:-6]} [{meta.get('agentType') or '?'}]"
                headless = False
                for line in lines:
                    if '"usage"' not in line:
                        if not headless and '"entrypoint":"sdk-cli"' in line:
                            headless = True
                        continue
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    if rec.get("entrypoint") == "sdk-cli":
                        headless = True
                    msg = rec.get("message") or {}
                    usage = msg.get("usage") if isinstance(msg, dict) else None
                    if not usage:
                        continue
                    ts = rec.get("timestamp")
                    if ts:
                        try:
                            t = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().replace(tzinfo=None)
                        except ValueError:
                            t = None
                        if t and (t < start or (end and t >= end)):
                            continue
                    model = msg.get("model", "unknown")
                    msg_id = msg.get("id") or rec.get("uuid")
                    out_t = usage.get("output_tokens", 0)
                    cc = usage.get("cache_creation") or {}
                    deltas = {
                        "input": usage.get("input_tokens", 0), "output": out_t,
                        "cache_read": usage.get("cache_read_input_tokens", 0),
                        "cache_5m": cc.get("ephemeral_5m_input_tokens", usage.get("cache_creation_input_tokens", 0) if not cc else 0),
                        "cache_1h": cc.get("ephemeral_1h_input_tokens", 0),
                    }
                    key = (msg_id, model)
                    if msg_id and key in seen:
                        if out_t <= seen[key]:
                            continue
                        deltas = {"output": out_t - seen[key]}
                    if msg_id:
                        seen[key] = max(out_t, seen.get(key, 0))
                    tier = model
                    long_over = gd.PRICING.get(model, {}).get("long_over")
                    if long_over:
                        if "input" in deltas:
                            seen_long[key] = sum(deltas[k] for k in ("input", "cache_read", "cache_5m", "cache_1h")) > long_over
                        if seen_long.get(key):
                            tier = model + "@long"
                    kind = "subagents" if sub else ("headless" if headless else "main")
                    slots = [kinds[kind].setdefault(tier, dict.fromkeys(gd.TOKEN_KEYS, 0))]
                    if sub:
                        slots.append(agents.setdefault(label, {}).setdefault(tier, dict.fromkeys(gd.TOKEN_KEYS, 0)))
                    for slot in slots:
                        for k, v in deltas.items():
                            slot[k] += v
    return kinds, agents


def totals(by_tier, gd):
    cost = fe = 0.0
    for tier, c in by_tier.items():
        a, b = gd.price_row(tier, c["input"], c["output"], c["cache_read"], c["cache_5m"], c["cache_1h"])
        cost, fe = cost + a, fe + b
    return cost, fe


def fmt_fe(fe):
    return f"{fe / 1e6:.1f}M" if fe >= 1e5 else f"{fe / 1e3:.0f}K"


def usage_data(when, project):
    gd = gather()
    dirs, name = project_dirs(project)
    start, end, label = window(when)
    kinds, agents = scan(dirs, start, end, gd)
    return gd, dirs, name, label, kinds, agents


def cmd_usage(args):
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]
    when = args[0] if args and (args[0] in ("today", "week") or re.fullmatch(r"\d{4}-\d\d-\d\d", args[0])) else "today"
    rest = [a for a in args if a != when]
    gd, dirs, name, label, kinds, agents = usage_data(when, rest[0] if rest else None)
    if not dirs:
        print(f"guard usage: no Claude logs found for {name}", file=sys.stderr)
        return 1
    rows = {k: totals(v, gd) for k, v in kinds.items()}
    all_cost, all_fe = sum(c for c, _ in rows.values()), sum(f for _, f in rows.values())
    if as_json:
        print(json.dumps({"project": name, "window": label, "cost": all_cost, "fe": all_fe,
                          "kinds": {k: {"cost": c, "fe": f} for k, (c, f) in rows.items()}}))
        return 0
    print(f"{name}: {label}")
    print(f"{'':22}{'FE tokens':>10}{'API $':>10}  share")
    names = {"main": "main session", "subagents": "Agent subagents", "headless": "headless claude -p"}
    for k in ("main", "subagents", "headless"):
        c, f = rows[k]
        print(f"{names[k]:22}{fmt_fe(f):>10}{c:>10.2f}  {100 * f / all_fe if all_fe else 0:4.0f}%")
        for tier in sorted(kinds[k], key=lambda t: -totals({t: kinds[k][t]}, gd)[1]):
            c2, f2 = totals({tier: kinds[k][tier]}, gd)
            if f2 >= 1:
                print(f"  {gd.display_name(tier) + (' (long)' if '@' in tier else ''):20}{fmt_fe(f2):>10}{c2:>10.2f}")
    print(f"{'total':22}{fmt_fe(all_fe):>10}{all_cost:>10.2f}")
    top = sorted(((totals(v, gd), k) for k, v in agents.items()), reverse=True)[:5]
    if top:
        print("\ntop subagents")
        for (c, f), k in top:
            print(f"  {fmt_fe(f):>8}  ${c:<7.2f} {k[:90]}")
    return 0


def cmd_fe_refresh(args):
    """write <project>/<date>.fe for the status line (started in the background by statusline.sh)"""
    cwd = args[0] if args else os.getcwd()
    slug = ug.slug_of(cwd)
    gd, dirs, name, label, kinds, agents = usage_data("today", ug.project_root(cwd))
    fe = sum(totals(v, gd)[1] for v in kinds.values())
    path = os.path.join(ug.pdir(slug), f"{ug.today()}.fe")
    with open(path + ".tmp", "w") as f:
        f.write(f"{fe / 1e6:.1f}\n")
    os.replace(path + ".tmp", path)
    return 0


def main(argv):
    while argv and argv[0] in ("--now",):
        ug.NOW = float(argv[1])
        argv = argv[2:]
    sub = argv[0] if argv else "status"
    slug = ug.slug_of(os.getcwd())
    if sub == "allow":
        return cmd_allow(argv[1:], slug)
    if sub == "revoke":
        return cmd_revoke(slug)
    if sub == "status":
        return cmd_status(slug)
    if sub == "log":
        return cmd_log(argv[1:])
    if sub == "usage":
        return cmd_usage(argv[1:])
    if sub == "fe-refresh":
        return cmd_fe_refresh(argv[1:])
    print(__doc__.strip(), file=sys.stderr)
    return 0 if sub in ("-h", "--help", "help") else 2
