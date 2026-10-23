#!/usr/bin/env python3
"""Builds a report-writer essay: report.md + numbers.json → report.html + 390 px phone cards.

    python3 -I build.py <report dir> [--data <data dir>] [--no-cards] [--md NEEDS-DATA.md --numbers needs-data.json]

<report dir> holds report.md (the essay) and numbers.json (one entry per figure). --data is the directory the
entries' "file" paths are relative to (default: the parent of <report dir>, i.e. the study's data dir when the
report lives in <data dir>/report/). Writes report.html, cards/NN-<slug>.png (2x of 390 css px) and
cards/measure.json, and fills numbers.json: a null "value" is read from its file and field, and every "derived"
value is recomputed from the keys it names (a stored value that disagrees is replaced and reported).

report.md is Markdown with a few extras:
  {key}       a figure from numbers.json → "value unit" (the only way a number may appear in prose)
  {key@}      the same, followed by the run name in grey
  [[gen 7]]   an identifier (generation, round, run index, exit code): plain text, not a figure
  > text      a blockquote; the first one is the user's ask (<q class="ask">)
  ~ text      where the ask was said (the who line), right after the quote
  ::bars k1 k2 … | hi=k7 | labels=g0 g1 … | cap=…   a bar chart whose labels are figure spans
  ::checker loops=N raised=N fixed=N open=N tokens=N seconds=N   the checker line (last line of the report)
  ::checker off                                                 when the checker was skipped
  ---         a forced screenful break
Blocks are packed into <section class="card"> screenfuls of at most PACK css px, measured with cards.mjs (next to
this script); a heading, quote or who line sticks to the block after it. Stdlib only, plus Node + playwright for
the cards (cards.mjs finds playwright; set PLAYWRIGHT_DIR if it cannot).

numbers.json entry: {"label", "value", "unit", "fmt", "run", "file", "field"} or {"label", "unit", "fmt",
"derived": {"op": mean|sum|diff|ratio|pct|pct_change|spread|mul|min|max|count, "of": [keys]}}.
"file" is always a file the study shipped, relative to --data; a file inside the report dir (one the writer made, such
as a tally) is refused, because the reader must be able to check every figure against the study's own files. An
aggregate over rows is written in the field: "[?agent=opus][?status=ok].fe_worker|mean" (filters [?k=v], [?k!=v],
[?k~substring], [?k>n], [?k<n]; aggregates |mean |sum |count |min |max |median |stdev |ci95 |first |last).
--md/--numbers build another Markdown + numbers pair in the same dir (a send-back NEEDS-DATA.md with needs-data.json).
fmt: 2 (two decimals), 0, 1, "int", "," (thousands), "%1" (value is a fraction, printed as a percent with one
decimal). "field": a.b[0].c, [name=x].y, list[-1], [?k=v]...|agg; for a text file, a regex with one capturing group.
"""
import html as H, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = ""   # set by build(); a numbers.json "file" under it is a writer-made data file and is refused
CARDS_MJS = os.path.join(HERE, "cards.mjs")
PACK = 820  # css px of content per screenful (phone viewport 844)


# ---------- source resolution (same rules as agents/evals/report-writer/check.py) ----------------------------------------
def resolve_path(obj, field):
    """a.b[0].c, [name=foo].x (exactly one match), [?name=foo] (every match, a filter), [?case~c9] (contains),
    gens[-1].wall, buckets.* (list of values). A trailing |agg (mean, sum, count, min, max, median, stdev, ci95, first,
    last) reduces a list to one number, so a figure can be a mean over filtered rows of a jsonl file."""
    agg = None
    if "|" in field:
        field, agg = field.rsplit("|", 1)
        agg = agg.strip()
    cur = obj
    for tok in re.findall(r"\[[^\]]+\]|[^.\[\]]+", field.strip()):
        if cur is None:
            return None
        if tok.startswith("["):
            inner = tok[1:-1]
            if inner.startswith("?"):
                if not isinstance(cur, list):
                    raise KeyError(f"filter {tok} on non-list")
                cur = [x for x in cur if _match(x, inner[1:])]
            elif "=" in inner:
                k, v = inner.split("=", 1)
                if not isinstance(cur, list):
                    raise KeyError(f"selector {tok} on non-list")
                m = [x for x in cur if str(x.get(k)) == v]
                if len(m) != 1:
                    raise KeyError(f"selector {tok} matched {len(m)}")
                cur = m[0]
            else:
                cur = cur[int(inner)]
        elif tok == "*":
            cur = list(cur.values()) if isinstance(cur, dict) else list(cur)
        else:
            cur = [c[tok] for c in cur] if isinstance(cur, list) else cur[tok]
    if agg:
        if not isinstance(cur, list):
            raise KeyError(f"|{agg} on a non-list")
        cur = aggregate(agg, cur)
    return cur


