#!/usr/bin/env python3
"""
Deterministic data-gathering for the weekly-roundup skill.

Replaces the manual git-log / jsonl-scanning / token-math tool calls with one
script invocation. Outputs JSON: repos worked on (with commits, remote,
screenshot candidates) and per-project token/cost breakdowns. Judgment calls
(key learnings, HTML writing, picking the deep-dive picture) stay with Claude.

Pooling: several machines on one account each add their data to the week's one artifact.
Each run collects this machine's raw per-session token counts and commits, merges them with
the other devices' data from --pool-in (the published page), reports on the union, and writes
the merged pool to --pool-out for embed_pool.py to put back into the page.

Usage:
  gather_data.py --files-dir ~/files --claude-projects ~/.claude/projects \
      --window-start 2026-09-04 --window-end 2026-09-11 \
      --token-window-start "2026-09-06T22:00:00" \
      [--token-window-end "2026-09-13T22:00:00"] \
      [--cap-pct 90] --plan-cost 100 \
      [--device jaxon@desktop] --person Jaxon [--pool-in this-week.html] [--pool-out pool.json] \
      [--include-ai-sandbox] [--include-project yugioh-deck-optimizer]

Who did what: --person names the owner of this machine's usage. Spellings pool fuzzily into the
pool's / KNOWN_PEOPLE's names ("jet Lee", "Jett" -> Jet; "jax", "Jaxson" -> Jaxon). Each person gets a color scheme (first
seen: warm, second: cool, ...), used for their projects' accents, pie slices and Misc.
"""
import argparse
import difflib
import getpass
import json
import re
import socket
import subprocess
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

# Per-million-token USD list prices (source: platform.claude.com/docs/en/about-claude/pricing,
# checked 2026-10-11). Cache reads default to 0.1x input; override with "cache_read_mult".
# Cache writes are 1.25x (5m) / 2x (1h) input. Update as pricing changes.
# "long_over": requests whose prompt (input + cache reads + cache writes) is over this many
# tokens are tallied under "<model>@long" and priced by that entry instead.
PRICING = {
    "claude-sonnet-5-5":      {"in": 2.00,  "out": 10.00, "display": "Sonnet 5.5"},
    "claude-sonnet-5":        {"in": 2.00,  "out": 10.00, "display": "Sonnet 5"},
    "claude-opus-5-5":        {"in": 4.00,  "out": 20.00, "cache_read_mult": 0.05, "display": "Opus 5.5"},
    "claude-opus-5":          {"in": 5.00,  "out": 25.00, "display": "Opus 5"},
    "claude-haiku-5-5":       {"in": 0.10,  "out": 0.50, "long_over": 100_000, "display": "Haiku 5.5"},
    "claude-haiku-5-5@long":  {"in": 0.50,  "out": 2.50, "display": "Haiku 5.5"},
    "claude-haiku-4-5-20251001": {"in": 1.00, "out": 5.00, "display": "Haiku 4.5"},
    "claude-fable-5-1":       {"in": 10.00, "out": 50.00, "cache_read_mult": 0.025, "display": "Fable 5.1"},
    "claude-fable-5":         {"in": 10.00, "out": 50.00, "display": "Fable 5"},
    # Local models: free, so they add nothing to cost, FE tokens, or the weekly cap.
    "qwen3.5-9b-claude":      {"in": 0.0, "out": 0.0, "display": "Qwen 3.5 9B (local)"},
    "qwen3.5-9b-claude-q4":   {"in": 0.0, "out": 0.0, "display": "Qwen 3.5 9B Q4 (local)"},
}
FABLE_INPUT_RATE = 10.00  # $/M tokens, the FE-token normalization base

# Model family -> (display name, color per effort level, light -> dark). Same family =
# same hue; deeper shade = higher effort. Effort None (Haiku etc.) uses the "medium" shade.
EFFORT_ORDER = ["low", "medium", "high", "xhigh", "max"]
FAMILY_COLORS = {
    "Sonnet": ["#9cc3f5", "#6ba4ee", "#3b82e0", "#2160b8", "#0f3f87"],  # blue
    "Fable":  ["#d0b3f3", "#b088e8", "#8f5fd9", "#6d3cb8", "#4a2088"],  # purple
    "Opus":   ["#f8c58a", "#f2a45a", "#e5822a", "#bd6112", "#8a4408"],  # orange
    "Haiku":  ["#a8dfb4", "#7bc98c", "#4fb066", "#348a4b", "#1f6533"],  # green
    "Local":  ["#9bd9d4", "#66c2bb", "#37a79f", "#238079", "#14605a"],  # teal (local models)
}
FAMILY_ORDER = ["Sonnet", "Fable", "Opus", "Haiku", "Local"]

# Who did the usage. Every machine's run names a person (--person); each person gets a color
# scheme, assigned in order of first appearance in the pool (first person warm, second cool,
# ...). "accents" color that person's projects; which accent a project gets is kept stable
# across weeks by project_colors.json (see assign_colors). "misc" is that person's Misc gray.
# warm and cool each hold 12 accents from opposite halves of the color wheel (warm: hues
# 305-360 and 0-57, i.e. magentas, pinks, reds, oranges, ambers, yellows, browns; cool: hues
# 100-282, i.e. greens, teals, cyans, blues, indigos, violets), in three lightness tiers so no
# two accents in a list have hue within 15 degrees and lightness within 10%.
PERSON_PALETTES = [
    {"name": "warm",  "main": "#e5484d", "misc": "#b9a295",
     "accents": ["#e5484d", "#f0690f", "#dd2c85", "#e59a06", "#b931ae", "#a33114",
                 "#d7cd09", "#f7806e", "#a71b3e", "#f8b859", "#ea86cc", "#844e1f",
                 "#6d2655", "#f5ee84", "#dd9dae", "#76651e", "#c964b6", "#c9bb64",
                 "#761e72", "#e495e1"]},
    {"name": "cool",  "main": "#2f80ed", "misc": "#94a3b8",
     "accents": ["#2f80ed", "#27a566", "#8f51d6", "#13a2ae", "#4e4ed0", "#2b822b",
                 "#5fc6f2", "#13725a", "#7b319b", "#183795", "#81cc5c", "#ac97ed",
                 "#9dddab", "#4cfac9", "#39266d", "#7e9bfc", "#cd8dec", "#26ed3d",
                 "#26536d", "#3e6d26"]},
    # Fallbacks for a third / fourth person.
    {"name": "berry", "main": "#a23bb6", "misc": "#ab9bb0",
     "accents": ["#a23bb6", "#e05297", "#6c3fcf", "#c74b7d", "#8d5be0", "#d670b5"]},
    {"name": "earth", "main": "#8b6b2e", "misc": "#a8a394",
     "accents": ["#8b6b2e", "#5f7a3b", "#a0522d", "#6b8e7b", "#b08968", "#4e6b4c"]},
]
# With only one person in the week's pool there is nothing to tell apart, so projects use the
# whole color wheel instead of one person's scheme (the split schemes above apply from two
# people on). Neutral grays are left out: Misc and Unused use them.
SOLO_PALETTE = {"name": "full", "main": "#2f80ed", "misc": "#9aa3ad",
                "accents": ["#e5484d", "#2f80ed", "#e8710a", "#7c5cff", "#2e9e6b", "#c2185b",
                            "#2bb4c9", "#b8860b", "#a13e85", "#43a047", "#ff8a65", "#6d4c41"]}
