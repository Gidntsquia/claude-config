#!/usr/bin/env python3
"""
Deterministic data-gathering for the weekly-roundup skill.

Replaces the manual git-log / jsonl-scanning / token-math tool calls with one
script invocation. Outputs JSON: repos worked on (with commits, remote,
screenshot candidates) and per-project token/cost breakdowns. Judgment calls
(key learnings, HTML writing, picking the deep-dive picture) stay with Claude.

Usage:
  gather_data.py --files-dir ~/files --claude-projects ~/.claude/projects \
      --window-start 2026-09-04 --window-end 2026-09-11 \
      --token-window-start "2026-09-06T22:00:00" \
      [--token-window-end "2026-09-13T22:00:00"] \
      --cap-pct 90 --plan-cost 100 \
      [--include-ai-sandbox] [--include-project yugioh-deck-optimizer]
"""
import argparse
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path

# Per-million-token USD list prices (source: platform.claude.com/docs/en/about-claude/pricing,
# checked 2026-09-20). Cache reads default to 0.1x input; override with "cache_read_mult".
# Cache writes are 1.25x (5m) / 2x (1h) input. Update as pricing changes.
PRICING = {
    "claude-sonnet-5":        {"in": 2.00,  "out": 10.00, "display": "Sonnet 5"},
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
    log = git(repo, "log", f"--since={start}", f"--until={end} 23:59:59", "--format=%s")
    return [l for l in log.splitlines() if l.strip()]


def slug_for(path: Path) -> str:
    return "-" + str(path).strip("/").replace("/", "-")


def scan_project_dir(dir_path: Path, window_start: datetime, eff_totals=None, window_end: datetime = None):
    """Return {model: {input, output, cache_read, cache_5m, cache_1h}} for one
    Claude-project jsonl directory, deduped by message id. If eff_totals is a
    dict, also accumulate the same counts into it keyed by (model, effort)."""
    totals = {}
    _new = lambda: {"input": 0, "output": 0, "cache_read": 0, "cache_5m": 0, "cache_1h": 0}

    def add(model, effort, **deltas):
        targets = [totals.setdefault(model, _new())]
        if eff_totals is not None:
            targets.append(eff_totals.setdefault((model, effort), _new()))
        for slot in targets:
            for k, v in deltas.items():
                slot[k] += v

    seen = {}  # msg_id -> output_tokens already counted, to add only deltas
    for jsonl in dir_path.rglob("*.jsonl"):
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
            if not usage:
                continue
            ts = rec.get("timestamp")
            if ts:
                try:
                    t = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().replace(tzinfo=None)
                except ValueError:
                    t = None
                if t and (t < window_start or (window_end and t >= window_end)):
                    continue
            model = msg.get("model", "unknown")
            effort = rec.get("effort")
            msg_id = msg.get("id") or rec.get("uuid")
            out_t = usage.get("output_tokens", 0)
            in_t = usage.get("input_tokens", 0)
            cache_read = usage.get("cache_read_input_tokens", 0)
            cc = usage.get("cache_creation") or {}
            c5m = cc.get("ephemeral_5m_input_tokens", usage.get("cache_creation_input_tokens", 0) if not cc else 0)
            c1h = cc.get("ephemeral_1h_input_tokens", 0)

            key = (msg_id, model)
            if msg_id and key in seen:
                prev_out = seen[key]
                if out_t > prev_out:
                    delta = out_t - prev_out
                    seen[key] = out_t
                    add(model, effort, output=delta)
                continue
            if msg_id:
                seen[key] = out_t

            add(model, effort, input=in_t, output=out_t, cache_read=cache_read, cache_5m=c5m, cache_1h=c1h)
    return totals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--files-dir", default=str(Path.home() / "files"))
    ap.add_argument("--claude-projects", default=str(Path.home() / ".claude" / "projects"))
    ap.add_argument("--window-start", required=True, help="YYYY-MM-DD, project/commit window start")
    ap.add_argument("--window-end", required=True, help="YYYY-MM-DD, project/commit window end")
    ap.add_argument("--token-window-start", required=True, help="ISO datetime, token tally window start")
    ap.add_argument("--token-window-end", default=None, help="ISO datetime, token tally window end (exclusive); default: now")
    ap.add_argument("--cap-pct", type=float, required=True, help="percent of weekly cap consumed so far")
    ap.add_argument("--plan-cost", type=float, required=True, help="flat-rate plan cost, $/mo")
    ap.add_argument("--include-ai-sandbox", action="store_true")
    ap.add_argument("--include-project", action="append", default=[], help="repo dir name to list even with no commits in the window (repeatable)")
    args = ap.parse_args()

    files_dir = Path(args.files_dir).expanduser()
    claude_projects = Path(args.claude_projects).expanduser()
    token_window_start = datetime.fromisoformat(args.token_window_start)
    token_window_end = datetime.fromisoformat(args.token_window_end) if args.token_window_end else None

    repos = list(find_repos(files_dir, args.include_ai_sandbox, claude_projects))

    eff_totals = {}  # (model, effort) -> token counts, all dirs
    projects = []
    matched_slugs = set()
    for repo in repos:
        is_git = (repo / ".git").exists()
        commits = repo_commits(repo, args.window_start, args.window_end) if is_git else []
        if is_git and not commits and repo.name not in args.include_project:
            continue
        remote = normalize_remote(git(repo, "remote", "get-url", "origin")) if is_git else ""
        screenshot = find_screenshot(repo, args.window_start)

        expected_slug = slug_for(repo)
        model_totals = {}
        for d in claude_projects.iterdir():
            if not d.is_dir():
                continue
            if d.name == expected_slug or d.name.startswith(expected_slug + "-"):
                matched_slugs.add(d.name)
                dir_totals = scan_project_dir(d, token_window_start, eff_totals, token_window_end)
                for model, t in dir_totals.items():
                    slot = model_totals.setdefault(model, {"input": 0, "output": 0, "cache_read": 0, "cache_5m": 0, "cache_1h": 0})
                    for k in slot:
                        slot[k] += t[k]

        token_rows = []
        project_fe_total = 0.0
        project_cost_total = 0.0
        for model, t in model_totals.items():
            if model in PRICING and PRICING[model]["in"] == 0 and PRICING[model]["out"] == 0:
                continue  # free local model: no usage to show
            raw = t["input"] + t["output"] + t["cache_read"] + t["cache_5m"] + t["cache_1h"]
            cost, fe = price_row(model, t["input"], t["output"], t["cache_read"], t["cache_5m"], t["cache_1h"])
            project_fe_total += fe
            project_cost_total += cost
            token_rows.append({
                "model": model,
                "model_display": display_name(model),
                "raw_tokens": raw,
                "fe_tokens": round(fe, 2),
                "cost": round(cost, 4),
            })
        token_rows.sort(key=lambda r: r["fe_tokens"], reverse=True)

        projects.append({
            "name": repo.name,
            "path": str(repo),
            "remote_url": remote,
            "commits": commits,
            "screenshot": screenshot,
            "token_rows": token_rows,
            "fe_total": round(project_fe_total, 2),
            "cost_total": round(project_cost_total, 4),
        })

    # Misc: every other claude-project dir active in the token window, not matched above.
    misc_fe = 0.0
    misc_cost = 0.0
    misc_by_model = {}  # model -> [fe, cost, raw]
    for d in claude_projects.iterdir():
        if not d.is_dir() or d.name in matched_slugs:
            continue
        dir_totals = scan_project_dir(d, token_window_start, eff_totals, token_window_end)
        for model, t in dir_totals.items():
            cost, fe = price_row(model, t["input"], t["output"], t["cache_read"], t["cache_5m"], t["cache_1h"])
            misc_fe += fe
            misc_cost += cost
            raw = t["input"] + t["output"] + t["cache_read"] + t["cache_5m"] + t["cache_1h"]
            m = misc_by_model.setdefault(model, [0.0, 0.0, 0])
            m[0] += fe
            m[1] += cost
            m[2] += raw

    # Per-model usage across tracked projects + Misc, weighted by FE tokens
    # (cost-normalized), as a share of total used FE tokens (sums to 100%, no Unused).
    by_model = {model: list(v) for model, v in misc_by_model.items()}
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
        cost, fe = price_row(model, t["input"], t["output"], t["cache_read"], t["cache_5m"], t["cache_1h"])
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
    p = args.cap_pct
    implied_cap_fe = combined_fe / (p / 100) if p else combined_fe

    for proj in projects:
        proj["weekly_pct"] = round((proj["fe_total"] / implied_cap_fe) * 100, 2) if implied_cap_fe else 0
    misc_weekly_pct = round((misc_fe / implied_cap_fe) * 100, 2) if implied_cap_fe else 0
    unused_pct = round(100 - p, 2)

    projects.sort(key=lambda pr: pr["weekly_pct"], reverse=True)

    out = {
        "window_start": args.window_start,
        "window_end": args.window_end,
        "token_window_start": args.token_window_start,
        "token_window_end": args.token_window_end,
        "cap_pct": p,
        "plan_cost": args.plan_cost,
        "implied_cap_fe": round(implied_cap_fe, 2),
        "combined_cost": round(combined_cost + misc_cost, 4),
        "projects": projects,
        "misc": {"fe_total": round(misc_fe, 2), "cost_total": round(misc_cost, 4), "weekly_pct": misc_weekly_pct},
        "unused_pct": unused_pct,
        "model_breakdown": model_breakdown,
        "model_effort_breakdown": model_effort_breakdown,
        "unpriced_models": unpriced,
    }
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