def _match(row, cond):
    """k=v (string equality), k!=v, k~v (v in str(k)), k!~v, k>v / k<v (numeric)"""
    m = re.match(r"([^!=~<>]+)(!=|!~|=|~|>|<)(.*)$", cond)
    if not m or not isinstance(row, dict):
        raise KeyError(f"bad filter {cond!r}")
    k, op, v = m.group(1).strip(), m.group(2), m.group(3)
    got = row.get(k)
    s = "" if got is None else str(got)
    if op == "=":
        return s == v
    if op == "!=":
        return s != v
    if op == "~":
        return v in s
    if op == "!~":
        return v not in s
    try:
        return (float(got) > float(v)) if op == ">" else (float(got) < float(v))
    except (TypeError, ValueError):
        return False


def aggregate(agg, xs):
    if agg == "count":
        return len(xs)
    if agg == "first":
        return xs[0] if xs else None
    if agg == "last":
        return xs[-1] if xs else None
    nums = []
    for x in xs:
        if isinstance(x, bool):
            nums.append(int(x))
        elif isinstance(x, (int, float)):
            nums.append(x)
        elif isinstance(x, str):
            try:
                nums.append(float(x.replace(",", "")))
            except ValueError:
                raise KeyError(f"|{agg} over a non-number {x!r}")
        elif x is None:
            raise KeyError(f"|{agg} over a null")
        else:
            raise KeyError(f"|{agg} over {type(x).__name__}")
    if not nums:
        return None
    n = len(nums)
    if agg == "sum":
        return sum(nums)
    if agg == "mean":
        return sum(nums) / n
    if agg == "min":
        return min(nums)
    if agg == "max":
        return max(nums)
    if agg == "median":
        s = sorted(nums)
        return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2
    if agg in ("stdev", "ci95"):
        if n < 2:
            return 0.0
        m = sum(nums) / n
        sd = (sum((x - m) ** 2 for x in nums) / (n - 1)) ** 0.5
        return sd if agg == "stdev" else 1.96 * sd / n ** 0.5
    raise KeyError(f"unknown aggregate |{agg}")


def load_file(root, path, cache={}):
    p = path if os.path.isabs(path) else os.path.join(root, path)
    if p in cache:
        return cache[p]
    if not os.path.exists(p):
        cache[p] = None
        return None
    txt = open(p, encoding="utf-8", errors="replace").read()
    if p.endswith(".json"):
        try:
            cache[p] = ("json", json.loads(txt))
        except ValueError:
            cache[p] = ("text", txt)
    elif p.endswith(".jsonl"):
        cache[p] = ("json", [json.loads(l) for l in txt.splitlines() if l.strip()])
    else:
        cache[p] = ("text", txt)
    return cache[p]


def derive(op, vals):
    if any(v is None for v in vals):
        return None
    if op == "mean":
        return sum(vals) / len(vals)
    if op == "sum":
        return sum(vals)
    if op == "diff":
        return vals[0] - vals[1]
    if op == "ratio":
        return vals[0] / vals[1]
    if op == "pct":
        return vals[0] / vals[1] * 100
    if op == "pct_change":
        return (vals[0] - vals[1]) / vals[1] * 100
    if op == "spread":
        return max(vals) - min(vals)
    if op == "mul":
        return vals[0] * vals[1]
    if op == "min":
        return min(vals)
    if op == "max":
        return max(vals)
    if op == "count":
        return len(vals)
    raise ValueError(f"unknown derived op {op}")


def to_number(v):
    if isinstance(v, bool):
        return int(v)
    if isinstance(v, (int, float)):
        return v
    if isinstance(v, str):
        s = v.replace(",", "").strip().rstrip("%")
        try:
            return float(s)
        except ValueError:
            return v
    return v


