"""Merge rules of gather_data.py: no Claude, no Docker, no network. Run: uv run pytest skills/weekly-roundup/tests"""
import json
import os
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


def run(root, device, person, pool_in=None, pool_out=None, features=None, cap="50", expect_ok=True, colors=None):
    cmd = [sys.executable, str(SKILL / "gather_data.py"), "--files-dir", str(root / "files"),
           "--claude-projects", str(root / ".claude" / "projects"), "--window-start", "2026-10-04",
           "--window-end", "2026-10-11", "--token-window-start", TWS, "--token-window-end", "2026-10-11T22:00:00",
           "--plan-cost", "100", "--device", device, "--cap-pct", cap,
           "--colors-file", str(colors or root / "project_colors.json")]
    if person:
        cmd += ["--person", person]
    if pool_in:
        cmd += ["--pool-in", str(pool_in)]
    if pool_out:
        cmd += ["--pool-out", str(pool_out)]
    if features:
        cmd += ["--features-file", str(features)]
    r = subprocess.run(cmd, capture_output=True, text=True, env={**os.environ, "TZ": "America/New_York"})
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


# ---- usage by day, palettes, stable project colors ------------------------------------------
# Local time in these tests is America/New_York (EDT, UTC-4 in October 2026); run() sets TZ.
import colorsys
import itertools

from gather_data import PERSON_PALETTES

SUN_2230 = "2026-10-05T02:30:00Z"   # Sun Oct 4 22:30 local: the opening 22:00-midnight sliver
MON_0010 = "2026-10-05T04:10:00Z"   # Mon Oct 5 00:10 local
TUE_2350 = "2026-10-07T03:50:00Z"   # Tue Oct 6 23:50 local
WED_0020 = "2026-10-07T04:20:00Z"   # Wed Oct 7 00:20 local
CLOSING_SUN = "2026-10-11T18:00:00Z"  # Sun Oct 11 14:00 local, before the closing 22:00
AFTER_END = "2026-10-12T03:00:00Z"   # Sun Oct 11 23:00 local: after the week


def write_msgs(pdir, sid, msgs):
    """One session jsonl: msgs = [(utc timestamp, model, input, output)]."""
    pdir.mkdir(parents=True, exist_ok=True)
    lines = []
    for k, (ts, model, i, o) in enumerate(msgs):
        lines.append(json.dumps({"type": "assistant", "timestamp": ts, "uuid": f"u{k}{sid}", "sessionId": sid,
                                 "message": {"role": "assistant", "id": f"m{k}{sid}", "model": model,
                                             "usage": {"input_tokens": i, "output_tokens": o}}}))
    (pdir / f"{sid}.jsonl").write_text("\n".join(lines) + "\n")


def add_day_sessions(world):
    """Sliver, midnight-crossing, closing-Sunday and after-the-week messages on machine a (alpha-app),
    a shared session on both machines (beta-tool on b, also present on a), Saturday left empty."""
    a_alpha = world["a"] / ".claude/projects" / slug_for(world["a"] / "files" / "alpha-app")
    write_msgs(a_alpha, "dddddddd-0000-4000-8000-000000000001",
               [(SUN_2230, mf.SON, 10_000, 1_000), (MON_0010, mf.SON, 20_000, 2_000)])
    write_msgs(a_alpha, "dddddddd-0000-4000-8000-000000000002",
               [(TUE_2350, mf.FAB, 3_000, 300), (WED_0020, mf.FAB, 4_000, 400)])
    write_msgs(a_alpha, "dddddddd-0000-4000-8000-000000000003",
               [(CLOSING_SUN, mf.SON, 5_000, 500), (AFTER_END, mf.SON, 900_000, 90_000)])


def day(out, label):
    return next(d for d in out["days"] if d["label"] == label)


def seg_pct(d, project, person=None):
    return sum(s["pct"] for s in d["segments"] if s["project"] == project and (person is None or s["person"] == person))


