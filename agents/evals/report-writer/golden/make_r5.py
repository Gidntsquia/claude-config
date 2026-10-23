#!/usr/bin/env python3
"""Golden round 5: two hand-written prose reports on the fixture study, built from golden/r5/<X>/source.md.

  python3 make_r5.py [A B]      → golden/r5/<X>/{numbers.json, report.md, report.html, cards/NN-*.png, cards/measure.json}

source.md is Markdown with a few extras:
  {key}       a figure from NUMBERS (below) or the build's numbers.json → "value unit" in report.md,
              <span class="n" data-key> in report.html (check.py verifies it against the fixture)
  {key@}      the same, followed by the run name in grey
  [[gen 7]]   an identifier (gen, round, run index): plain text, not a figure (check.py --prose skips it)
  > text      a blockquote; the first one is the user's ask (<q class="ask">)
  ~ text      where the ask was said (<span class="who">)
  ::bars k1 k2 … | hi=k7 | labels=g0 g1 … | cap=…   a bar chart whose labels are figure spans
  ---         a forced screenful break
Blocks are packed into <section class="card"> screenfuls of at most PACK css px, measured with cards.mjs
(the repo's phone renderer); report.html then gets one PNG per card at 390 css px, 2x.
"""
import html as H, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RW = os.path.dirname(HERE)                                   # agents/evals/report-writer
BUILD = os.path.join(RW, "out", "build", "report")
CARDS_MJS = os.path.join(BUILD, "cards.mjs")
PACK = 820  # css px of content per screenful (phone viewport 844)

# ---------- figures used by the prose reports, on top of the build's numbers.json ---------------------------------------
def _gw(arm, i, g, label_arm):
    return {"label": f"gen {g} wall, r9pre-ab-{arm}-{i}", "value": None, "unit": "s", "fmt": 2, "run": f"r9pre-ab-{arm}-{i}",
            "file": "runs-all.json", "field": f"[name=r9pre-ab-{arm}-{i}].genWalls[{g}]"}

NUMBERS = {}
for i in (1, 2, 3):
    for g in range(10):
        NUMBERS[f"gw_def{i}_g{g}"] = _gw("default", i, g, "default")
        NUMBERS[f"gw_tail{i}_g{g}"] = _gw("tail", i, g, "tail")
        NUMBERS[f"gd{i}_g{g}"] = {"label": f"gen {g} tail minus default, pair {i}", "value": None, "unit": "s", "fmt": 2, "signed": True,
                                  "run": f"r9pre-ab-tail-{i} vs r9pre-ab-default-{i}", "derived": {"op": "diff", "of": [f"gw_tail{i}_g{g}", f"gw_def{i}_g{g}"]}}
    for arm, lab in (("default", "default"), ("tail", "tail speculation")):
        NUMBERS[f"ts_{arm}{i}"] = {"label": f"{lab} tail share r9pre-ab-{arm}-{i}", "value": None, "fmt": "%1", "run": f"r9pre-ab-{arm}-{i}",
                                   "file": "runs-all.json", "field": f"[name=r9pre-ab-{arm}-{i}].tailShare"}
    for f in ("pool", "speculated", "kept", "discarded", "served"):
        NUMBERS[f"tl{i}_{f}"] = {"label": f"tail log {f}, r9pre-ab-tail-{i}", "value": None, "unit": "",
                                 "fmt": ",", "run": f"r9pre-ab-tail-{i}", "file": "runs-all.json", "field": f"[name=r9pre-ab-tail-{i}].tailLog.{f}"}
    NUMBERS[f"tl{i}_discard_pct"] = {"label": f"share of speculated battles discarded, r9pre-ab-tail-{i}", "value": None, "unit": "%", "fmt": 0,
                                     "run": f"r9pre-ab-tail-{i}", "derived": {"op": "pct", "of": [f"tl{i}_discarded", f"tl{i}_speculated"]}}
    NUMBERS[f"tl{i}_served_pct"] = {"label": f"share of the pool served from speculation, r9pre-ab-tail-{i}", "value": None, "unit": "%", "fmt": 0,
                                    "run": f"r9pre-ab-tail-{i}", "derived": {"op": "pct", "of": [f"tl{i}_served", f"tl{i}_pool"]}}
    NUMBERS[f"tail_s_def{i}_g7"] = {"label": f"about-tail seconds in gen 7 of r9pre-ab-default-{i} (run share × gen wall)", "value": None, "unit": "s", "fmt": 1,
                                    "run": f"r9pre-ab-default-{i}", "derived": {"op": "mul", "of": [f"ts_default{i}", f"gw_def{i}_g7"]}}