HERE = Path(__file__).resolve().parent
COLORS_FILE = HERE / "project_colors.json"  # "<person>|<project key>" -> accent, kept across weeks
DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
UNKNOWN_PERSON = "Unknown"  # contributions made before --person existed
KNOWN_PEOPLE = ["Jaxon", "Jet"]  # the account's people; any fuzzy spelling of these pools into them
FUZZY_MIN = 0.75  # difflib ratio at or above this counts as the same person


def _words(name: str):
    return [w for w in (re.sub(r"[^a-z0-9]", "", w.lower()) for w in (name or "").split()) if w]


def person_score(name: str, known: str) -> float:
    """How well any word of `name` matches `known` (0..1): exact 1.0, prefix either way (2+
    chars) 0.95, else the best difflib ratio. "jet lee"/"Jett"/"JET" -> Jet; "jax"/"Jaxson" ->
    Jaxon."""
    k = _words(known)[0] if _words(known) else ""
    best = 0.0
    for w in _words(name):
        if w == k:
            return 1.0
        if len(w) >= 2 and (k.startswith(w) or w.startswith(k)):
            best = max(best, 0.95)
        best = max(best, difflib.SequenceMatcher(None, w, k).ratio())
    return best


def canonical_person(name: str, known) -> str:
    """The pool's spelling for this name: the closest known person (pool people, then
    KNOWN_PEOPLE) at or above FUZZY_MIN wins, so "jet Lee", "jett", "JAXON." and "jaxson" pool
    into "Jet" / "Jaxon"; otherwise the first word, capitalized."""
    words = _words(name)
    if not words:
        return UNKNOWN_PERSON
    cands = list(dict.fromkeys(list(known) + KNOWN_PEOPLE))
    best = max(cands, key=lambda k: person_score(name, k), default=None)
    if best is not None and person_score(name, best) >= FUZZY_MIN:
        return best
    word = re.sub(r"[^\w'-]", "", name.strip().split()[0])
    return word[:1].upper() + word[1:]


def family_for(model: str) -> str:
    for fam in ("sonnet", "fable", "opus", "haiku"):
        if fam in model:
            return fam.capitalize()
    return "Local"


# Repos that lived elsewhere in earlier weeks: project name -> old paths (relative to
# --files-dir) whose Claude project dirs also count toward it.
MOVED_FROM = {
    "token-experiment": ["ai-sandbox/token-experiment"],
    "deadlock-optimal-build-finder": ["deadlock-build-optimizer"],
    "nisar-archaeology": ["NISAR-projects"],
    # Test runs of the agents: demo apps built to try the helper, and replays of worker and
    # evaluator runs. A path with a "/" folds just that subfolder (and its own subfolders).
    "helper-agent-building": ["first-project", "tip-calculator"],
    "worker-building": ["replay/video-editor-replay", "replay/claude-config-replay"],
    "evaluator-building": ["replay/deadlock-r14-replay", "replay/worker-building-evalreplay"],
}

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}


def base_model(model: str) -> str:
    """The model id without a pricing-tier suffix like "@long"."""
    return model.split("@", 1)[0]


def display_name(model: str) -> str:
    if model in PRICING:
        return PRICING[model]["display"]
    return model


def price_row(model: str, input_t, output_t, cache_read_t, cache_5m_t, cache_1h_t):
    p = PRICING.get(model)
    if p is None:
        # Unknown model: fall back to sonnet-5 pricing so totals stay sane, flagged in output.
        p = PRICING["claude-sonnet-5"]
    in_rate, out_rate = p["in"], p["out"]
    cost = (
        input_t * in_rate
        + output_t * out_rate
        + cache_read_t * (in_rate * p.get("cache_read_mult", 0.1))
        + cache_5m_t * (in_rate * 1.25)
        + cache_1h_t * (in_rate * 2.0)
    ) / 1_000_000
    fe_tokens = (cost / (FABLE_INPUT_RATE / 1_000_000)) if FABLE_INPUT_RATE else 0
    return cost, fe_tokens


def git(repo: Path, *args):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    return r.stdout.strip()


def find_repos(files_dir: Path, include_ai_sandbox: bool, claude_projects: Path = None):
    """Yield project directories under files_dir: git repos, plus (if
    claude_projects is given) non-git directories that have a matching Claude
    project directory with any session activity at all — so ungitted/early-
    stage projects aren't silently folded into Misc."""
    for child in sorted(files_dir.iterdir()):
        if not child.is_dir():
            continue
        if child.name == "ai-sandbox" and not include_ai_sandbox:
            continue
        if (child / ".git").exists():
            yield child
            continue
        if claude_projects is not None:
            expected_slug = slug_for(child)
            for d in claude_projects.iterdir():
                if d.is_dir() and (d.name == expected_slug or d.name.startswith(expected_slug + "-")):
                    if any(d.rglob("*.jsonl")):
                        yield child
                        break


def normalize_remote(url: str) -> str:
    if not url:
        return ""
    url = url.strip()
    if url.startswith("git@"):
        # git@github.com:user/repo.git -> https://github.com/user/repo
        m = re.match(r"git@([^:]+):(.+?)(\.git)?$", url)
        if m:
            url = f"https://{m.group(1)}/{m.group(2)}"
    elif url.endswith(".git"):
        url = url[:-4]
    return url


