#!/usr/bin/env python3
"""Embed (or replace) the pooled week data in a roundup page.

  embed_pool.py --pool <pool.json> --html <page.html>

Writes it as <script type="application/json" id="roundup-data"> just before </body>, so the
next device's gather_data.py --pool-in <page.html> can merge into it.
"""
import argparse, json, re

ap = argparse.ArgumentParser()
ap.add_argument("--pool", required=True)
ap.add_argument("--html", required=True)
ap.add_argument("--hostname", help="this machine's hostname; records it as author of what follows")
ap.add_argument("--wrote-projects", default="", help="comma-separated project names whose card (paragraph, picture, card-meta) this run wrote")
ap.add_argument("--wrote-fixed", default="", help="comma-separated ids of the Things-fixed entries this run wrote")
a = ap.parse_args()

pool = json.load(open(a.pool))
auth = pool.setdefault("authored", {"projects": {}, "fixed": {}})
auth.setdefault("projects", {}); auth.setdefault("fixed", {})
if a.hostname:
    for n in filter(None, a.wrote_projects.split(",")):
        auth["projects"][n.strip()] = a.hostname
    for i in filter(None, a.wrote_fixed.split(",")):
        auth["fixed"][i.strip()] = a.hostname
data = json.dumps(pool, separators=(",", ":"), ensure_ascii=False).replace("</", "<\\/")
block = f'<script type="application/json" id="roundup-data">{data}</script>'
html = open(a.html).read()
pat = re.compile(r'<script type="application/json" id="roundup-data">.*?</script>', re.S)
if pat.search(html):
    html = pat.sub(lambda _: block, html)
elif "</body>" in html:
    html = html.replace("</body>", block + "\n</body>", 1)
else:
    html += "\n" + block + "\n"
open(a.html, "w").write(html)
print(f"embedded {len(data) // 1024} KB of pool data -> {a.html}")