for arm, run in (("def", "r9-ab-default-1"), ("tail", "r9-ab-tail-1")):
    for b in ("kernel", "tail"):
        NUMBERS[f"pf_{arm}_g7_{b}"] = {"label": f"gen 7 {b} seconds, {run} (gpu-profile)", "value": None, "unit": "s", "fmt": 2, "run": run,
                                       "file": f"runs/{run}/gpu-profile.json", "field": f"generations[7].buckets.{b}"}
    NUMBERS[f"pf_{arm}_g7_wall"] = {"label": f"gen 7 wall, {run} (gpu-profile)", "value": None, "unit": "s", "fmt": 2, "run": run,
                                    "file": f"runs/{run}/gpu-profile.json", "field": "generations[7].wall"}
NUMBERS["ts_r9tail_runsall"] = {"label": "r9-ab-tail-1 tail share (runs-all)", "value": None, "fmt": "%1", "run": "r9-ab-tail-1",
                                "file": "runs-all.json", "field": "[name=r9-ab-tail-1].tailShare"}
NUMBERS["tl_r9tail_discarded"] = {"label": "tail log discarded, r9-ab-tail-1", "value": None, "unit": "battles", "fmt": ",", "run": "r9-ab-tail-1",
                                  "file": "runs-all.json", "field": "[name=r9-ab-tail-1].tailLog.discarded"}
NUMBERS["tl_r9tail_speculated"] = {"label": "tail log speculated, r9-ab-tail-1", "value": None, "unit": "battles", "fmt": ",", "run": "r9-ab-tail-1",
                                   "file": "runs-all.json", "field": "[name=r9-ab-tail-1].tailLog.speculated"}
NUMBERS["gw_r9def_g7"] = {"label": "gen 7 wall, r9-ab-default-1", "value": None, "unit": "s", "fmt": 2, "run": "r9-ab-default-1",
                          "file": "runs-all.json", "field": "[name=r9-ab-default-1].genWalls[7]"}
NUMBERS["gw_r9tail_g7"] = {"label": "gen 7 wall, r9-ab-tail-1", "value": None, "unit": "s", "fmt": 2, "run": "r9-ab-tail-1",
                           "file": "runs-all.json", "field": "[name=r9-ab-tail-1].genWalls[7]"}
NUMBERS["fulltail_pre_total"] = {"label": "r9pre-full-tail wall before exit 1", "value": None, "unit": "s", "fmt": 0, "run": "r9pre-full-tail",
                                 "file": "runs-all.json", "field": "[name=r9pre-full-tail].total"}

NUMBERS["w_fulltail_pre"] = {"label": "r9pre-full-tail warm s/gen (died at gen 80 of 100)", "value": None, "unit": "s", "fmt": 2, "run": "r9pre-full-tail",
                             "file": "runs-all.json", "field": "[name=r9pre-full-tail].warmPerGen"}
NUMBERS["w_full100_def"] = {"label": "r9-full-default warm s/gen (100 gens)", "value": None, "unit": "s", "fmt": 2, "run": "r9-full-default",
                            "file": "runs-all.json", "field": "[name=r9-full-default].warmPerGen"}
NUMBERS["gw_fulltail_pre_g79"] = {"label": "gen 79 wall, r9pre-full-tail", "value": None, "unit": "s", "fmt": 1, "run": "r9pre-full-tail",
                                  "file": "runs-all.json", "field": "[name=r9pre-full-tail].genWalls[79]"}
NUMBERS["gw_fulltail_pre_g7"] = {"label": "gen 7 wall, r9pre-full-tail", "value": None, "unit": "s", "fmt": 1, "run": "r9pre-full-tail",
                                 "file": "runs-all.json", "field": "[name=r9pre-full-tail].genWalls[7]"}
NUMBERS["gw_full100def_g79"] = {"label": "gen 79 wall, r9-full-default", "value": None, "unit": "s", "fmt": 1, "run": "r9-full-default",
                                "file": "runs-all.json", "field": "[name=r9-full-default].genWalls[79]"}
NUMBERS["gw_fullcert_pre_g64"] = {"label": "gen 64 wall, r9pre-full-certain", "value": None, "unit": "s", "fmt": 1, "run": "r9pre-full-certain",
                                  "file": "runs-all.json", "field": "[name=r9pre-full-certain].genWalls[64]"}
NUMBERS["full100_def_gens"] = {"label": "r9-full-default generations planned and done", "value": None, "fmt": "int", "run": "r9-full-default",
                               "file": "runs-all.json", "field": "[name=r9-full-default].gens"}