def find_screenshot(repo: Path, since_iso: str):
    candidates = []
    for sub in ("docs", "screenshots", "screenshot", "assets", "."):
        d = repo / sub
        if not d.exists():
            continue
        for f in d.glob("*"):
            if f.suffix.lower() in IMAGE_EXTS and f.is_file():
                candidates.append(f)
    if not candidates:
        return None
    # Prefer most recently modified.
    candidates.sort(key=lambda f: f.stat().st_mtime, reverse=True)
    return str(candidates[0])


def repo_commits(repo: Path, start: str, end: str):
    """[{hash, subject}] for commits in the window; hashes let pooled devices dedupe shared repos."""
    log = git(repo, "log", f"--since={start}", f"--until={end} 23:59:59", "--format=%H %s")
    return [{"hash": l[:40], "subject": l[41:]} for l in log.splitlines() if l.strip()]


def slug_for(path: Path) -> str:
    # Claude Code maps every non-alphanumeric character (/, \, :, _, ., space) to "-":
    # /home/x/repo -> -home-x-repo, C:\Users\x\repo -> C--Users-x-repo
    return re.sub(r"[^A-Za-z0-9-]", "-", str(path).rstrip("/\\"))


def _prompt_text(msg):
    c = msg.get("content")
    if isinstance(c, list):
        c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    return c.strip() if isinstance(c, str) else ""




TOKEN_KEYS = ("input", "output", "cache_read", "cache_5m", "cache_1h")


def _new_counts():
    return {k: 0 for k in TOKEN_KEYS}


def scan_project_dir(dir_path: Path, window_start: datetime, window_end: datetime = None, sessions=None):
    """Fill sessions[session_id] = {start, prompt, usage: {model: {effort: counts}},
    days: {YYYY-MM-DD: {model: counts}}} for one Claude-project jsonl directory, deduped by
    message id. One session per jsonl file; subagent usage counts toward its parent session;
    prompt = first real user message in the window; effort is "" when the record has none.
    `days` splits the same usage by local calendar day of each record's timestamp."""
    if sessions is None:
        sessions = {}
    seen = {}  # msg_id -> output_tokens already counted, to add only deltas
    seen_long = {}  # msg_id -> True if the request's prompt was over its model's "long_over"
    for jsonl in dir_path.rglob("*.jsonl"):
        # Subagent transcripts (<session>/subagents/agent-*.jsonl) count toward their parent session.
        sid = jsonl.parent.parent.name if jsonl.parent.name == "subagents" else jsonl.stem
        sess = sessions.setdefault(sid, {"start": None, "prompt": "", "usage": {}, "days": {}})
        try:
            lines = jsonl.read_text(errors="ignore").splitlines()
        except OSError:
            continue
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = rec.get("message") or {}
            usage = msg.get("usage")
            ts = rec.get("timestamp")
            t = None
            if ts:
                try:
                    t = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().replace(tzinfo=None)
                except ValueError:
                    t = None
                if t and (t < window_start or (window_end and t >= window_end)):
                    continue
            if t and (sess["start"] is None or t.isoformat() < sess["start"]):
                sess["start"] = t.isoformat(timespec="minutes")
            if (not sess["prompt"] and rec.get("type") == "user" and not rec.get("isMeta")
                    and msg.get("role") == "user"):
                text = _prompt_text(msg)
                if text and not text.startswith("<"):
                    sess["prompt"] = " ".join(text.split())[:200]
            if not usage:
                continue
            model = msg.get("model", "unknown")
            effort = rec.get("effort") or ""
            msg_id = msg.get("id") or rec.get("uuid")
            out_t = usage.get("output_tokens", 0)
            cc = usage.get("cache_creation") or {}
            deltas = {
                "input": usage.get("input_tokens", 0),
                "output": out_t,
                "cache_read": usage.get("cache_read_input_tokens", 0),
                "cache_5m": cc.get("ephemeral_5m_input_tokens", usage.get("cache_creation_input_tokens", 0) if not cc else 0),
                "cache_1h": cc.get("ephemeral_1h_input_tokens", 0),
            }
            key = (msg_id, model)
            if msg_id and key in seen:
                prev_out = seen[key]
                if out_t <= prev_out:
                    continue
                deltas = {"output": out_t - prev_out}
            if msg_id:
                seen[key] = max(out_t, seen.get(key, 0))
            tier = model
            long_over = PRICING.get(model, {}).get("long_over")
            if long_over:
                if "input" in deltas:  # first record of this request: it carries the full prompt
                    prompt_t = sum(deltas[k] for k in ("input", "cache_read", "cache_5m", "cache_1h"))
                    seen_long[key] = prompt_t > long_over
                if seen_long.get(key):
                    tier = model + "@long"
            slot = sess["usage"].setdefault(tier, {}).setdefault(effort, _new_counts())
            day = sess["days"].setdefault(t.date().isoformat() if t else "", {}).setdefault(tier, _new_counts())
            for k, v in deltas.items():
                slot[k] += v
                day[k] += v
    return sessions


