#!/usr/bin/env python3
"""make_fixtures.py <a|b> [--root DIR] [--expected FILE]
Generate fake git repos + Claude session jsonl for one machine, under DIR (default /root).
With --expected, write the hand-computed expected totals for BOTH machines to FILE."""
import argparse, json, os, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from gather_data import PRICING  # price table only; no pooling logic is used

SON, FAB = "claude-sonnet-4-5", "claude-fable-5-1"
# 1-based session ids; counts: input, output, cache_read, cache_5m
SESS = {
 "a": {"alpha-app": [("aaaaaaa1-0000-4000-8000-000000000001", SON, 100_000, 200_000, 50_000, 0),
                     ("aaaaaaa1-0000-4000-8000-000000000002", FAB, 10_000, 20_000, 400_000, 100_000)],
       "scratch":   [("aaaaaaa1-0000-4000-8000-000000000003", SON, 30_000, 60_000, 0, 0)]},
 "b": {"beta-tool": [("bbbbbbb1-0000-4000-8000-000000000001", FAB, 50_000, 100_000, 200_000, 0)],
       "scratch":   [("bbbbbbb1-0000-4000-8000-000000000002", SON, 40_000, 80_000, 10_000, 0),
                     ("bbbbbbb1-0000-4000-8000-000000000003", FAB, 5_000, 10_000, 0, 20_000)]},
}
REPOS = {"a": ("alpha-app", 3), "b": ("beta-tool", 2)}
OLD = 1_000_000  # extra tokens in a pre-window message that must be excluded


def fe(model, i, o, cr, c5):
    p = PRICING.get(model) or PRICING["claude-sonnet-5"]  # unknown models priced as sonnet-5
    cost = (i * p["in"] + o * p["out"] + cr * p["in"] * p.get("cache_read_mult", 0.1) + c5 * p["in"] * 1.25) / 1e6
    return cost, cost / 10.0 * 1e6


def expected():
    out = {"window_start": "2026-10-04", "token_window_start": "2026-10-04T22:00:00",
           "cap_pct": {"S1": 55, "S2": 40, "S3": 55}, "machines": {}, "projects": {},
           "person": {"root@machine-a": "Jet", "root@machine-b": "Jaxon"}}  # run.sh varies the spelling per run
    for m, projs in SESS.items():
        dev = f"root@machine-{m}"
        d = {"sessions": 0, "fe_tokens": 0.0, "cost": 0.0, "misc_sessions": 0, "misc_fe_tokens": 0.0}
        for proj, ss in projs.items():
            for sid, model, i, o, cr, c5 in ss:
                cost, f = fe(model, i, o, cr, c5)
                d["sessions"] += 1; d["fe_tokens"] += f; d["cost"] += cost
                if proj == "scratch":
                    d["misc_sessions"] += 1; d["misc_fe_tokens"] += f
                else:
                    pr = out["projects"].setdefault(proj, {"device": dev, "commits": REPOS[m][1], "fe_tokens": 0.0, "sessions": 0})
                    pr["fe_tokens"] += f; pr["sessions"] += 1
        out["machines"][dev] = d
    return out


def git(repo, *a, env=None):
    subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True, env={**os.environ, **(env or {})})


def make_repo(root, m):
    name, n = REPOS[m]
    repo = Path(root) / "files" / name
    repo.mkdir(parents=True, exist_ok=True)
    git(repo, "init", "-q"); git(repo, "config", "user.email", "t@example.com"); git(repo, "config", "user.name", "Test")
    git(repo, "remote", "add", "origin", f"https://github.com/test/{name}")
    dates = ["2026-10-01T12:00:00"] + [f"2026-10-0{5 + k}T12:00:00" for k in range(n)]
    if m == "b":
        dates = dates[:1] + dates[1:]  # b: 1 pre-window commit + 2 in window
    for k, dt in enumerate(dates):
        (repo / f"f{k}.txt").write_text(f"{name} {k}\n")
        git(repo, "add", "."); 
        git(repo, "commit", "-q", "-m", f"{name} commit {k}", env={"GIT_AUTHOR_DATE": dt + "+00:00", "GIT_COMMITTER_DATE": dt + "+00:00"})


def write_session(pdir, sid, model, i, o, cr, c5, n):
    pdir.mkdir(parents=True, exist_ok=True)
    def rec(ts, mid, usage, role="assistant"):
        r = {"type": role, "timestamp": ts, "uuid": mid, "sessionId": sid, "message": {"role": role, "id": mid, "model": model, "usage": usage} if role == "assistant" else {"role": "user", "content": f"fixture task {n} for {sid[:8]}"}}
        return json.dumps(r)
    lines = [rec("2026-10-06T14:00:00Z", "u" + sid, None, "user"),
             rec("2026-10-03T14:00:00Z", "old" + sid, {"input_tokens": OLD, "output_tokens": OLD, "cache_read_input_tokens": 0, "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}})]
    half = lambda x: x // 2
    for k, ts in enumerate(["2026-10-06T14:05:00Z", "2026-10-07T09:00:00Z"]):
        lines.append(rec(ts, f"m{k}{sid}", {"input_tokens": half(i), "output_tokens": half(o), "cache_read_input_tokens": half(cr),
                                            "cache_creation": {"ephemeral_5m_input_tokens": half(c5), "ephemeral_1h_input_tokens": 0}}))
    (pdir / f"{sid}.jsonl").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("machine", nargs="?", choices=["a", "b"])
    ap.add_argument("--root", default="/root")
    ap.add_argument("--expected")
    a = ap.parse_args()
    if a.expected:
        Path(a.expected).write_text(json.dumps(expected(), indent=1) + "\n")
    if a.machine:
        m = a.machine
        make_repo(a.root, m)
        for proj, ss in SESS[m].items():
            slug = "-root-files-" + proj if proj != "scratch" else "-root-scratch"
            for n, s in enumerate(ss):
                write_session(Path(a.root) / ".claude" / "projects" / slug, *s, n)
        print(f"fixtures for machine {m} under {a.root}")