def fill_values(N, data):
    """compute every value from the fixture the same way check.py will verify it"""
    sys.path.insert(0, RW)
    import check  # noqa  (check.py: load_file, resolve_path, derive)
    for key, e in N.items():
        if e.get("value") is not None or "derived" in e:
            continue
        if not e.get("file"):
            continue
        kind, obj = check.load_file(data, e["file"])
        if kind == "json":
            e["value"] = check.resolve_path(obj, e["field"])
        else:
            m = re.search(e["field"], obj, re.M)
            e["value"] = float(m.group(1))
    for _ in range(4):  # derived of derived
        for key, e in N.items():
            d = e.get("derived")
            if not d or e.get("value") is not None:
                continue
            vals = [N[k]["value"] for k in d["of"]]
            if any(v is None for v in vals):
                continue
            e["value"] = check.derive(d["op"], vals, N)


def fmt_value(e):
    v = e.get("value")
    if v is None:
        return e.get("text", "not measured")
    f = e.get("fmt", 2)
    if f == "," or f == "int":
        s = f"{round(v):,}" if f == "," else f"{round(v)}"
    elif isinstance(f, str) and f.startswith("%"):
        s = f"{v * 100:.{int(f[1:] or 0)}f}"
    else:
        s = f"{v:.{int(f)}f}"
    if e.get("signed") and v > 0 and not s.startswith("+"):
        s = "+" + s
    return s.replace("-", "−", 1) if s.startswith("-") else s


def unit_of(e):
    f = e.get("fmt", 2)
    return "%" if isinstance(f, str) and f.startswith("%") else e.get("unit", "")


def text_value(e):
    u = unit_of(e)
    return fmt_value(e) + ("" if not u else ("%" if u == "%" else " " + u))


# ---------- markdown subset ----------------------------------------------------------------------------------------------
INLINE_MD = [
    (re.compile(r"\{([A-Za-z0-9_]+)(@?)\}"), None),  # handled separately
]


def inline(text, N, mode):
    """mode 'md' → plain text with values; mode 'html' → spans"""
    used = []

    def num(m):
        key, at = m.group(1), m.group(2)
        if key not in N:
            raise KeyError(f"unknown figure {{{key}}}")
        e = N[key]
        used.append(key)
        if mode == "md":
            return text_value(e) + (f" ({e.get('run')})" if at else "")
        s = f'<span class="n" data-key="{key}">{H.escape(text_value(e))}</span>'
        if at:
            s += f' <span class="src">({H.escape(str(e.get("run", "")))})</span>'
        return s

    def ident(m):
        return m.group(1) if mode == "md" else f'<span class="id">{m.group(1)}</span>'

    if mode == "html":
        text = H.escape(text, quote=False)
    text = re.sub(r"\{([A-Za-z0-9_]+)(@?)\}", num, text)
    text = re.sub(r"\[\[(.+?)\]\]", ident, text)
    if mode == "html":
        text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", text)
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text, used


def parse(src):
    blocks, para = [], []

    def flush():
        if para:
            blocks.append(("p", " ".join(para)))
            para.clear()

    for line in src.splitlines():
        s = line.rstrip()
        if not s.strip():
            flush()
            continue
        if s.startswith("# "):
            flush(); blocks.append(("h1", s[2:].strip()))
        elif s.startswith("## "):
            flush(); blocks.append(("h2", s[3:].strip()))
        elif s.startswith("> "):
            flush()
            if blocks and blocks[-1][0] == "quote":
                blocks[-1] = ("quote", blocks[-1][1] + " " + s[2:].strip())
            else:
                blocks.append(("quote", s[2:].strip()))
        elif s.startswith("~ "):
            flush(); blocks.append(("who", s[2:].strip()))
        elif s.startswith("::bars "):
            flush(); blocks.append(("bars", s[7:].strip()))
        elif s.strip() == "---":
            flush(); blocks.append(("break", ""))
        elif s.startswith("- "):
            flush()
            if blocks and blocks[-1][0] == "ul":
                blocks[-1][1].append(s[2:].strip())
            else:
                blocks.append(("ul", [s[2:].strip()]))
        else:
            para.append(s.strip())
    flush()
    return blocks