def collect(args, device, person):
    """This machine's contribution to the week: per-project sessions with raw token counts,
    commits, remotes, plus Misc sessions, all attributed to `person`. Pricing is applied later,
    so contributions from several devices merge losslessly."""
    files_dir = Path(args.files_dir).expanduser()
    claude_projects = Path(args.claude_projects).expanduser()
    token_window_start = datetime.fromisoformat(args.token_window_start)
    token_window_end = datetime.fromisoformat(args.token_window_end) if args.token_window_end else None

    projects = []
    matched_slugs = set()
    moved_old = {old for olds in MOVED_FROM.values() for old in olds}
    moved_owner = {slug_for(files_dir / old): new for new, olds in MOVED_FROM.items() for old in olds}

    def claimed_elsewhere(name, repo_name):
        """True when a MOVED_FROM entry of another repo owns this Claude project dir."""
        return any((name == m or name.startswith(m + "-")) and owner != repo_name
                   for m, owner in moved_owner.items())
    repos = list(find_repos(files_dir, args.include_ai_sandbox, claude_projects)) if files_dir.is_dir() else []
    for repo in repos:
        if repo.name in moved_old:
            continue  # folded into its new repo via MOVED_FROM, not a separate project
        is_git = (repo / ".git").exists()
        commits = repo_commits(repo, args.window_start, args.window_end) if is_git else []
        if is_git and not commits and repo.name not in args.include_project:
            continue
        remote = normalize_remote(git(repo, "remote", "get-url", "origin")) if is_git else ""

        expected_slugs = [slug_for(repo)] + [slug_for(files_dir / old) for old in MOVED_FROM.get(repo.name, [])]
        sessions = {}
        for d in claude_projects.iterdir():
            if (d.is_dir() and any(d.name == e or d.name.startswith(e + "-") for e in expected_slugs)
                    and not claimed_elsewhere(d.name, repo.name)):
                matched_slugs.add(d.name)
                scan_project_dir(d, token_window_start, token_window_end, sessions)
        if not is_git and not any(s["usage"] for s in sessions.values()):
            continue  # nothing left once MOVED_FROM folded its subfolders elsewhere
        projects.append({
            "name": repo.name,
            "path": str(repo),
            "remote_url": remote,
            "screenshot": find_screenshot(repo, args.window_start),
            "commits": commits,
            "sessions": {sid: s for sid, s in sessions.items() if s["usage"]},
        })

    # Misc: every other claude-project dir active in the token window, not matched above.
    misc = {}
    for d in claude_projects.iterdir():
        if d.is_dir() and d.name not in matched_slugs:
            scan_project_dir(d, token_window_start, token_window_end, misc)
    misc = {sid: {"start": s["start"], "usage": s["usage"], "days": s["days"]} for sid, s in misc.items() if s["usage"]}

    return {
        "device": device,
        "person": person,
        "collected_at": datetime.now().isoformat(timespec="minutes"),
        "projects": projects,
        "misc_sessions": misc,
    }


def host_of(device):
    """Hostname part of a device label ('user@host' -> 'host'; a bare label is its own hostname)."""
    return device.rsplit("@", 1)[-1]


def entry_host(entry):
    """Hostname of a stored pool entry; older entries without the field get it from `device`."""
    return entry.get("hostname") or host_of(entry["device"])


def entry_sids(entry):
    sids = set(entry.get("misc_sessions", {}))
    for p in entry.get("projects", []):
        sids |= set(p.get("sessions", {}))
    return sids


def public_contribution(c):
    """A contribution as stored in the published page: drops first prompts, local paths and
    screenshot paths (the page may be shared publicly; other devices can't use them anyway)."""
    return {
        "device": c["device"],
        "hostname": host_of(c["device"]),
        "person": c.get("person", UNKNOWN_PERSON),
        "collected_at": c["collected_at"],
        "projects": [
            {
                "name": p["name"],
                "remote_url": p["remote_url"],
                "commits": p["commits"],
                "sessions": {sid: {"start": s["start"], "usage": s["usage"], "days": s["days"]}
                             for sid, s in p["sessions"].items()},
            }
            for p in c["projects"]
        ],
        "misc_sessions": c["misc_sessions"],
    }


def merge_projects(contributions):
    """Merge projects across devices: same remote URL, else same repo name, is one project.
    Sessions merge by id, commits by hash. Local-only fields (path, screenshot, prompts)
    come from whichever device has them."""
    merged = []
    for c in contributions:
        for p in c["projects"]:
            hit = next((m for m in merged
                        if (p["remote_url"] and m["remote_url"].lower() == p["remote_url"].lower())
                        or m["name"] == p["name"]), None)
            if hit is None:
                hit = {"name": p["name"], "path": p.get("path", ""), "remote_url": p["remote_url"],
                       "screenshot": p.get("screenshot"), "commits": [], "sessions": {}, "devices": []}
                merged.append(hit)
            hit["remote_url"] = hit["remote_url"] or p["remote_url"]
            hit["path"] = hit["path"] or p.get("path", "")
            hit["screenshot"] = hit["screenshot"] or p.get("screenshot")
            hit["devices"].append(c["device"])
            hashes = {x["hash"] for x in hit["commits"]}
            hit["commits"] += [x for x in p["commits"] if x["hash"] not in hashes]
            for sid, s in p["sessions"].items():
                hit["sessions"][sid] = {"prompt": "", **s, "device": c["device"],  # this machine (last) wins
                                        "person": c.get("person", UNKNOWN_PERSON)}
    return merged


def counts_by(sessions, key):
    """Sum session usage into {key(model, effort): counts}."""
    out = {}
    for s in sessions:
        for model, efforts in s["usage"].items():
            for effort, t in efforts.items():
                slot = out.setdefault(key(model, effort), _new_counts())
                for k in TOKEN_KEYS:
                    slot[k] += t[k]
    return out


def priced(t, model):
    cost, fe = price_row(model, t["input"], t["output"], t["cache_read"], t["cache_5m"], t["cache_1h"])
    return cost, fe, sum(t[k] for k in TOKEN_KEYS)


def people_order(contributions, stored=()):
    """Canonical people in palette order: the pool's stored order first, then new ones as they
    appear. Each person keeps the same palette for the whole week."""
    order = [p for p in stored if p]
    for c in contributions:
        p = c.get("person", UNKNOWN_PERSON)
        if p not in order:
            order.append(p)
    return order


def palette_for(person, order):
    if len(order) == 1:
        return SOLO_PALETTE
    return PERSON_PALETTES[order.index(person) % len(PERSON_PALETTES)]


def by_person(sessions, order, implied_cap_fe, color_of):
    """[{person, fe_tokens, cost, sessions, weekly_pct, pct, color}] for a group of sessions,
    sorted by fe desc. `color_of(person)` picks the swatch."""
    tot = {}
    for sess in sessions:
        slot = tot.setdefault(sess["person"], [0.0, 0.0, 0])
        for model, t in counts_by([sess], lambda m, e: m).items():
            cost, fe, _r = priced(t, model)
            slot[0] += fe
            slot[1] += cost
        slot[2] += 1
    group_fe = sum(v[0] for v in tot.values())
    rows = [
        {"person": p, "fe_tokens": round(fe, 2), "cost": round(cost, 4), "sessions": n,
         "weekly_pct": round(fe / implied_cap_fe * 100, 2) if implied_cap_fe else 0,
         "pct": round(fe / group_fe * 100, 2) if group_fe else 0,
         "color": color_of(p)}
        for p, (fe, cost, n) in tot.items() if fe > 0
    ]
    rows.sort(key=lambda r: (-r["fe_tokens"], order.index(r["person"])))
    return rows