def check_days_invariants(out):
    assert [d["label"] for d in out["days"]] == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    assert [d["date"] for d in out["days"]] == [f"2026-10-{k:02d}" for k in range(4, 11)]
    # R2: per project x person, the days sum to the pie slice; all days sum to the used share
    for sl in out["pie_slices"]:
        got = sum(seg_pct(d, sl["project"], sl["person"]) for d in out["days"])
        assert abs(got - sl["pct"]) <= 0.1, (sl, got)
    assert abs(sum(d["total_pct"] for d in out["days"]) - (100 - out["unused_pct"])) <= 0.1
    # R3: segment colors are the pie's; R4: largest first, pie order on ties
    color = {(sl["project"], sl["person"]): sl["color"] for sl in out["pie_slices"]}
    order = [(sl["project"], sl["person"]) for sl in out["pie_slices"]]
    for d in out["days"]:
        for s in d["segments"]:
            assert s["color"] == color[(s["project"], s["person"])]
        keys = [(-s["pct"], order.index((s["project"], s["person"]))) for s in d["segments"]]
        assert keys == sorted(keys)
        assert abs(sum(s["pct"] for s in d["segments"]) - d["total_pct"]) <= 0.05


def test_days_shape_sums_and_boundaries(world):
    add_day_sessions(world)
    t = world["tmp"]
    out = json.loads(run(world["a"], A, "Jet", pool_out=t / "p1.json").stdout)
    check_days_invariants(out)
    # one person: the existing fixtures' Oct 6 14:05Z / Oct 7 09:00Z messages land on Tue / Wed
    sliver = 10_000 * 2.0 / 1e6 / 10 * 1e6 + 1_000 * 10.0 / 1e6 / 10 * 1e6  # sonnet-4-5 prices as sonnet-5: FE tokens
    cap = out["implied_cap_fe"]
    closing = (5_000 * 2.0 + 500 * 10.0) / 10
    assert abs(seg_pct(day(out, "Sun"), "alpha-app") - round((sliver + closing) / cap * 100, 2)) <= 0.01
    assert seg_pct(day(out, "Mon"), "alpha-app") > 0          # Mon 00:10 is Monday, not Sunday
    assert day(out, "Sat")["segments"] == [] and day(out, "Sat")["total_pct"] == 0  # empty day
    # midnight-crossing session: Tue 23:50 on Tuesday, Wed 00:20 on Wednesday
    p = pool_of(t / "p1.json")
    sess = p["devices"][0]["projects"][0]["sessions"]["dddddddd-0000-4000-8000-000000000002"]
    assert set(sess["days"]) == {"2026-10-06", "2026-10-07"}
    sliver_sess = p["devices"][0]["projects"][0]["sessions"]["dddddddd-0000-4000-8000-000000000001"]
    assert set(sliver_sess["days"]) == {"2026-10-04", "2026-10-05"}
    # after the closing Sunday 22:00 is outside the week
    late = p["devices"][0]["projects"][0]["sessions"]["dddddddd-0000-4000-8000-000000000003"]
    assert set(late["days"]) == {"2026-10-11"}
    assert p["days"] == out["days"]  # R5: stored in the pool (roundup-data)


def test_days_two_people_and_shared_session_once(world):
    add_day_sessions(world)
    t = world["tmp"]
    shared = "eeeeeeee-0000-4000-8000-000000000001"
    for m in ("a", "b"):  # the same session file on both machines (beta-tool, Fri Oct 9 local)
        mf.make_repo(world[m], "b") if m == "a" else None
        write_msgs(world[m] / ".claude/projects" / slug_for(world[m] / "files" / "beta-tool"), shared,
                   [("2026-10-09T16:00:00Z", mf.SON, 50_000, 5_000)])
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    out = json.loads(run(world["b"], B, "Jaxon", pool_in=t / "p1.json", pool_out=t / "p2.json").stdout)
    check_days_invariants(out)
    assert {s["person"] for d in out["days"] for s in d["segments"]} == {"Jet", "Jaxon"}
    misc = [s for d in out["days"] for s in d["segments"] if s["project"] == "Misc"]
    assert {s["person"] for s in misc} == {"Jet", "Jaxon"}
    # the shared session's tokens count once: Friday beta-tool equals one copy of it
    fri = sum(s["pct"] for s in day(out, "Fri")["segments"] if s["project"] == "beta-tool")
    once = (50_000 * 2.0 + 5_000 * 10.0) / 10 / out["implied_cap_fe"] * 100
    assert abs(fri - once) <= 0.01
    assert "days" in pool_of(t / "p2.json")