def bars_svg(spec, N, used):
    parts = [p.strip() for p in spec.split("|")]
    keys = parts[0].split()
    opts = dict(p.split("=", 1) for p in parts[1:])
    labels = opts.get("labels", " ".join(keys)).split()
    hi = opts.get("hi")
    vals = [N[k]["value"] for k in keys]
    W, Hh, top, bottom = 374, 190, 26, 22
    lo, hi_v = min(0, min(vals)), max(0, max(vals))
    span = (hi_v - lo) or 1
    plot_h = Hh - top - bottom
    y_of = lambda v: top + (hi_v - v) / span * plot_h
    slot = W / len(keys)
    bw = slot * 0.62
    out = [f'<svg class="chart bars" viewBox="0 0 {W} {Hh}" width="{W}" height="{Hh}" role="img" aria-label="{H.escape(opts.get("cap", ""))}">']
    y0 = y_of(0)
    out.append(f'<line class="axis" x1="0" y1="{y0:.1f}" x2="{W}" y2="{y0:.1f}"/>')
    for i, (k, v) in enumerate(zip(keys, vals)):
        x = i * slot + (slot - bw) / 2
        y1, y2 = sorted((y_of(v), y0))
        cls = "bar hi" if k == hi else "bar"
        out.append(f'<rect class="{cls}" x="{x:.1f}" y="{y1:.1f}" width="{bw:.1f}" height="{max(1, y2 - y1):.1f}"/>')
        ty = y1 - 4 if v >= 0 else y2 + 11
        used.append(k)
        out.append(f'<text class="val" x="{x + bw / 2:.1f}" y="{ty:.1f}" text-anchor="middle"><tspan class="n" data-key="{k}">{H.escape(fmt_value(N[k]))}</tspan></text>')
        out.append(f'<text class="lab" x="{x + bw / 2:.1f}" y="{Hh - 6}" text-anchor="middle">{H.escape(labels[i])}</text>')
    out.append("</svg>")
    cap = opts.get("cap", "")
    cap_html, u2 = inline(cap, N, "html")
    used.extend(u2)
    return f'<figure class="fig">{"".join(out)}<figcaption>{cap_html}</figcaption></figure>', cap


def render_blocks(blocks, N):
    """→ (list of (kind, html, md)), used keys"""
    out, used, first_quote = [], [], True
    for kind, body in blocks:
        if kind in ("h1", "h2", "p", "who"):
            h, u = inline(body, N, "html"); m, _ = inline(body, N, "md"); used += u
            if kind == "who":
                out.append((kind, f'<p class="who"><span class="who">{h}</span></p>', f"<sub>{m}</sub>"))
            elif kind == "p":
                out.append((kind, f"<p>{h}</p>", m))
            else:
                out.append((kind, f"<{kind}>{h}</{kind}>", ("# " if kind == "h1" else "## ") + m))
        elif kind == "quote":
            h, u = inline(body, N, "html"); m, _ = inline(body, N, "md"); used += u
            q = f'<q class="ask">{h}</q>' if first_quote else h
            first_quote = False
            out.append((kind, f"<blockquote>{q}</blockquote>", "> " + m))
        elif kind == "ul":
            hs, ms = [], []
            for it in body:
                h, u = inline(it, N, "html"); m, _ = inline(it, N, "md"); used += u
                hs.append(f"<li>{h}</li>"); ms.append("- " + m)
            out.append((kind, "<ul>" + "".join(hs) + "</ul>", "\n".join(ms)))
        elif kind == "bars":
            fig, cap = bars_svg(body, N, used)
            keys = body.split("|")[0].split()
            md = "(chart: " + ", ".join(f"{N[k]['label']} {text_value(N[k])}" for k in keys) + ")\n\n" + inline(cap, N, "md")[0]
            out.append((kind, fig, md))
        elif kind == "break":
            out.append((kind, "", ""))
    return out, used


def css():
    src = open(os.path.join(BUILD, "render.py"), encoding="utf-8").read()
    base = re.search(r'^CSS = """(.*?)"""', src, re.S | re.M).group(1)
    return base + """
main.prose h1{font-size:21px;line-height:1.25;margin:6px 0 10px}
main.prose h2{font-size:17.5px;line-height:1.3;margin:4px 0 6px}
main.prose p{margin:8px 0;line-height:1.45}
main.prose blockquote{margin:8px 0;padding:6px 10px;border-left:4px solid #bbb;background:#f7f7f7;border-radius:0 6px 6px 0}
main.prose blockquote q{quotes:"“" "”";font-style:italic}
main.prose p.who{margin:2px 0 8px;color:var(--muted);font-size:13.5px}
main.prose ul{margin:6px 0;padding-left:20px}
main.prose li{margin:3px 0;line-height:1.4}
main.prose code{font-size:0.9em;background:#f2f2f2;padding:0 3px;border-radius:3px}
main.prose .fig{margin:10px 0 4px}
main.prose figcaption{font-size:13.5px;line-height:1.3;color:var(--muted);margin-top:4px}
main.prose svg .bar{fill:#9db7d6}main.prose svg .bar.hi{fill:#1f5fa8}
main.prose svg .val{font-size:10.5px}main.prose svg .lab{font-size:10.5px;fill:var(--muted)}
main.prose .card{padding:12px 8px}
main.prose .card:last-child{border-bottom:0}
"""


