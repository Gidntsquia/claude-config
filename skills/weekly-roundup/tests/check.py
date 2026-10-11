#!/usr/bin/env python3
"""check.py [out_dir]  -- check the pooled roundup-data of out/S1..S3/week.html. PASS/FAIL per line."""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from gather_data import PRICING

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "out"
EXP = json.loads((HERE / "expected.json").read_text())
A, B = "root@machine-a", "root@machine-b"
fails = 0


def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  -- {detail}"))


def fe_of(sess):
    tot = 0.0
    for model, efforts in sess["usage"].items():
        p = PRICING.get(model) or PRICING["claude-sonnet-5"]
        for c in efforts.values():
            cost = (c["input"] * p["in"] + c["output"] * p["out"] + c["cache_read"] * p["in"] * p.get("cache_read_mult", 0.1)
                    + c["cache_5m"] * p["in"] * 1.25 + c["cache_1h"] * p["in"] * 2.0) / 1e6
            tot += cost / 10.0 * 1e6
    return tot


def load(s):
    f = OUT / s / "week.html"
    if not f.exists():
        return None
    m = re.findall(r'<script type="application/json" id="roundup-data">(.*?)</script>', f.read_text(), re.S)
    check(f"{s}: exactly one roundup-data block", len(m) == 1, f"found {len(m)}")
    return json.loads(m[0]) if m else None


def near(a, b):
    return abs(a - b) <= max(1.0, abs(b) * 1e-6)


def normalize(pool):
    p = json.loads(json.dumps(pool))
    for k in ("features", "cap_pct", "cap_pct_at"):
        p.pop(k, None)
    p["people"] = sorted(p.get("people", []))  # palette order follows run order; names must match
    for d in p["devices"]:
        d.pop("collected_at", None)
    p["devices"].sort(key=lambda d: d["device"])
    for d in p["devices"]:
        d["projects"].sort(key=lambda x: x["name"])
    return p


pools = {s: load(s) for s in ("S1", "S2", "S3")}
for s, pool in pools.items():
    if pool is None:
        check(f"{s}: pool present", False, "no week.html / block")
        continue
    devs = {d["device"]: d for d in pool["devices"]}
    check(f"{s}: devices are exactly machine-a and machine-b", sorted(devs) == [A, B], sorted(devs))
    who = {d: devs[d].get("person") for d in devs}
    check(f"{s}: person per machine == {EXP['person']} (spellings pooled)", who == EXP["person"], who)
    check(f"{s}: pool people == {sorted(set(EXP['person'].values()))}",
          sorted(pool.get("people", [])) == sorted(set(EXP["person"].values())), pool.get("people"))
    names = sorted(p["name"] for d in pool["devices"] for p in d["projects"])
    check(f"{s}: projects are exactly alpha-app and beta-tool (once each)", names == ["alpha-app", "beta-tool"], names)
    for proj, e in EXP["projects"].items():
        d = devs.get(e["device"])
        pr = next((p for p in (d or {}).get("projects", []) if p["name"] == proj), None)
        other = [x for dn, dd in devs.items() if dn != e["device"] for x in dd["projects"] if x["name"] == proj]
        check(f"{s}: {proj} belongs to {e['device']} only", pr is not None and not other)
        if pr:
            check(f"{s}: {proj} commits == {e['commits']} (in-window only)", len(pr["commits"]) == e["commits"], len(pr["commits"]))
            fe = sum(fe_of(x) for x in pr["sessions"].values())
            check(f"{s}: {proj} FE tokens == {e['fe_tokens']:.0f}", near(fe, e["fe_tokens"]), fe)
    for dev, e in EXP["machines"].items():
        d = devs.get(dev)
        if not d:
            check(f"{s}: {dev} present", False)
            continue
        ms = d["misc_sessions"]
        check(f"{s}: {dev} Misc sessions == {e['misc_sessions']}", len(ms) == e["misc_sessions"], len(ms))
        mfe = sum(fe_of(x) for x in ms.values())
        check(f"{s}: {dev} Misc FE == {e['misc_fe_tokens']:.0f}", near(mfe, e["misc_fe_tokens"]), mfe)
        nsess = len(ms) + sum(len(p["sessions"]) for p in d["projects"])
        tfe = mfe + sum(fe_of(x) for p in d["projects"] for x in p["sessions"].values())
        check(f"{s}: {dev} sessions == {e['sessions']}", nsess == e["sessions"], nsess)
        check(f"{s}: {dev} total FE == {e['fe_tokens']:.0f}", near(tfe, e["fe_tokens"]), tfe)
    # Amendment 2026-10-11: projects pie legend grouped by person, most-used person first,
    # each person's projects then their Misc. Read from the rendered page's first legend.
    html = (OUT / s / "week.html").read_text()
    leg = re.search(r'<ul class="legend">(.*?)</ul>', html, re.S)
    items = [re.sub(r"<[^>]+>", "", li).replace("&middot;", "·").strip()
             for li in re.findall(r"<li>(.*?)</li>", leg.group(1) if leg else "", re.S)]
    labels = [re.sub(r"[\d.]+%$", "", x).strip() for x in items if not x.startswith("Unused")]
    pairs = [tuple(part.strip() for part in lab.split("·", 1)) for lab in labels if "·" in lab]
    person_fe = {}
    for dev, e in EXP["machines"].items():
        person_fe[EXP["person"][dev]] = person_fe.get(EXP["person"][dev], 0) + e["fe_tokens"]
    want_people = sorted(person_fe, key=lambda q: -person_fe[q])
    got_people = list(dict.fromkeys(q for _p, q in pairs))
    contiguous = all(pairs[i][1] == pairs[i + 1][1] or pairs[i + 1][1] not in [q for _p, q in pairs[:i + 1]]
                     for i in range(len(pairs) - 1))
    misc_last = all(any(pp == "Misc" for pp, qq in pairs if qq == q) and
                    [pp for pp, qq in pairs if qq == q][-1] == "Misc" for q in want_people)
    check(f"{s}: pie legend grouped by person, most usage first {want_people}, Misc last per person",
          len(pairs) == len(labels) == 4 and contiguous and got_people == want_people and misc_last, labels)
    check(f"{s}: cap_pct == {EXP['cap_pct'][s]}", pool.get("cap_pct") == EXP["cap_pct"][s], pool.get("cap_pct"))
    check(f"{s}: window_start / token_window_start as expected",
          pool.get("window_start") == EXP["window_start"] and pool.get("token_window_start") == EXP["token_window_start"],
          (pool.get("window_start"), pool.get("token_window_start")))

if all(pools.values()):
    n = {s: normalize(p) for s, p in pools.items()}
    check("S1 == S2 (ignoring collected_at, features, cap_pct)", n["S1"] == n["S2"], "pools differ")
    check("S3 == S1 (rerun replaced, did not duplicate)", n["S3"] == n["S1"], "pools differ")
sys.exit(1 if fails else 0)