def test_legacy_pool_entry_without_days(world):
    """An entry stored before per-day data counts each session on its start day."""
    t = world["tmp"]
    run(world["a"], A, "Jet", pool_out=t / "p1.json")
    p = pool_of(t / "p1.json")
    for pr in p["devices"][0]["projects"]:
        for s in pr["sessions"].values():
            del s["days"]
    for s in p["devices"][0]["misc_sessions"].values():
        del s["days"], s["start"]
    (t / "p1.json").write_text(json.dumps(p))
    out = json.loads(run(world["b"], B, "Jaxon", pool_in=t / "p1.json", pool_out=t / "p2.json").stdout)
    check_days_invariants(out)


def _hsl(c):
    r, g, b = (int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360, s * 100, l * 100


def test_person_palettes_separated():
    warm, cool = PERSON_PALETTES[0], PERSON_PALETTES[1]
    assert (warm["name"], cool["name"]) == ("warm", "cool")
    assert len(warm["accents"]) == len(cool["accents"]) == 12
    for pal in (warm, cool):
        assert len(set(pal["accents"])) == 12
        for a, b in itertools.combinations(pal["accents"], 2):
            (ha, _sa, la), (hb, _sb, lb) = _hsl(a), _hsl(b)
            dh = min(abs(ha - hb), 360 - abs(ha - hb))
            assert not (dh < 15 and abs(la - lb) <= 10), (a, b, dh, abs(la - lb))
        for c in pal["accents"]:  # readable on light (#ffffff card) and dark (#1d2027 card)
            assert 25 <= _hsl(c)[2] <= 78 and _hsl(c)[1] >= 40
    # disjoint hue ranges: warm is 300..360 + 0..60, cool is 90..290
    warm_h = [_hsl(c)[0] for c in warm["accents"]]
    cool_h = [_hsl(c)[0] for c in cool["accents"]]
    assert all(h >= 300 or h <= 60 for h in warm_h)
    assert all(90 <= h <= 290 for h in cool_h)
    assert len(PERSON_PALETTES[2]["accents"]) == len(PERSON_PALETTES[3]["accents"]) == 6


def test_colors_stable_across_runs_and_joining(world):
    t = world["tmp"]
    ca, cb = t / "colors-a.json", t / "colors-b.json"
    out1 = json.loads(run(world["a"], A, "Jet", pool_out=t / "p1.json", colors=ca).stdout)
    solo = json.loads(ca.read_text())
    assert solo == {"solo|https://github.com/test/alpha-app": out1["projects"][0]["accent"]}
    out1b = json.loads(run(world["a"], A, "Jet", pool_out=t / "p1.json", colors=ca).stdout)
    assert [p["accent"] for p in out1b["projects"]] == [p["accent"] for p in out1["projects"]]
    # second person joins: fresh colors from each person's half; the solo entry stays
    out2 = json.loads(run(world["b"], B, "Jaxon", pool_in=t / "p1.json", pool_out=t / "p2.json", colors=cb).stdout)
    p2 = pool_of(t / "p2.json")
    m = p2["project_colors"]
    assert m["Jet|https://github.com/test/alpha-app"] in PERSON_PALETTES[0]["accents"]
    assert m["Jaxon|https://github.com/test/beta-tool"] in PERSON_PALETTES[1]["accents"]
    assert m["solo|https://github.com/test/alpha-app"] == solo["solo|https://github.com/test/alpha-app"]
    assert json.loads(cb.read_text()) == m
    # machine a's next run (joining) merges the page's map and reuses its colors; page wins on conflict
    ca.write_text(json.dumps({**json.loads(ca.read_text()), "Jaxon|https://github.com/test/beta-tool": "#ac97ed"}))
    out3 = json.loads(run(world["a"], A, "Jet", pool_in=t / "p2.json", pool_out=t / "p3.json", colors=ca).stdout)
    acc = lambda o: {(sl["project"], sl["person"]): sl["color"] for sl in o["pie_slices"]}
    assert acc(out3) == acc(out2)
    assert json.loads(ca.read_text())["Jaxon|https://github.com/test/beta-tool"] == m["Jaxon|https://github.com/test/beta-tool"]


def test_mapped_color_reused_and_new_project_takes_free_accent(world):
    t = world["tmp"]
    c = t / "colors.json"
    third = PERSON_PALETTES[0]["accents"][2]  # map alpha-app (solo) to a later accent
    c.write_text(json.dumps({"solo|https://github.com/test/alpha-app": "#2f80ed"}))
    mf.make_repo(world["a"], "b")  # machine a also works on beta-tool
    write_msgs(world["a"] / ".claude/projects" / slug_for(world["a"] / "files" / "beta-tool"),
               "ffffffff-0000-4000-8000-000000000001", [("2026-10-08T16:00:00Z", mf.FAB, 900_000, 90_000)])
    out = json.loads(run(world["a"], A, "Jet", colors=c).stdout)
    acc = {p["name"]: p["accent"] for p in out["projects"]}
    assert acc["alpha-app"] == "#2f80ed"          # mapped, reused even though beta-tool is bigger
    from gather_data import SOLO_PALETTE
    assert acc["beta-tool"] == SOLO_PALETTE["accents"][0]  # first accent not used this week
    assert third  # (palette has more than two accents)


def test_thirteen_projects_cycle(tmp_path):
    root = tmp_path / "root"
    files, projs = root / "files", root / ".claude" / "projects"
    names = [f"proj-{k:02d}" for k in range(13)]
    for k, name in enumerate(names):
        repo = files / name
        repo.mkdir(parents=True)
        mf.git(repo, "init", "-q"); mf.git(repo, "config", "user.email", "t@e.com"); mf.git(repo, "config", "user.name", "T")
        (repo / "f").write_text(name)
        mf.git(repo, "add", "."); mf.git(repo, "commit", "-q", "-m", "c",
                                      env={"GIT_AUTHOR_DATE": "2026-10-06T12:00:00+00:00", "GIT_COMMITTER_DATE": "2026-10-06T12:00:00+00:00"})
        write_msgs(projs / slug_for(repo), f"{k:08d}-0000-4000-8000-000000000000",
                   [("2026-10-06T16:00:00Z", mf.SON, 100_000 * (k + 1), 1_000)])
    # a second person so Jet uses a 12-accent person palette
    bm = tmp_path / "root-b"
    mf.make_repo(bm, "b")
    write_msgs(bm / ".claude/projects" / slug_for(bm / "files" / "beta-tool"), "bbbbbbbb-1111-4000-8000-000000000000",
               [("2026-10-06T16:00:00Z", mf.SON, 1_000, 100)])
    run(bm, B, "Jaxon", pool_out=tmp_path / "p1.json", colors=tmp_path / "cb.json")
    r = run(root, A, "Jet", pool_in=tmp_path / "p1.json", pool_out=tmp_path / "p2.json", colors=tmp_path / "ca.json")
    out = json.loads(r.stdout)
    jet = [p["accent"] for p in out["projects"] if p["lead_person"] == "Jet"]
    jet_pal = next(r for r in out["people"] if r["person"] == "Jet")
    assert jet_pal["palette"] == "cool" and len(jet_pal["accents"]) == 12  # Jaxon was seen first
    assert len(jet) == 13 and all(a in PERSON_PALETTES[1]["accents"] for a in jet)
    assert len(set(jet)) == 12  # 12 distinct, the 13th reuses one
    check_days_invariants(out)
    again = json.loads(run(root, A, "Jet", pool_in=tmp_path / "p1.json", colors=tmp_path / "ca.json").stdout)
    assert [p["accent"] for p in again["projects"]] == [p["accent"] for p in out["projects"]]