def fill_values(N, data):
    """fill null values from their files; recompute every derived value. → list of notes (what changed)"""
    notes = []
    for key, e in N.items():
        if "derived" in e or e.get("value") is not None or not e.get("file"):
            continue
        fp = os.path.realpath(e["file"] if os.path.isabs(e["file"]) else os.path.join(data, e["file"]))
        if fp.startswith(os.path.realpath(OUTDIR) + os.sep) or not fp.startswith(os.path.realpath(data) + os.sep):
            notes.append(f"{key}: file {e['file']} is a writer-made data file (inside the report dir or outside --data); figures come from study files only, use [?k=v]…|mean on the raw file")
            continue
        loaded = load_file(data, e["file"])
        if loaded is None:
            notes.append(f"{key}: file {e['file']} not found")
            continue
        kind, obj = loaded
        try:
            if kind == "json":
                v = to_number(resolve_path(obj, e["field"]))
            else:
                m = re.search(e["field"], obj, re.M)
                v = to_number(m.group(1)) if m else None
        except (KeyError, IndexError, TypeError, ValueError) as ex:
            notes.append(f"{key}: {e['file']} → {e['field']}: {ex}")
            continue
        e["value"] = v
    for _ in range(6):  # derived of derived
        for key, e in N.items():
            d = e.get("derived")
            if not d:
                continue
            vals = [to_number(N[k].get("value")) if k in N else None for k in d.get("of", [])]
            if any(k not in N for k in d.get("of", [])):
                notes.append(f"{key}: derived of unknown key {[k for k in d['of'] if k not in N]}")
                continue
            if any(not isinstance(v, (int, float)) for v in vals):
                continue
            v = derive(d["op"], vals)
            old = e.get("value")
            if old is not None and v is not None and abs(float(old) - v) > 1e-6 * max(1, abs(v)) + 10 ** (-(precision(e) + 1)):
                notes.append(f"{key}: stored {old} replaced by recomputed {v:.6g}")
            e["value"] = v
    return notes


def precision(e):
    f = e.get("fmt", 2)
    if isinstance(f, int):
        return f
    if isinstance(f, str) and f.startswith("%"):
        return int(f[1:] or 0) + 2
    return 0


# ---------- formatting ----------------------------------------------------------------------------------------------------
def fmt_value(e):
    v = e.get("value")
    if v is None:
        return e.get("text", "not measured")
    if isinstance(v, str):
        return v
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


# ---------- markdown subset -----------------------------------------------------------------------------------------------
def inline(text, N, mode, used):
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
        return m.group(1) if mode == "md" else f'<span class="id">{H.escape(m.group(1))}</span>'

    if mode == "html":
        text = H.escape(text, quote=False)
    text = re.sub(r"\{([A-Za-z0-9_]+)(@?)\}", num, text)
    text = re.sub(r"\[\[(.+?)\]\]", ident, text)
    if mode == "html":
        text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", text)
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


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
        elif s.startswith("::checker"):
            flush(); blocks.append(("checker", s[9:].strip()))
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
    opts = dict(p.split("=", 1) for p in parts[1:] if "=" in p)
    labels = opts.get("labels", " ".join(keys)).split()
    while len(labels) < len(keys):
        labels.append("")
    hi = opts.get("hi")
    vals = [float(N[k]["value"]) for k in keys]
    W, Hh, top, bottom = 374, 190, 26, 22
    lo, hi_v = min(0, min(vals)), max(0, max(vals))
    span = (hi_v - lo) or 1
    plot_h = Hh - top - bottom
    y_of = lambda v: top + (hi_v - v) / span * plot_h
    slot = W / len(keys)
    bw = slot * 0.62
    out = [f'<svg class="chart bars" viewBox="0 0 {W} {Hh}" width="{W}" height="{Hh}" role="img" aria-label="{H.escape(opts.get("cap", ""), quote=True)}">']
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
    cap_html = inline(opts.get("cap", ""), N, "html", used)
    return f'<figure class="fig">{"".join(out)}<figcaption>{cap_html}</figcaption></figure>'


def checker_html(spec):
    spec = spec.strip()
    if spec == "off" or spec.startswith("off"):
        return '<p class="checked" id="checked">checker: off</p>'
    kv = dict(p.split("=", 1) for p in spec.split() if "=" in p)
    need = ("loops", "raised", "fixed", "open", "tokens", "seconds")
    missing = [k for k in need if k not in kv]
    if missing:
        raise ValueError(f"::checker line lacks {missing}")
    g = lambda k: int(float(kv[k].replace(",", "")))
    txt = (f"checker: {g('loops')} loop{'s' if g('loops') != 1 else ''}, {g('raised')} raised, {g('fixed')} fixed, {g('open')} open; "
           f"checker tokens {g('tokens'):,}, wall {g('seconds'):,} s")
    return f'<p class="checked" id="checked">{txt}</p>'