def project_key(proj):
    """Stable identity of a project across weeks and machines: its GitHub remote, else its folder name."""
    return proj["remote_url"] or proj["name"]


def assign_colors(projects, order, colormap):
    """{(project name, person): accent} for every project x person this week (a project with no
    usage gets its lead, order[0]). The accent comes from `colormap` ("<person>|<project key>",
    or "solo|<project key>" when the pool has one person) when it is there and still in that
    person's palette; otherwise it is the first accent of the person's palette that none of
    their projects uses this week, then the accent least used in the map, and it is written to
    `colormap`. `projects` is in usage order, so bigger new projects pick first."""
    solo = len(order) == 1

    def prefix(who):
        return "solo|" if solo else f"{who}|"

    pairs = [(proj, who) for proj in projects for who in ([r["person"] for r in proj["people"]] or [order[0]])]
    colors, used, pending = {}, {}, []
    for proj, who in pairs:
        c = colormap.get(prefix(who) + project_key(proj))
        if c in palette_for(who, order)["accents"]:
            colors[(proj["name"], who)] = c
            used.setdefault(who, set()).add(c)
        else:
            pending.append((proj, who))
    for proj, who in pending:
        acc = palette_for(who, order)["accents"]
        mine = used.setdefault(who, set())
        free = [a for a in acc if a not in mine]
        if free:
            c = free[0]
        else:
            n = {a: 0 for a in acc}
            for k, v in colormap.items():
                if k.startswith(prefix(who)) and v in n:
                    n[v] += 1
            c = min(acc, key=lambda a: n[a])  # ties: palette order, so it cycles
        colors[(proj["name"], who)] = c
        mine.add(c)
        colormap[prefix(who) + project_key(proj)] = c
    return colors


def week_days(token_window_start):
    """The 8 local calendar dates of the week starting at this Sunday 22:00: the opening Sunday
    (22:00-24:00 only), Monday..Saturday, the closing Sunday (00:00-22:00)."""
    ws = datetime.fromisoformat(token_window_start).date()
    return [ws + timedelta(days=i) for i in range(8)]


def session_day_fe(sess, ws, fallback):
    """{day index 0..7: FE tokens} for one session. Index = local calendar day minus the opening
    Sunday: 0 is the opening Sunday's 22:00-midnight sliver, 7 the closing Sunday. Sessions stored
    before per-day data existed count on their start day, else on `fallback` (YYYY-MM-DD)."""
    days = sess.get("days")
    if not days:
        tot = {}
        for model, efforts in sess["usage"].items():
            slot = tot.setdefault(model, _new_counts())
            for t in efforts.values():
                for k in TOKEN_KEYS:
                    slot[k] += t[k]
        days = {(sess.get("start") or "")[:10]: tot}
    out = {}
    for d, models in days.items():
        try:
            idx = (date.fromisoformat(d) - ws).days
        except ValueError:
            idx = (date.fromisoformat(fallback) - ws).days
        idx = min(max(idx, 0), 7)
        for model, t in models.items():
            _c, fe, _r = priced(t, model)
            out[idx] = out.get(idx, 0.0) + fe
    return out


def daily_usage(projects, misc_sessions, pie_slices, implied_cap_fe, token_window_start):
    """The `days` output: 8 entries (opening Sunday, Mon..Sat, closing Sunday), each with one segment per project x person
    (and Misc per person) that used tokens that day, in weekly-cap % (same basis as the pie),
    colored like that pie slice, largest first (pie order on ties)."""
    dates = week_days(token_window_start)
    ws = dates[0]
    pie_at = {(sl["project"], sl["person"]): (i, sl["color"]) for i, sl in enumerate(pie_slices)}
    groups = [(proj["name"], list(proj["sessions"].values())) for proj in projects] + [("Misc", list(misc_sessions.values()))]
    starts = {}  # device -> earliest session day, the fallback for old entries with no start
    for _n, sessions in groups:
        for sess in sessions:
            st = (sess.get("start") or "")[:10]
            if st and (sess["device"] not in starts or st < starts[sess["device"]]):
                starts[sess["device"]] = st
    fe = {}  # (project, person) -> [fe per day]
    for name, sessions in groups:
        for sess in sessions:
            row = fe.setdefault((name, sess["person"]), [0.0] * 8)
            for idx, v in session_day_fe(sess, ws, starts.get(sess["device"], ws.isoformat())).items():
                row[idx] += v
    pct = lambda v: round(v / implied_cap_fe * 100, 2) if implied_cap_fe else 0
    days = []
    for i, d in enumerate(dates):
        segs = []
        for (name, who), row in fe.items():
            if (name, who) in pie_at and pct(row[i]) > 0:
                segs.append({"project": name, "person": who, "color": pie_at[(name, who)][1], "pct": pct(row[i])})
        segs.sort(key=lambda sg: (-sg["pct"], pie_at[(sg["project"], sg["person"])][0]))
        days.append({"date": d.isoformat(), "label": DAY_LABELS[i % 7], "segments": segs,
                     "total_pct": pct(sum(row[i] for row in fe.values()))})
    return days


