#!/usr/bin/env python3
"""Build the Roundup Archive page from archive_weeks.json.

  build_archive.py --out <page.html> [--add <week.json>]

--add inserts or replaces (by weekStart) one week in archive_weeks.json first.
"""
import argparse, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
WEEKS = os.path.join(HERE, "archive_weeks.json")
TEMPLATE = os.path.join(HERE, "archive_template.html")
KEYS = ["weekStart", "label", "url", "projectCount", "totalCost", "slices"]

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--add")
a = ap.parse_args()

weeks = json.load(open(WEEKS))
if a.add:
    new = json.load(open(a.add))
    missing = [k for k in KEYS if k not in new]
    if missing:
        raise SystemExit(f"week is missing {missing}")
    weeks = [w for w in weeks if w["weekStart"] != new["weekStart"]]
    weeks.append({k: new[k] for k in KEYS})
    weeks.sort(key=lambda w: w["weekStart"])
    with open(WEEKS, "w") as f:
        json.dump(weeks, f, indent=1, ensure_ascii=False)
        f.write("\n")

data = json.dumps(weeks, ensure_ascii=False).replace("</", "<\\/")
html = open(TEMPLATE).read().replace("__WEEKS_JSON__", data)
with open(a.out, "w") as f:
    f.write(html)
print(f"{len(weeks)} weeks -> {a.out}")