def render_blocks(blocks, N):
    """→ list of (kind, html), used keys"""
    out, used, first_quote = [], [], True
    for kind, body in blocks:
        if kind in ("h1", "h2", "p", "who"):
            h = inline(body, N, "html", used)
            if kind == "who":
                out.append((kind, f'<p class="who"><span class="who">{h}</span></p>'))
            elif kind == "p":
                out.append((kind, f"<p>{h}</p>"))
            else:
                out.append((kind, f"<{kind}>{h}</{kind}>"))
        elif kind == "quote":
            h = inline(body, N, "html", used)
            q = f'<q class="ask">{h}</q>' if first_quote else h
            first_quote = False
            out.append((kind, f"<blockquote>{q}</blockquote>"))
        elif kind == "ul":
            out.append((kind, "<ul>" + "".join(f"<li>{inline(it, N, 'html', used)}</li>" for it in body) + "</ul>"))
        elif kind == "bars":
            out.append((kind, bars_svg(body, N, used)))
        elif kind == "checker":
            out.append((kind, checker_html(body)))
        elif kind == "break":
            out.append((kind, ""))
    return out, used


CSS = """
:root{--ink:#1b1b1b;--muted:#5d5d5d;--line:#d9d9d9;--bg:#fff;--acc:#1f5fa8}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.4 -apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.emoji{font-family:"Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",sans-serif;line-height:1}
main{max-width:860px;margin:0 auto;padding:12px 16px}
body[data-mode=phone] main{max-width:390px;padding:0}
.card{padding:12px 8px;border-bottom:2px solid var(--line)}
.card:last-child{border-bottom:0}
h1{font-size:21px;line-height:1.25;margin:6px 0 10px}
h2{font-size:17.5px;line-height:1.3;margin:4px 0 6px}
p{margin:8px 0;line-height:1.45}
blockquote{margin:8px 0;padding:6px 10px;border-left:4px solid #bbb;background:#f7f7f7;border-radius:0 6px 6px 0}
blockquote q{quotes:"\\201C" "\\201D";font-style:italic}
p.who{margin:2px 0 8px;color:var(--muted);font-size:13.5px}
ul{margin:6px 0;padding-left:20px}
li{margin:3px 0;line-height:1.4}
code{font-size:0.9em;background:#f2f2f2;padding:0 3px;border-radius:3px}
.n{font-variant-numeric:tabular-nums;font-weight:600}
.src{color:var(--muted);font-size:0.85em}
.fig{margin:10px 0 4px}
figcaption{font-size:13.5px;line-height:1.3;color:var(--muted);margin-top:4px}
svg.chart{display:block;max-width:100%;height:auto}
svg .axis{stroke:#888;stroke-width:1}
svg .bar{fill:#9db7d6}svg .bar.hi{fill:#1f5fa8}
svg .val{font-size:10.5px;fill:var(--ink)}svg .lab{font-size:10.5px;fill:var(--muted)}
p.checked{color:var(--muted);font-size:13px;margin-top:10px}
"""


def page_html(cards, title):
    body = [f'<section class="card" id="{cid}">' + "".join(h for _, h in items) + "</section>" for cid, items in cards]
    body = [b.replace("<p>📚 ", '<p><span class="emoji">📚</span> ') for b in body]   # the books glyph needs an emoji font; scoped so line heights stay put
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">\n'
            f'<title>{H.escape(title)}</title><style>{CSS}</style></head><body data-mode="phone"><main class="prose">\n'
            + "\n".join(body) + "\n</main></body></html>\n")


def slug(items, n):
    for kind, h in items:
        if kind in ("h1", "h2"):
            s = re.sub(r"[^a-z0-9]+", "-", re.sub(r"<[^>]+>", "", h).lower()).strip("-")
            return s[:28].rstrip("-") or f"part-{n}"
    return f"part-{n}"