def page_html(cards, title):
    body = []
    for cid, items in cards:
        body.append(f'<section class="card" id="{cid}">' + "".join(h for _, h, _ in items) + "</section>")
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{H.escape(title)}</title><style>{css()}</style></head><body data-mode="phone"><main class="prose">
{chr(10).join(body)}
</main></body></html>
"""


def slug(items, n):
    for kind, _, md in items:
        if kind in ("h1", "h2"):
            s = re.sub(r"[^a-z0-9]+", "-", md.lstrip("# ").lower()).strip("-")
            return s[:28].rstrip("-") or f"part-{n}"
    return f"part-{n}"


def measure(outdir, mode):
    r = subprocess.run(["node", CARDS_MJS, outdir, mode], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"cards.mjs failed: {r.stderr}")
    return json.load(open(os.path.join(outdir, "cards", "measure.json"))), r.stdout.strip()


def build(name):
    outdir = os.path.join(HERE, "r5", name)
    src = open(os.path.join(outdir, "source.md"), encoding="utf-8").read()
    data = os.path.join(RW, "fixture", "data")
    base = json.load(open(os.path.join(BUILD, "numbers.json")))
    N = {**base, **NUMBERS}
    fill_values(N, data)
    blocks = parse(src)
    items, used = render_blocks(blocks, N)
    title = next((md.lstrip("# ") for k, _, md in items if k == "h1"), name)
    # pass 1: every block its own card, to measure it
    singles = [(f"b{i:02d}", [it]) for i, it in enumerate(items) if it[0] != "break"]
    open(os.path.join(outdir, "report.html"), "w", encoding="utf-8").write(page_html(singles, title))
    m1, _ = measure(outdir, "desktop")
    h = {c["slug"]: c["css_height_px"] - 26 for c in m1["cards"]}  # minus the card's own padding+border
    # pack: fill screenfuls of PACK; a heading, quote or who line sticks to what follows; a forced break ends a card
    cards, cur, cur_h = [], [], 0
    for i, it in enumerate(items):
        if it[0] == "break":
            if cur:
                cards.append(cur); cur, cur_h = [], 0
            continue
        bh = h[f"b{i:02d}"]
        if cur and cur_h + bh > PACK:
            # move a trailing heading/quote/who into the new card
            tail = []
            while cur and cur[-1][0] in ("h1", "h2", "quote", "who"):
                tail.insert(0, cur.pop())
            if cur:
                cards.append(cur)
            cur, cur_h = tail, sum(h[f"b{items.index(t):02d}"] for t in tail)
        cur.append(it); cur_h += bh
    if cur:
        cards.append(cur)
    named = [(f"{slug(c, n + 1)}", c) for n, c in enumerate(cards)]
    seen = {}
    for n, (s, c) in enumerate(named):  # unique ids
        if s in seen:
            named[n] = (f"{s}-{seen[s] + 1}", c)
        seen[s] = seen.get(s, 0) + 1
    open(os.path.join(outdir, "report.html"), "w", encoding="utf-8").write(page_html(named, title))
    # report.md
    md = []
    for _, c in named:
        md.append("\n\n".join(m for _, _, m in c))
    open(os.path.join(outdir, "report.md"), "w", encoding="utf-8").write("\n\n".join(md) + "\n")
    # numbers.json: only the figures on the page (plus what they derive from)
    keep = set(used)
    for _ in range(4):
        for k in list(keep):
            keep |= set(N[k].get("derived", {}).get("of", []))
    json.dump({k: N[k] for k in N if k in keep}, open(os.path.join(outdir, "numbers.json"), "w"), indent=1, ensure_ascii=False)
    m2, summary = measure(outdir, "phone")
    heights = ", ".join(f"{c['slug']} {c['css_height_px']}" for c in m2["cards"])
    print(f"{name}: {len(named)} cards ({heights}); {len(keep)} figures; {summary}")


if __name__ == "__main__":
    for name in (sys.argv[1:] or ["A", "B"]):
        build(name)