def report(contributions, cap_pct, features_map, args, stored_people=(), colormap=None):
    projects = merge_projects(contributions)
    misc_sessions = {}
    for c in contributions:
        misc_sessions.update({sid: {**m, "device": c["device"], "person": c.get("person", UNKNOWN_PERSON)}
                              for sid, m in c["misc_sessions"].items()})
    order = people_order(contributions, stored_people)
    all_sessions = [s for p in projects for s in p["sessions"].values()] + list(misc_sessions.values())

    # Per-device totals for the page's "Data sources" drawer; each session counts once, toward
    # the device that reported it.
    dev_tot = {c["device"]: [0.0, 0.0, 0] for c in contributions}  # fe, cost, sessions
    for sess in all_sessions:
        for model, t in counts_by([sess], lambda m, e: m).items():
            cost, fe, _r = priced(t, model)
            dev_tot[sess["device"]][0] += fe
            dev_tot[sess["device"]][1] += cost
        dev_tot[sess["device"]][2] += 1

    eff_totals = counts_by(
        [s for p in projects for s in p["sessions"].values()] + list(misc_sessions.values()),
        lambda m, e: (m, e or None))

    for proj in projects:
        model_totals = counts_by(proj["sessions"].values(), lambda m, e: m)
        rows = {}  # base model -> [fe, cost, raw]; pricing tiers of one model share a row
        fe_total = cost_total = 0.0
        for model, t in model_totals.items():
            if model in PRICING and PRICING[model]["in"] == 0 and PRICING[model]["out"] == 0:
                continue  # free local model: no usage to show
            cost, fe, raw = priced(t, model)
            fe_total += fe
            cost_total += cost
            r = rows.setdefault(base_model(model), [0.0, 0.0, 0])
            r[0] += fe
            r[1] += cost
            r[2] += raw
        token_rows = [
            {"model": model, "model_display": display_name(model), "raw_tokens": raw,
             "fe_tokens": round(fe, 2), "cost": round(cost, 4)}
            for model, (fe, cost, raw) in rows.items()
        ]
        token_rows.sort(key=lambda r: r["fe_tokens"], reverse=True)
        proj["token_rows"] = token_rows
        proj["fe_total"] = round(fe_total, 2)
        proj["cost_total"] = round(cost_total, 4)

    misc_fe = misc_cost = 0.0
    by_model = {}  # model -> [fe, cost, raw]
    for model, t in counts_by(misc_sessions.values(), lambda m, e: m).items():
        cost, fe, raw = priced(t, model)
        misc_fe += fe
        misc_cost += cost
        m = by_model.setdefault(base_model(model), [0.0, 0.0, 0])
        m[0] += fe
        m[1] += cost
        m[2] += raw

    # Per-model usage across tracked projects + Misc, weighted by FE tokens
    # (cost-normalized), as a share of total used FE tokens (sums to 100%, no Unused).
    for proj in projects:
        for r in proj["token_rows"]:
            m = by_model.setdefault(r["model"], [0.0, 0.0, 0])
            m[0] += r["fe_tokens"]
            m[1] += r["cost"]
            m[2] += r["raw_tokens"]
    used_fe = sum(v[0] for v in by_model.values())
    model_breakdown = sorted(
        (
            {
                "model": model,
                "model_display": display_name(model),
                "raw_tokens": raw,
                "fe_tokens": round(fe, 2),
                "cost": round(cost, 4),
                "usage_pct": round(fe / used_fe * 100, 2) if used_fe else 0,
            }
            for model, (fe, cost, raw) in by_model.items()
            if fe > 0  # drops zero-token pseudo-models like "<synthetic>"
        ),
        key=lambda r: r["fe_tokens"],
        reverse=True,
    )

    # Per (family, effort) breakdown for the "Usage by model" pie. Versions of one
    # family (e.g. Fable 5 / 5.1) merge, since they share a color.
    fe_groups = {}
    for (model, effort), t in eff_totals.items():
        cost, fe, _raw = priced(t, model)
        if fe <= 0:
            continue
        g = fe_groups.setdefault((family_for(model), effort), [0.0, 0.0, set()])
        g[0] += fe
        g[1] += cost
        g[2].add(display_name(model))
    eff_used = sum(g[0] for g in fe_groups.values())

    def _sort_key(item):
        (fam, eff), _ = item
        return (FAMILY_ORDER.index(fam), EFFORT_ORDER.index(eff) if eff in EFFORT_ORDER else 1)

    model_effort_breakdown = []
    for (fam, eff), (fe, cost, names) in sorted(fe_groups.items(), key=_sort_key):
        idx = EFFORT_ORDER.index(eff) if eff in EFFORT_ORDER else 1
        model_effort_breakdown.append({
            "family": fam,
            "effort": eff or "default",
            "label": f"{fam} · {eff or 'default'}",
            "models": sorted(names),
            "color": FAMILY_COLORS[fam][idx],
            "fe_tokens": round(fe, 2),
            "cost": round(cost, 4),
            "usage_pct": round(fe / eff_used * 100, 2) if eff_used else 0,
        })
    unpriced = sorted({m for (m, _e) in eff_totals if m not in PRICING and m != "<synthetic>"})

    combined_fe = sum(p["fe_total"] for p in projects) + misc_fe
    combined_cost = sum(p["cost_total"] for p in projects) + misc_cost
    p = cap_pct
    implied_cap_fe = combined_fe / (p / 100) if p else combined_fe

    for proj in projects:
        proj["weekly_pct"] = round((proj["fe_total"] / implied_cap_fe) * 100, 2) if implied_cap_fe else 0
    misc_weekly_pct = round((misc_fe / implied_cap_fe) * 100, 2) if implied_cap_fe else 0
    unused_pct = round(100 - p, 2)

    # Who did what: per-person split of every project and of Misc, project accent colors from
    # the dominant person's palette, and ready-made slices for the projects pie (one per
    # project x person, so each person's share is visible in their own colors).
    projects.sort(key=lambda pr: pr["weekly_pct"], reverse=True)
    for proj in projects:
        proj["people"] = by_person(proj["sessions"].values(), order, implied_cap_fe, lambda who: None)
    colors = assign_colors(projects, order, colormap if colormap is not None else {})
    pie_slices = []  # filled below, grouped by person (most usage first)
    for proj in projects:
        for row in proj["people"]:
            row["color"] = colors[(proj["name"], row["person"])]
        lead = proj["people"][0]["person"] if proj["people"] else order[0]
        proj["accent"] = colors[(proj["name"], lead)]
        proj["lead_person"] = lead
        for row in proj["people"]:
            pie_slices.append({"project": proj["name"], "person": row["person"], "fe": row["fe_tokens"],
                               "label": f"{proj['name']} · {row['person']}" if len(order) > 1 else proj["name"],
                               "pct": row["weekly_pct"], "color": row["color"]})
    misc_people = by_person(misc_sessions.values(), order, implied_cap_fe,
                            lambda who: palette_for(who, order)["misc"])
    for row in misc_people:
        pie_slices.append({"project": "Misc", "person": row["person"], "fe": row["fe_tokens"],
                           "label": f"Misc · {row['person']}" if len(order) > 1 else "Misc",
                           "pct": row["weekly_pct"], "color": row["color"]})
    people_rows = by_person(all_sessions, order, implied_cap_fe, lambda who: palette_for(who, order)["main"])
    seen_people = {r["person"] for r in people_rows}
    # Group the projects pie by person: the person with the most usage first, then the next;
    # within a person, their projects by usage desc, then their Misc slice last.
    rank = {r["person"]: i for i, r in enumerate(people_rows)}
    pie_slices.sort(key=lambda sl: (rank.get(sl["person"], len(rank)), sl["project"] == "Misc", -sl.pop("fe")))
    for who in order:
        if who not in seen_people:
            people_rows.append({"person": who, "fe_tokens": 0, "cost": 0, "sessions": 0, "weekly_pct": 0,
                                "pct": 0, "color": palette_for(who, order)["main"]})
    for row in people_rows:
        pal = palette_for(row["person"], order)
        row["palette"] = pal["name"]
        row["accents"] = pal["accents"]
        row["devices"] = [c["device"] for c in contributions if c.get("person", UNKNOWN_PERSON) == row["person"]]

    days = daily_usage(projects, misc_sessions, pie_slices, implied_cap_fe, args.token_window_start)

    def session_fe(sess):
        out = {}
        for model, t in counts_by([sess], lambda m, e: m).items():
            _c, fe, _r = priced(t, model)
            if fe > 0:
                out[model] = fe
        return out

    warnings = []
    for proj in projects:
        sessions = proj["sessions"]
        fe_by_sid = {sid: session_fe(sess) for sid, sess in sessions.items()}
        fe_by_sid = {sid: m for sid, m in fe_by_sid.items() if m}
        proj["sessions"] = sorted(
            (
                {
                    "id": sid,
                    "start": sessions[sid]["start"],
                    "prompt": sessions[sid].get("prompt", ""),
                    "device": sessions[sid]["device"],
                    "person": sessions[sid]["person"],
                    "fe_tokens": round(sum(m.values()), 2),
                    "weekly_pct": round(sum(m.values()) / implied_cap_fe * 100, 2) if implied_cap_fe else 0,
                }
                for sid, m in fe_by_sid.items()
            ),
            key=lambda r: r["start"] or "",
        )
        proj["commits"] = [x["subject"] for x in proj["commits"]]
        wanted = features_map.get(proj["name"])
        if not wanted:
            continue
        assigned = {}  # sid -> feature
        for feature, ids in wanted.items():
            for ref in ids:
                hits = [sid for sid in fe_by_sid if sid.startswith(ref)]
                if not hits:
                    warnings.append(f"warning: {proj['name']} / {feature}: no session matches '{ref}'")
                for sid in hits:
                    assigned.setdefault(sid, feature)
        unassigned = [s["id"] for s in proj["sessions"] if s["id"] not in assigned]
        if unassigned:
            proj["unassigned_sessions"] = unassigned
        groups = {}  # feature -> {family: fe}
        who = {}  # feature -> {person: fe}
        for sid, m in fe_by_sid.items():
            g = groups.setdefault(assigned.get(sid, "Other"), {})
            w = who.setdefault(assigned.get(sid, "Other"), {})
            for model, fe in m.items():
                g[family_for(model)] = g.get(family_for(model), 0.0) + fe
                w[sessions[sid]["person"]] = w.get(sessions[sid]["person"], 0.0) + fe
        feats = []
        for feature, fams in groups.items():
            fe_sum = sum(fams.values())
            feats.append({
                "name": feature,
                "fe_tokens": round(fe_sum, 2),
                "weekly_pct": round(fe_sum / implied_cap_fe * 100, 2) if implied_cap_fe else 0,
                "sessions": sum(1 for sid in fe_by_sid if assigned.get(sid, "Other") == feature),
                "models": [
                    {"family": fam, "color": FAMILY_COLORS[fam][2], "fe_tokens": round(fe, 2),
                     "pct": round(fe / fe_sum * 100, 2)}
                    for fam, fe in sorted(fams.items(), key=lambda kv: kv[1], reverse=True)
                ],
                "people": [
                    {"person": pr, "color": palette_for(pr, order)["main"], "fe_tokens": round(fe, 2),
                     "pct": round(fe / fe_sum * 100, 2)}
                    for pr, fe in sorted(who[feature].items(), key=lambda kv: kv[1], reverse=True)
                ],
            })
        feats.sort(key=lambda f: (f["name"] == "Other", -f["fe_tokens"]))
        proj["features"] = feats
    for w in warnings:
        print(w, file=sys.stderr)

    return {
        "window_start": args.window_start,
        "window_end": args.window_end,
        "token_window_start": args.token_window_start,
        "token_window_end": args.token_window_end,
        "cap_pct": p,
        "plan_cost": args.plan_cost,
        "people": people_rows,
        "pie_slices": pie_slices,
        "days": days,
        "devices": [
            {
                "device": c["device"],
                "person": c.get("person", UNKNOWN_PERSON),
                "collected_at": c["collected_at"],
                "sessions": dev_tot[c["device"]][2],
                "fe_tokens": round(dev_tot[c["device"]][0], 2),
                "cost": round(dev_tot[c["device"]][1], 4),
                "weekly_pct": round(dev_tot[c["device"]][0] / implied_cap_fe * 100, 2) if implied_cap_fe else 0,
            }
            for c in contributions
        ],
        "implied_cap_fe": round(implied_cap_fe, 2),
        "combined_cost": round(combined_cost, 4),
        "projects": projects,
        "misc": {"fe_total": round(misc_fe, 2), "cost_total": round(misc_cost, 4), "weekly_pct": misc_weekly_pct,
                 "people": misc_people},
        "unused_pct": unused_pct,
        "model_breakdown": model_breakdown,
        "model_effort_breakdown": model_effort_breakdown,
        "unpriced_models": unpriced,
    }