def measure(outdir, mode, html="report.html"):
    r = subprocess.run(["node", CARDS_MJS, outdir, mode, html], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"cards.mjs failed: {r.stderr.strip()}")
    return json.load(open(os.path.join(outdir, "cards", "measure.json"))), r.stdout.strip()


def build(outdir, data, cards=True, md="report.md", numbers="numbers.json"):
    global OUTDIR
    OUTDIR = outdir
    src_path, np_ = os.path.join(outdir, md), os.path.join(outdir, numbers)
    html = "report.html" if md == "report.md" else os.path.splitext(md)[0] + ".html"   # NEEDS-DATA.md → NEEDS-DATA.html
    if not os.path.exists(src_path):
        sys.exit(f"build.py: no {src_path}")
    if not os.path.exists(np_):
        sys.exit(f"build.py: no {np_}")
    src = open(src_path, encoding="utf-8").read()
    N = json.load(open(np_, encoding="utf-8"))
    notes = fill_values(N, data)
    for n in notes:
        print(f"numbers: {n}")
    json.dump(N, open(np_, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    blocks = parse(src)
    try:
        items, used = render_blocks(blocks, N)
    except KeyError as ex:
        sys.exit(f"build.py: {ex}")
    unused = sorted(set(N) - set(used) - {k for u in used for k in N[u].get("derived", {}).get("of", [])})
    title = next((re.sub(r"<[^>]+>", "", h) for k, h in items if k == "h1"), os.path.basename(os.path.dirname(outdir) or outdir))
    if not cards:
        groups = [[it for it in items if it[0] != "break"]]
    else:
        singles = [(f"b{i:02d}", [it]) for i, it in enumerate(items) if it[0] != "break"]
        open(os.path.join(outdir, html), "w", encoding="utf-8").write(page_html(singles, title))
        m1, _ = measure(outdir, "desktop", html)
        h = {c["slug"]: c["css_height_px"] - 26 for c in m1["cards"]}
        groups, cur, cur_h = [], [], 0
        for i, it in enumerate(items):
            if it[0] == "break":
                if cur:
                    groups.append(cur); cur, cur_h = [], 0
                continue
            bh = h[f"b{i:02d}"]
            if cur and cur_h + bh > PACK:
                tail = []
                while cur and cur[-1][0] in ("h1", "h2", "quote", "who"):
                    tail.insert(0, cur.pop())
                if cur:
                    groups.append(cur)
                cur, cur_h = tail, sum(h[f"b{items.index(t):02d}"] for t in tail)
            cur.append(it); cur_h += bh
        if cur:
            groups.append(cur)
    named = [(slug(c, n + 1), c) for n, c in enumerate(groups)]
    seen = {}
    for n, (s, c) in enumerate(named):
        if s in seen:
            named[n] = (f"{s}-{seen[s] + 1}", c)
        seen[s] = seen.get(s, 0) + 1
    open(os.path.join(outdir, html), "w", encoding="utf-8").write(page_html(named, title))
    if md == "report.md":   # a send-back (--md NEEDS-DATA.md) has no checker folder
        ck = os.path.join(outdir, "checker")
        os.makedirs(ck, exist_ok=True)   # the checker's folder is one of the run's outputs even when the checker was skipped
        spec = next((b for k, b in blocks if k == "checker"), "")
        if spec.strip().startswith("off") and not os.listdir(ck):
            open(os.path.join(ck, "OFF.txt"), "w").write("checker: off (built with --no-checker)\n")
    if not cards:
        print(f"build: {len(named)} card(s), {len(set(used))} figures used of {len(N)}; no cards (--no-cards)")
        return
    m2, summary = measure(outdir, "phone", html)
    heights = ", ".join(f"{c['slug']} {c['css_height_px']}" for c in m2["cards"])
    print(f"build: {len(named)} cards ({heights}); {len(set(used))} figures used of {len(N)}"
          + (f"; unused keys: {', '.join(unused[:12])}{' …' if len(unused) > 12 else ''}" if unused else "") + f"; {summary}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0].startswith("-"):
        sys.exit(__doc__)
    outdir = os.path.abspath(a[0])
    data = os.path.abspath(a[a.index("--data") + 1]) if "--data" in a else os.path.dirname(outdir)
    md = a[a.index("--md") + 1] if "--md" in a else "report.md"
    numbers = a[a.index("--numbers") + 1] if "--numbers" in a else "numbers.json"
    build(outdir, data, cards="--no-cards" not in a, md=md, numbers=numbers)
