"""Merge rules of gather_data.py: no Claude, no Docker, no network. Run: uv run pytest skills/weekly-roundup/tests"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
SKILL = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(SKILL))
import make_fixtures as mf  # fake repos + session jsonl
from gather_data import slug_for

TWS = "2026-10-04T22:00:00"
A, B = "root@machine-a", "root@machine-b"


def machine(tmp_path, m):
    root = tmp_path / f"root-{m}"
    mf.make_repo(root, m)
    for proj, ss in mf.SESS[m].items():
        slug = slug_for(root / "files" / proj) if proj != "scratch" else "-root-scratch"
        for n, s in enumerate(ss):
            mf.write_session(root / ".claude" / "projects" / slug, *s, n)
    return root


def run(root, device, person, pool_in=None, pool_out=None, features=None, cap="50", expect_ok=True):
    cmd = [sys.executable, str(SKILL / "gather_data.py"), "--files-dir", str(root / "files"),
           "--claude-projects", str(root / ".claude" / "projects"), "--window-start", "2026-10-04",
           "--window-end", "2026-10-11", "--token-window-start", TWS, "--token-window-end", "2026-10-11T22:00:00",
           "--plan-cost", "100", "--device", device, "--cap-pct", cap]
    if person:
        cmd += ["--person", person]
    if pool_in:
        cmd += ["--pool-in", str(pool_in)]
    if pool_out:
        cmd += ["--pool-out", str(pool_out)]
    if features:
        cmd += ["--features-file", str(features)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    assert (r.returncode == 0) == expect_ok, r.stderr
    return r


@pytest.fixture
def world(tmp_path):
    return {"a": machine(tmp_path, "a"), "b": machine(tmp_path, "b"), "tmp": tmp_path}


def pool_of(path):
    return json.loads(Path(path).read_text())


def test_first_run_one_entry(world):
    out = world["tmp"] / "p.json"
    r = run(world["a"], A, "Jet", pool_out=out)
    p = pool_of(out)
    assert len(p["devices"]) == 1 and p["devices"][0]["hostname"] == "machine-a"
    assert "rewrite" not in json.loads(r.stdout)


def test_rerun_equals_single_run(world):
    t = world["tmp"]
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    r1 = run(world["a"], A, "Jet", pool_out=t / "p1.json")
    run(world["b"], B, "Jaxon", pool_in=t / "p1.json", pool_out=t / "p2.json")
    b_before = [d for d in pool_of(t / "p2.json")["devices"] if d["device"] == B][0]
    r2 = run(world["a"], A, "Jet", pool_in=t / "p2.json", pool_out=t / "p3.json")
    r3 = run(world["a"], A, "Jet", pool_in=t / "p3.json", pool_out=t / "p4.json")
    p3, p4 = pool_of(t / "p3.json"), pool_of(t / "p4.json")
    assert [d["hostname"] for d in p4["devices"]].count("machine-a") == 1 and len(p4["devices"]) == 2
    assert [d for d in p4["devices"] if d["device"] == B] == [b_before]
    strip = lambda p: {d["device"]: {k: v for k, v in d.items() if k != "collected_at"} for d in p["devices"]}
    assert strip(p3) == strip(p4)
    assert json.loads(r2.stdout)["combined_cost"] == json.loads(r3.stdout)["combined_cost"]
    assert "rewrite" in json.loads(r3.stdout)
    # totals equal a single run of A alone
    solo = run(world["a"], A, "Jet")
    d = json.loads(r1.stdout)
    assert d["combined_cost"] == json.loads(solo.stdout)["combined_cost"]


def test_rerun_drops_own_feature_links_keeps_other(world):
    t = world["tmp"]
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    run(world["b"], B, "Jaxon", pool_in=t / "p1.json", pool_out=t / "p2.json")
    pool = pool_of(t / "p2.json")
    pool["features"] = {"alpha-app": {"F1": ["aaaaaaa1-0000-4000-8000-000000000001"]},
                        "beta-tool": {"F2": ["bbbbbbb1-0000-4000-8000-000000000001"]}}
    (t / "p2.json").write_text(json.dumps(pool))
    run(world["a"], A, "Jet", pool_in=t / "p2.json", pool_out=t / "p3.json")
    assert pool_of(t / "p3.json")["features"] == {"beta-tool": {"F2": ["bbbbbbb1-0000-4000-8000-000000000001"]}}


def test_dangling_feature_link_warns_and_drops(world):
    t = world["tmp"]
    ff = t / "f.json"
    ff.write_text(json.dumps({"alpha-app": {"F": ["aaaaaaa1-0000-4000-8000-000000000001", "zzzzzzzz-gone"]}}))
    r = run(world["a"], A, "Jet", features=ff, pool_out=t / "p.json")
    assert "zzzzzzzz-gone" in r.stderr and "no longer in the pool" in r.stderr
    assert pool_of(t / "p.json")["features"] == {"alpha-app": {"F": ["aaaaaaa1-0000-4000-8000-000000000001"]}}


def test_same_hostname_different_person_errors(world):
    t = world["tmp"]
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    r = run(world["a"], A, "Jaxon", pool_in=t / "p1.json", pool_out=t / "p2.json", expect_ok=False)
    assert "Jet" in r.stderr and "Jaxon" in r.stderr and "machine-a" in r.stderr
    assert not (t / "p2.json").exists()


def test_two_hostnames_same_person_stay_two(world):
    t = world["tmp"]
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    run(world["b"], B, "Jet", pool_in=t / "p1.json", pool_out=t / "p2.json")
    assert len(pool_of(t / "p2.json")["devices"]) == 2


def test_legacy_entry_without_hostname_matched(world):
    t = world["tmp"]
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    p = pool_of(t / "p1.json")
    del p["devices"][0]["hostname"]
    (t / "p1.json").write_text(json.dumps(p))
    run(world["a"], A, None, pool_in=t / "p1.json", pool_out=t / "p2.json")
    devs = pool_of(t / "p2.json")["devices"]
    assert len(devs) == 1 and devs[0]["hostname"] == "machine-a"


def test_shared_project_keeps_other_machine(world):
    t = world["tmp"]
    # machine B also worked on alpha-app (same remote): one shared id, one B-only id
    shared = "aaaaaaa1-0000-4000-8000-000000000001"
    bonly = "bbbbbbb1-0000-4000-8000-0000000000ff"
    mf.make_repo(world["b"], "a")
    mf.write_session(world["b"] / ".claude/projects" / slug_for(world["b"] / "files" / "alpha-app"), shared, mf.SON, 100_000, 200_000, 50_000, 0, 0)
    mf.write_session(world["b"] / ".claude/projects" / slug_for(world["b"] / "files" / "alpha-app"), bonly, mf.SON, 10_000, 20_000, 0, 0, 1)
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    run(world["b"], B, "Jaxon", pool_in=t / "p1.json", pool_out=t / "p2.json")
    r = run(world["a"], A, "Jet", pool_in=t / "p2.json", pool_out=t / "p3.json")
    alpha = next(p for p in json.loads(r.stdout)["projects"] if p["name"] == "alpha-app")
    ids = [s["id"] for s in alpha["sessions"]]
    assert bonly in ids and ids.count(shared) == 1
    hashes = [c for c in alpha["commits"]]
    assert len(hashes) == len(set(hashes)) == 3  # same commit subjects, counted once
    b_entry = next(d for d in pool_of(t / "p3.json")["devices"] if d["device"] == B)
    assert any(p["name"] == "alpha-app" and bonly in p["sessions"] for p in b_entry["projects"])


def test_rewrite_lists_authored(world):
    t = world["tmp"]
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    run(world["b"], B, "Jaxon", pool_in=t / "p1.json", pool_out=t / "p2.json")
    p = pool_of(t / "p2.json")
    p["authored"] = {"projects": {"alpha-app": "machine-a", "beta-tool": "machine-b"},
                     "fixed": {"fix-1": "machine-a", "fix-2": "machine-b"}}
    (t / "p2.json").write_text(json.dumps(p))
    r = run(world["a"], A, "Jet", pool_in=t / "p2.json", pool_out=t / "p3.json")
    rw = json.loads(r.stdout)["rewrite"]
    assert rw["projects"] == ["alpha-app"] and rw["fixed"] == ["fix-1"]
    assert pool_of(t / "p3.json")["authored"] == p["authored"]