POOL_RE = re.compile(r'<script type="application/json" id="roundup-data">(.*?)</script>', re.S)


def load_pool(path):
    """Pooled week data from a JSON file or from a published roundup page (its roundup-data block)."""
    text = Path(path).expanduser().read_text()
    if path.endswith((".html", ".htm")) or text.lstrip().startswith("<"):
        m = POOL_RE.search(text)
        if not m:
            sys.exit(f"{path}: no roundup-data block; this page predates pooling")
        text = m.group(1)
    return json.loads(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--files-dir", default=str(Path.home() / "files"))
    ap.add_argument("--claude-projects", default=str(Path.home() / ".claude" / "projects"))
    ap.add_argument("--window-start", required=True, help="YYYY-MM-DD, project/commit window start")
    ap.add_argument("--window-end", required=True, help="YYYY-MM-DD, project/commit window end")
    ap.add_argument("--token-window-start", required=True, help="ISO datetime, token tally window start")
    ap.add_argument("--token-window-end", default=None, help="ISO datetime, token tally window end (exclusive); default: now")
    ap.add_argument("--cap-pct", type=float, default=None, help="percent of weekly cap consumed so far (whole account); the newest entry wins. Default: the pool's last entered value")
    ap.add_argument("--plan-cost", type=float, required=True, help="flat-rate plan cost, $/mo")
    ap.add_argument("--features-file", default=None, help="JSON {project: {feature: [session id or prefix, ...]}}; adds per-feature usage to each project. Default: the pool's saved features")
    ap.add_argument("--device", default=f"{getpass.getuser()}@{socket.gethostname()}", help="label for this machine's data in the pool")
    ap.add_argument("--person", default=None, help="who this machine's usage belongs to (e.g. Jaxon). Spellings pool by first word, case-insensitive. Default: this device's stored person in the pool")
    ap.add_argument("--pool-in", default=None, help="this week's published roundup page (.html) or pool JSON; other devices' data is merged in, this device's is replaced")
    ap.add_argument("--pool-out", default=None, help="write the merged pool JSON here, for embed_pool.py")
    ap.add_argument("--colors-file", default=str(COLORS_FILE), help="project color map, \"<person>|<project key>\" -> accent; read and updated every run (default: project_colors.json next to this script)")
    ap.add_argument("--include-ai-sandbox", action="store_true")
    ap.add_argument("--include-project", action="append", default=[], help="repo dir name to list even with no commits in the window (repeatable)")
    args = ap.parse_args()

    pool = {"version": 1, "devices": [], "features": {}}
    if args.pool_in:
        pool = load_pool(args.pool_in)
        if pool.get("token_window_start") != args.token_window_start:
            sys.exit(f"--token-window-start {args.token_window_start} doesn't match the pool's "
                     f"{pool.get('token_window_start')}; use the pool's window")

    if args.cap_pct is None:
        if pool.get("cap_pct") is None:
            sys.exit("--cap-pct is required (no earlier value in the pool)")
        args.cap_pct = pool["cap_pct"]
        cap_pct_at = pool.get("cap_pct_at")
    else:
        cap_pct_at = datetime.now().isoformat(timespec="minutes")
        if pool.get("cap_pct") is not None and args.cap_pct < pool["cap_pct"]:
            print(f"warning: --cap-pct {args.cap_pct} is lower than the {pool['cap_pct']} entered at "
                  f"{pool.get('cap_pct_at')}; using {args.cap_pct} (newest entry)", file=sys.stderr)

    hostname = host_of(args.device)
    replaced = [c for c in pool["devices"] if entry_host(c) == hostname]
    others = [c for c in pool["devices"] if entry_host(c) != hostname]
    stored_people = people_order(others, pool.get("people", []))
    if args.person is None:
        prev = next((c.get("person") for c in replaced), None)
        if not prev:
            sys.exit("--person is required (who does this machine's usage belong to?)")
        args.person = prev
    person = canonical_person(args.person, people_order(pool["devices"], pool.get("people", [])))
    if person == UNKNOWN_PERSON:
        sys.exit(f"--person {args.person!r}: no name in it")
    for c in replaced:
        if c.get("person", UNKNOWN_PERSON) != person:
            sys.exit(f"error: hostname {hostname} is already in the pool for {c.get('person', UNKNOWN_PERSON)}, "
                     f"but this run is for {person}; one hostname cannot belong to two people. Nothing written.")
    mine = collect(args, args.device, person)
    contributions = others + [mine]
    people = people_order(contributions, stored_people)

    features_map = pool.get("features", {})
    old_sids = set().union(*(entry_sids(c) for c in replaced)) if replaced else set()
    other_sids = set().union(*(entry_sids(c) for c in others)) if others else set()
    if args.features_file:
        features_map = json.loads(Path(args.features_file).expanduser().read_text())
    elif old_sids:
        # This machine's earlier assignments are dropped; the skill reassigns from scratch.
        features_map = {
            proj: {f: kept for f, ids in feats.items()
                   if (kept := [r for r in ids
                                if not (any(o.startswith(r) for o in old_sids)
                                        and not any(o.startswith(r) for o in other_sids))])}
            for proj, feats in features_map.items()
        }
        features_map = {k: v for k, v in features_map.items() if v}
    all_sids = other_sids | entry_sids(mine)
    cleaned = {}
    for proj, feats in features_map.items():
        for f, ids in feats.items():
            keep = []
            for r in ids:
                if any(o.startswith(r) for o in all_sids):
                    keep.append(r)
                else:
                    print(f"warning: {proj} / {f}: session '{r}' is no longer in the pool; link dropped",
                          file=sys.stderr)
            if keep:
                cleaned.setdefault(proj, {})[f] = keep
    features_map = cleaned

    colors_file = Path(args.colors_file).expanduser()
    local_colors = json.loads(colors_file.read_text()) if colors_file.exists() else {}
    colormap = {**local_colors, **pool.get("project_colors", {})}  # the page wins on conflict
    out = report(contributions, args.cap_pct, features_map, args, people, colormap)
    colormap = dict(sorted(colormap.items()))
    colors_file.write_text(json.dumps(colormap, indent=1, ensure_ascii=False) + "\n")

    authored = pool.get("authored") or {"projects": {}, "fixed": {}}
    authored.setdefault("projects", {})
    authored.setdefault("fixed", {})
    out["authored"] = authored
    if replaced:
        out["rewrite"] = {
            "hostname": hostname,
            "replaced_collected_at": replaced[0]["collected_at"],
            "projects": sorted({n for n, h in authored["projects"].items() if h == hostname}
                               | {pr["name"] for pr in out["projects"] if set(pr["devices"]) == {args.device}}),
            "fixed": sorted(i for i, h in authored["fixed"].items() if h == hostname),
        }

    if args.pool_out:
        pool_out = {
            "version": 1,
            "window_start": args.window_start,
            "window_end": args.window_end,
            "token_window_start": args.token_window_start,
            "token_window_end": args.token_window_end,
            "cap_pct": args.cap_pct,
            "cap_pct_at": cap_pct_at,
            "features": features_map,
            "authored": authored,
            "people": people,
            "project_colors": colormap,
            "days": out["days"],
            "devices": others + [public_contribution(mine)],
        }
        Path(args.pool_out).expanduser().write_text(json.dumps(pool_out, separators=(",", ":")))
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
