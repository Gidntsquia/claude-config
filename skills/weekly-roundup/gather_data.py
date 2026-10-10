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
      --cap-pct 90 --plan-cost 100 \
      [--device jaxon@desktop] [--pool-in this-week.html] [--pool-out pool.json] \
      [--include-ai-sandbox] [--include-project yugioh-deck-optimizer]
"""
import argparse
import getpass
import json
import re
import socket
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# Per-million-token USD list prices (source: platform.claude.com/docs/en/about-claude/pricing,
# checked 2026-10-04). Cache reads default to 0.1x input; override with "cache_read_mult".
# Cache writes are 1.25x (5m) / 2x (1h) input. Update as pricing changes.
PRICING = {
    "claude-sonnet-5-5":      {"in": 2.00,  "out": 10.00, "display": "Sonnet 5.5"},
    "claude-sonnet-5":        {"in": 2.00,  "out": 10.00, "display": "Sonnet 5"},
    "claude-opus-5-5":        {"in": 4.00,  "out": 20.00, "cache_read_mult": 0.05, "display": "Opus 5.5"},
    "claude-opus-5":          {"in": 5.00,  "out": 25.00, "display": "Opus 5"},
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
}

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}


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
    # Claude Code maps every non-alphanumeric character (/, _, ., space) to "-"
    return "-" + re.sub(r"[^A-Za-z0-9-]", "-", str(path).strip("/"))


def _prompt_text(msg):
    c = msg.get("content")
    if isinstance(c, list):
        c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    return c.strip() if isinstance(c, str) else ""




TOKEN_KEYS = ("input", "output", "cache_read", "cache_5m", "cache_1h")


def _new_counts():
    return {k: 0 for k in TOKEN_KEYS}


def scan_project_dir(dir_path: Path, window_start: datetime, window_end: datetime = None, sessions=None):
    """Fill sessions[session_id] = {start, prompt, usage: {model: {effort: counts}}} for one
    Claude-project jsonl directory, deduped by message id. One session per jsonl file; subagent
    usage counts toward its parent session; prompt = first real user message in the window;
    effort is "" when the record has none."""
    if sessions is None:
        sessions = {}
    seen = {}  # msg_id -> output_tokens already counted, to add only deltas
    for jsonl in dir_path.rglob("*.jsonl"):
        # Subagent transcripts (<session>/subagents/agent-*.jsonl) count toward their parent session.
        sid = jsonl.parent.parent.name if jsonl.parent.name == "subagents" else jsonl.stem
        sess = sessions.setdefault(sid, {"start": None, "prompt": "", "usage": {}})
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
            slot = sess["usage"].setdefault(model, {}).setdefault(effort, _new_counts())
            for k, v in deltas.items():
                slot[k] += v
    return sessions


def collect(args, device):
    """This machine's contribution to the week: per-project sessions with raw token counts,
    commits, remotes, plus Misc sessions. Pricing is applied later, so contributions from
    several devices merge losslessly."""
    files_dir = Path(args.files_dir).expanduser()
    claude_projects = Path(args.claude_projects).expanduser()
    token_window_start = datetime.fromisoformat(args.token_window_start)
    token_window_end = datetime.fromisoformat(args.token_window_end) if args.token_window_end else None

    projects = []
    matched_slugs = set()
    moved_old = {old for olds in MOVED_FROM.values() for old in olds}
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
            if d.is_dir() and any(d.name == e or d.name.startswith(e + "-") for e in expected_slugs):
                matched_slugs.add(d.name)
                scan_project_dir(d, token_window_start, token_window_end, sessions)
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
    misc = {sid: {"usage": s["usage"]} for sid, s in misc.items() if s["usage"]}

    return {
        "device": device,
        "collected_at": datetime.now().isoformat(timespec="minutes"),
        "projects": projects,
        "misc_sessions": misc,
    }


def public_contribution(c):
    """A contribution as stored in the published page: drops first prompts, local paths and
    screenshot paths (the page may be shared publicly; other devices can't use them anyway)."""
    return {
        "device": c["device"],
        "collected_at": c["collected_at"],
        "projects": [
            {
                "name": p["name"],
                "remote_url": p["remote_url"],
                "commits": p["commits"],
                "sessions": {sid: {"start": s["start"], "usage": s["usage"]} for sid, s in p["sessions"].items()},
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
                hit["sessions"][sid] = {"prompt": "", **s, "device": c["device"]}  # this machine (last) wins
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


def report(contributions, cap_pct, features_map, args):
    projects = merge_projects(contributions)
    misc_sessions = {}
    for c in contributions:
        misc_sessions.update(c["misc_sessions"])

    eff_totals = counts_by(
        [s for p in projects for s in p["sessions"].values()] + list(misc_sessions.values()),
        lambda m, e: (m, e or None))

    for proj in projects:
        model_totals = counts_by(proj["sessions"].values(), lambda m, e: m)
        token_rows = []
        fe_total = cost_total = 0.0
        for model, t in model_totals.items():
            if model in PRICING and PRICING[model]["in"] == 0 and PRICING[model]["out"] == 0:
                continue  # free local model: no usage to show
            cost, fe, raw = priced(t, model)
            fe_total += fe
            cost_total += cost
            token_rows.append({
                "model": model,
                "model_display": display_name(model),
                "raw_tokens": raw,
                "fe_tokens": round(fe, 2),
                "cost": round(cost, 4),
            })
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
        by_model[model] = [fe, cost, raw]

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
        for sid, m in fe_by_sid.items():
            g = groups.setdefault(assigned.get(sid, "Other"), {})
            for model, fe in m.items():
                g[family_for(model)] = g.get(family_for(model), 0.0) + fe
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
            })
        feats.sort(key=lambda f: (f["name"] == "Other", -f["fe_tokens"]))
        proj["features"] = feats
    for w in warnings:
        print(w, file=sys.stderr)

    projects.sort(key=lambda pr: pr["weekly_pct"], reverse=True)

    return {
        "window_start": args.window_start,
        "window_end": args.window_end,
        "token_window_start": args.token_window_start,
        "token_window_end": args.token_window_end,
        "cap_pct": p,
        "plan_cost": args.plan_cost,
        "devices": [{"device": c["device"], "collected_at": c["collected_at"]} for c in contributions],
        "implied_cap_fe": round(implied_cap_fe, 2),
        "combined_cost": round(combined_cost, 4),
        "projects": projects,
        "misc": {"fe_total": round(misc_fe, 2), "cost_total": round(misc_cost, 4), "weekly_pct": misc_weekly_pct},
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
    ap.add_argument("--cap-pct", type=float, required=True, help="percent of weekly cap consumed so far (whole account)")
    ap.add_argument("--plan-cost", type=float, required=True, help="flat-rate plan cost, $/mo")
    ap.add_argument("--features-file", default=None, help="JSON {project: {feature: [session id or prefix, ...]}}; adds per-feature usage to each project. Default: the pool's saved features")
    ap.add_argument("--device", default=f"{getpass.getuser()}@{socket.gethostname()}", help="label for this machine's data in the pool")
    ap.add_argument("--pool-in", default=None, help="this week's published roundup page (.html) or pool JSON; other devices' data is merged in, this device's is replaced")
    ap.add_argument("--pool-out", default=None, help="write the merged pool JSON here, for embed_pool.py")
    ap.add_argument("--include-ai-sandbox", action="store_true")
    ap.add_argument("--include-project", action="append", default=[], help="repo dir name to list even with no commits in the window (repeatable)")
    args = ap.parse_args()

    pool = {"version": 1, "devices": [], "features": {}}
    if args.pool_in:
        pool = load_pool(args.pool_in)
        if pool.get("token_window_start") != args.token_window_start:
            sys.exit(f"--token-window-start {args.token_window_start} doesn't match the pool's "
                     f"{pool.get('token_window_start')}; use the pool's window")

    mine = collect(args, args.device)
    others = [c for c in pool["devices"] if c["device"] != args.device]
    contributions = others + [mine]

    features_map = pool.get("features", {})
    if args.features_file:
        features_map = json.loads(Path(args.features_file).expanduser().read_text())

    out = report(contributions, args.cap_pct, features_map, args)

    if args.pool_out:
        pool_out = {
            "version": 1,
            "window_start": args.window_start,
            "token_window_start": args.token_window_start,
            "cap_pct": args.cap_pct,
            "cap_pct_at": mine["collected_at"],
            "features": features_map,
            "devices": others + [public_contribution(mine)],
        }
        Path(args.pool_out).expanduser().write_text(json.dumps(pool_out, separators=(",", ":")))
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
