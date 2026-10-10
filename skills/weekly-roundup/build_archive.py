#!/usr/bin/env python3
"""Build the Roundup Archive page from archive_weeks.json.

  build_archive.py --out <page.html> [--add <week.json>] [--base <published archive.html>]

--base starts from the weeks embedded in the published archive page (the shared copy every
device updates) and overwrites archive_weeks.json with them. --add then inserts or replaces
(by weekStart) one week in archive_weeks.json.
"""
import argparse, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
WEEKS = os.path.join(HERE, "archive_weeks.json")
TEMPLATE = os.path.join(HERE, "archive_template.html")
KEYS = ["weekStart", "label", "url", "projectCount", "totalCost", "slices"]

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--add")
ap.add_argument("--base")
a = ap.parse_args()

weeks = json.load(open(WEEKS))
if a.base:
    m = re.search(r'<script type="application/json" id="weeks-data">(.*?)</script>', open(a.base).read(), re.S)
    if not m:
        raise SystemExit(f"{a.base}: no weeks-data block")
    weeks = json.loads(m.group(1))
if a.add:
    new = json.load(open(a.add))
    missing = [k for k in KEYS if k not in new]
    if missing:
        raise SystemExit(f"week is missing {missing}")
    weeks = [w for w in weeks if w["weekStart"] != new["weekStart"]]
    weeks.append({k: new[k] for k in KEYS})
    weeks.sort(key=lambda w: w["weekStart"])
if a.add or a.base:
    with open(WEEKS, "w") as f:
        json.dump(weeks, f, indent=1, ensure_ascii=False)
        f.write("\n")

data = json.dumps(weeks, ensure_ascii=False).replace("</", "<\\/")
html = open(TEMPLATE).read().replace("__WEEKS_JSON__", data)
with open(a.out, "w") as f:
    f.write(html)
print(f"{len(weeks)} weeks -> {a.out}")
