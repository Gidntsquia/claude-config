#!/usr/bin/env python3
"""Build the Roundup Archive page from archive_weeks.json.

  build_archive.py --out <page.html> [--add <week.json> [--days-from <gather output.json>]]
                   [--base <published archive.html>]

--base starts from the weeks embedded in the published archive page (the shared copy every
device updates) and overwrites archive_weeks.json with them. --add then inserts or replaces
(by weekStart) one week in archive_weeks.json. The added week must carry `days` (gather_data.py's
per-day usage); --days-from copies it from the run's output when the week file lacks it. Older
entries without `days` are kept as they are; the "Usage by day" chart shows them as empty weeks.
The chart is drawn here (daychart.py, next to this file), so any machine rebuilds the page
identically from --base.
"""
import argparse, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
WEEKS = os.path.join(HERE, "archive_weeks.json")
TEMPLATE = os.path.join(HERE, "archive_template.html")
sys.path.insert(0, HERE)
import daychart  # noqa: E402

KEYS = ["weekStart", "label", "url", "projectCount", "totalCost", "slices", "days"]

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--add")
ap.add_argument("--base")
ap.add_argument("--days-from", help="gather_data.py output JSON; its `days` fills the added week's when missing")
a = ap.parse_args()

weeks = json.load(open(WEEKS, encoding="utf8"))
if a.base:
    m = re.search(r'<script type="application/json" id="weeks-data">(.*?)</script>', open(a.base, encoding="utf8").read(), re.S)
    if not m:
        raise SystemExit(f"{a.base}: no weeks-data block")
    weeks = json.loads(m.group(1))
if a.add:
    new = json.load(open(a.add, encoding="utf8"))
    if "days" not in new and a.days_from:
        new["days"] = json.load(open(a.days_from, encoding="utf8"))["days"]
    missing = [k for k in KEYS if k not in new]
    if missing:
        raise SystemExit(f"week is missing {missing}")
    weeks = [w for w in weeks if w["weekStart"] != new["weekStart"]]
    weeks.append({k: new[k] for k in KEYS})
    weeks.sort(key=lambda w: w["weekStart"])
if a.add or a.base:
    with open(WEEKS, "w", encoding="utf8") as f:
        json.dump(weeks, f, indent=1, ensure_ascii=False)
        f.write("\n")

data = json.dumps(weeks, ensure_ascii=False).replace("</", "<\\/")
html = (open(TEMPLATE, encoding="utf8").read().replace("__DAYCHART_CSS__", daychart.CSS)
        .replace("__DAYCHART__", daychart.archive_html(weeks)).replace("__WEEKS_JSON__", data))
with open(a.out, "w", encoding="utf8") as f:
    f.write(html)
print(f"{len(weeks)} weeks -> {a.out}")
