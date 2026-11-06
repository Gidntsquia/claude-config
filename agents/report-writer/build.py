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
  ::table h1 | h2 | … ;; {k} | {k} | … ;; … | cap=…   a phone-width table: header cells are words, body cells are
              {key}s, [[id]]s or words (a row's label), one row per ";;"; first column left, figure columns right; a
              column whose keys share a unit prints it once in the header; a digit typed in a cell is a build error;
              a table taller than one card is split across cards with its header repeated
  ::split total | k1 k2 … | labels=a b … | cap=…   one stacked bar for the figure `total`, a segment per key sized by
              its value, each with its label and value; the segments must sum to within 1% of `total` (build error)
  ::pair left=k1 k2 … right=k3 k4 … | labels=A B | id=… | rows=r1 r2 … | cap=…   the same unit under two arms, two
              cards side by side; each lists its keys with a label (rows=, else numbers.json "label") and value, under
              the unit's [[id]] (id=) and the arm label. For the "But" paragraph and again in the ending.
              In labels=/rows= a "_" stands for a space.
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
Ledger: a full build of report.md (not --no-cards, not --md) replaces this <report dir>'s line in
agents/evals/report-writer/ledger.jsonl (or $REPORT_LEDGER) and appends it last: {"ts", "out", "form", "title_shape",
"first_sentence_sha1"}. "form" is the opening form named on NOTES.md's "## Openings" line "pick: <form>" (moment,
log-line, break, expected-vs-got, person); "title_shape" is the title with figures as N and nouns as _ ("The _ that
cost a _"); check.py's opening_ledger fails a form or title shape equal to either of the two entries before it.
Focus: cards/measure.json gets "words": [{"section", "words"}], one entry per section (the # title's opening card, then
every ## section), counting prose only: block lines (::…), the quote, the who line, headings and the sources line are left
out, a {key} is one word. check.py's focus group (outline_present, outline_match, outline_budget, unasked_once,
focus_findings) compares these to the budgets in the writer's outline.md (| # | heading | ask clause | settles with |
words |) and reads ## Recap and ## Left out there. A --no-cards build updates "words" in an existing measure.json.
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
        elif s.startswith(("::table ", "::split ", "::pair ")):
            flush(); kw = s[2:].split(" ", 1)[0]; blocks.append((kw, s[len(kw) + 3:].strip()))
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


class BuildError(Exception):
    pass


DIGIT_RE = re.compile(r"\d")


def _bare(text):
    """what is left of a cell once its {key}s and [[id]]s are removed"""
    return re.sub(r"\[\[.+?\]\]", " ", re.sub(r"\{[A-Za-z0-9_]+@?\}", " ", text))


def _opts(parts):
    return dict(p.split("=", 1) for p in parts if "=" in p and re.match(r"^\w+=", p))


def _words(s):
    return [w.replace("_", " ") for w in s.split()]


def _keys_in(cell):
    return re.findall(r"\{([A-Za-z0-9_]+)@?\}", cell)


def parse_table(spec):
    """→ header cells, body rows (lists of cell strings), caption"""
    rows = [r.strip() for r in spec.split(";;")]
    cap = ""
    last = [c.strip() for c in rows[-1].split("|")]
    caps = [c for c in last if c.startswith("cap=")]
    if caps:
        cap = caps[0][4:].strip()
        rows[-1] = " | ".join(c for c in last if not c.startswith("cap="))
    cells = [[c.strip() for c in r.split("|")] for r in rows if r.strip()]
    if len(cells) < 2:
        raise BuildError(f"::table needs a header row and at least one body row: {spec[:60]!r}")
    head, body = cells[0], cells[1:]
    for c in head:
        if DIGIT_RE.search(_bare(c)) or _keys_in(c):
            raise BuildError(f"::table header cell {c!r} must be words (no figure, no digit)")
    for r in body:
        if len(r) != len(head):
            raise BuildError(f"::table row {' | '.join(r)!r} has {len(r)} cells, the header has {len(head)}")
        for c in r:
            if DIGIT_RE.search(_bare(c)):
                raise BuildError(f"::table cell {c!r} holds a typed digit; a figure in a table is a {{key}} like in prose")
    return head, body, cap


def table_html(spec, N, used, max_rows=None):
    """→ list of html chunks (one per card when the table is split, the header repeated)"""
    head, body, cap = parse_table(spec)
    for r in body:
        for c in r:
            for k in _keys_in(c):
                if k not in N:
                    raise KeyError(f"unknown figure {{{k}}} in ::table")
    ncol = len(head)
    # a column whose cells are all single figures sharing one unit prints the unit once, in the header
    col_unit, numeric = [], []
    for j in range(ncol):
        ks = [_keys_in(r[j]) for r in body]
        single = all(len(k) == 1 and r[j].strip() == "{" + k[0] + "}" for k, r in zip(ks, body))
        units = {unit_of(N[k[0]]) for k in ks if k} if single else set()
        numeric.append(any(ks) and all(k or not r[j].strip() for k, r in zip(ks, body)))
        col_unit.append(units.pop() if single and len(units) == 1 else None)

    def cell(c, j):
        if col_unit[j] is not None:
            k = _keys_in(c)[0]
            used.append(k)
            return f'<span class="n" data-key="{k}">{H.escape(fmt_value(N[k]))}</span>'
        return inline(c, N, "html", used)

    def th(j):
        u = col_unit[j]
        if u and u.lower() == re.sub(r"<[^>]+>", "", head[j]).strip().lower():
            u = None   # the header already names the unit ("FE")
        uh = f' <span class="u">({H.escape(u)})</span>' if u and u != "%" else (' <span class="u">(%)</span>' if u == "%" else "")
        return f'<th class="{"num" if numeric[j] else "lab"}">{inline(head[j], N, "html", used)}{uh}</th>'

    n = max_rows or len(body)
    chunks = [body[i:i + n] for i in range(0, len(body), n)]
    out = []
    for ci, rows in enumerate(chunks):
        trs = "".join("<tr>" + "".join(f'<td class="{"num" if numeric[j] else "lab"}">{cell(c, j)}</td>' for j, c in enumerate(r)) + "</tr>" for r in rows)
        thead = "<thead><tr>" + "".join(th(j) for j in range(ncol)) + "</tr></thead>"
        last = ci == len(chunks) - 1
        cont = "" if last else ' <span class="cont">(continued)</span>'
        cap_html = inline(cap, N, "html", used) if last else ""
        fc = f"<figcaption>{cap_html}{cont}</figcaption>" if (cap_html or cont) else ""
        out.append(f'<figure class="fig blk tbl" data-block="table">'
                   f'<table class="t">{thead}<tbody>{trs}</tbody></table>{fc}</figure>')
    return out


SEG_FILL = ("#1f5fa8", "#6f9bd1", "#a9c3e4", "#4f6d8f", "#c9d7e8", "#8a8a8a", "#d4d4d4")


def split_html(spec, N, used):
    parts = [p.strip() for p in spec.split("|")]
    if len(parts) < 2:
        raise BuildError(f"::split needs 'total | k1 k2 …': {spec[:60]!r}")
    total, keys = parts[0].split()[0], parts[1].split()
    opts = _opts(parts[2:])
    for k in [total] + keys:
        if k not in N:
            raise KeyError(f"unknown figure {{{k}}} in ::split")
    vals = [to_number(N[k].get("value")) for k in keys]
    tv = to_number(N[total].get("value"))
    if not all(isinstance(v, (int, float)) for v in vals + [tv]):
        raise BuildError(f"::split {total}: a segment or the total has no numeric value")
    ssum = sum(vals)
    if abs(ssum - tv) > 0.01 * abs(tv):
        raise BuildError(f"::split {total}: segments {' + '.join(keys)} sum to {ssum:.6g}, total is {tv:.6g} "
                         f"({(ssum - tv) / tv * 100:+.1f}%, more than 1% off)")
    labels = _words(opts.get("labels", " ".join(keys)))
    while len(labels) < len(keys):
        labels.append(keys[len(labels)])
    W, Hh = 374, 30
    x, rects = 0.0, []
    for i, (k, v) in enumerate(zip(keys, vals)):
        w = W * v / ssum if ssum else 0
        rects.append(f'<rect x="{x:.1f}" y="0" width="{max(0.5, w):.1f}" height="{Hh}" fill="{SEG_FILL[i % len(SEG_FILL)]}"/>')
        x += w
    svg = (f'<svg class="chart split" viewBox="0 0 {W} {Hh}" width="{W}" height="{Hh}" role="img" '
           f'aria-label="{H.escape(opts.get("cap", ""), quote=True)}">{"".join(rects)}</svg>')
    used.append(total)
    legend = []
    for i, (k, lab, v) in enumerate(zip(keys, labels, vals)):
        used.append(k)
        share = v / ssum * 100 if ssum else 0
        legend.append(f'<div class="seg"><span class="sw" style="background:{SEG_FILL[i % len(SEG_FILL)]}"></span>'
                      f'<span class="sl">{H.escape(lab)}</span><span class="sv"><span class="n" data-key="{k}">{H.escape(text_value(N[k]))}</span></span></div>')
    tot = (f'<div class="tot">{H.escape(N[total].get("label", total))} <span class="n" data-key="{total}">{H.escape(text_value(N[total]))}</span></div>')
    cap_html = inline(opts.get("cap", ""), N, "html", used)
    return (f'<figure class="fig blk split" data-block="split">{tot}{svg}<div class="legend">{"".join(legend)}</div>'
            f'<figcaption>{cap_html}</figcaption></figure>')


def pair_html(spec, N, used):
    parts = [p.strip() for p in spec.split("|")]
    m = re.match(r"left=(.+?)\s+right=(.+)$", parts[0])
    if not m:
        raise BuildError(f"::pair needs 'left=k… right=k…': {spec[:60]!r}")
    left, right = m.group(1).split(), m.group(2).split()
    opts = _opts(parts[1:])
    labels = _words(opts.get("labels", "before after"))
    while len(labels) < 2:
        labels.append("")
    rows = _words(opts.get("rows", ""))
    ident = opts.get("id", "").strip().strip("[]")
    for k in left + right:
        if k not in N:
            raise KeyError(f"unknown figure {{{k}}} in ::pair")

    def card(keys, arm):
        lis = []
        for i, k in enumerate(keys):
            used.append(k)
            lab = rows[i] if i < len(rows) else N[k].get("label", k)
            if DIGIT_RE.search(lab):
                raise BuildError(f"::pair row label {lab!r} holds a digit; name it in words")
            lis.append(f'<div class="pr"><span class="pl">{H.escape(lab)}</span><span class="pv"><span class="n" data-key="{k}">{H.escape(text_value(N[k]))}</span></span></div>')
        hd = (f'<div class="ph"><span class="id">{H.escape(ident)}</span></div>' if ident else "")
        return f'<div class="pc">{hd}<div class="pa">{H.escape(arm)}</div>{"".join(lis)}</div>'

    cap_html = inline(opts.get("cap", ""), N, "html", used)
    return (f'<figure class="fig blk pair" data-block="pair"><div class="pairs">{card(left, labels[0])}{card(right, labels[1])}</div>'
            f'<figcaption>{cap_html}</figcaption></figure>')


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


def render_blocks(blocks, N, max_rows=None):
    """→ list of (kind, html, block index), used keys. max_rows: {block index: rows per card} for a split table"""
    out, used, first_quote = [], [], True
    max_rows = max_rows or {}
    for bi, (kind, body) in enumerate(blocks):
        n0 = len(out)
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
            out.append((kind, bars_svg(body, N, used).replace('<figure class="fig">', '<figure class="fig blk" data-block="bars">', 1)))
        elif kind == "table":
            out.extend((kind, h) for h in table_html(body, N, used, max_rows.get(bi)))
        elif kind == "split":
            out.append((kind, split_html(body, N, used)))
        elif kind == "pair":
            out.append((kind, pair_html(body, N, used)))
        elif kind == "checker":
            out.append((kind, checker_html(body)))
        elif kind == "break":
            out.append((kind, ""))
        out[n0:] = [(k, h, bi) for k, h in out[n0:]]
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
table.t{width:100%;border-collapse:collapse;font-size:14px;line-height:1.3}
table.t th,table.t td{padding:4px 5px;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}
table.t th{font-size:12.5px;color:var(--muted);font-weight:600;border-bottom:1.5px solid #999}
table.t .num{text-align:right;white-space:nowrap}table.t .lab{text-align:left}
table.t th .u{font-weight:400}
.cont{font-style:italic}
.split .tot{font-size:13.5px;color:var(--muted);margin-bottom:4px}
svg.split{border-radius:4px}
.legend{margin-top:6px;font-size:14px}
.seg{display:flex;align-items:center;gap:6px;padding:2px 0;border-bottom:1px dotted var(--line)}
.seg .sw{flex:0 0 12px;height:12px;border-radius:2px}.seg .sl{flex:1 1 auto;min-width:0}.seg .sv{flex:0 0 auto;text-align:right}
.pairs{display:flex;gap:8px}
.pc{flex:1 1 0;min-width:0;border:1px solid var(--line);border-radius:8px;padding:6px 8px;background:#fafafa}
.pc .ph{font-size:12.5px;color:var(--muted)}.pc .pa{font-weight:700;font-size:15px;margin:1px 0 4px}
.pr{display:flex;flex-wrap:wrap;justify-content:space-between;gap:0 6px;font-size:13.5px;padding:2px 0;border-top:1px dotted var(--line)}
.pr .pl{color:var(--muted)}.pr .pv{margin-left:auto}
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


LEDGER = os.environ.get("REPORT_LEDGER") or os.path.join(os.path.dirname(HERE), "evals", "report-writer", "ledger.jsonl")
FORMS = ("moment", "log-line", "break", "expected-vs-got", "person")
KEEP = set("""a an the of to in on at by for from with without into onto over under after before since until than as and or but
nor so yet if when while that which who whom whose what where why how this these those it its it's is are was were be been
being am do does did done has have had not no never more most less least one two three every each all some any half twice
you your yours i me my we us our they them their he she his her cost costs beat won lost took ran made got went
came found left paid ate saved broke waited stayed kept outweighed outran passed failed carried grew fell rose doubled
halved everything nothing something anything wrote said asked wanted needed used""".split())


def title_shape(title):
    """the title with figures as N and nouns (every word outside a short list of function words and verbs) as _"""
    t = re.sub(r"\{[A-Za-z0-9_]+@?\}|\[\[.+?\]\]|[−+-]?\d[\d,.]*%?", " N ", title)
    out = []
    for w in re.findall(r"N|[A-Za-z][A-Za-z'’-]*", t):
        lw = w.lower()
        tok = "N" if w == "N" else (w if (lw in KEEP or (lw.endswith("ed") and len(lw) > 4)) else "_")
        if tok == "_" and out and out[-1] == "_":
            continue
        out.append(tok)
    return " ".join(out)


def notes_form(outdir):
    """the form named on NOTES.md's '## Openings' line 'pick: <form>' (None when absent)"""
    p = os.path.join(outdir, "NOTES.md")
    if not os.path.exists(p):
        return None
    txt = open(p, encoding="utf-8").read()
    m = re.search(r"^##\s*Openings\s*$(.*?)(?=^##\s|\Z)", txt, re.S | re.M)
    if not m:
        return None
    pm = re.search(r"^\W*pick\W*\s*[:=]?\s*\**`?([a-z-]+)", m.group(1), re.M | re.I)
    f = pm.group(1).lower() if pm else None
    return f if f in FORMS else None


def first_sentence(blocks):
    """the first sentence of the opening: the first paragraph after the who line, skipping a short label line"""
    seen_who = False
    for kind, body in blocks:
        if kind == "who":
            seen_who = True
            continue
        if seen_who and kind == "p":
            if len(body.split()) <= 8 and "{" not in body:
                continue
            return re.split(r"(?<=[.!?])\s+(?=[A-Z])", body.strip())[0]
    return ""


def write_ledger(outdir, blocks):
    import datetime, hashlib
    title = next((b for k, b in blocks if k == "h1"), "")
    fs = first_sentence(blocks)
    row = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "out": os.path.realpath(outdir),
           "form": notes_form(outdir), "title": title, "title_shape": title_shape(title),
           "first_sentence_sha1": hashlib.sha1(fs.encode("utf-8")).hexdigest()}
    rows = []
    if os.path.exists(LEDGER):
        for l in open(LEDGER, encoding="utf-8"):
            if l.strip():
                try:
                    r = json.loads(l)
                except ValueError:
                    continue
                if r.get("out") != row["out"]:
                    rows.append(r)
    rows.append(row)
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    with open(LEDGER, "w", encoding="utf-8") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
    return row


BLOCKS = ("bars", "table", "split", "pair")


def prose_words(body):
    """prose words of one section (same count as check.py's focus group)"""
    n = 0
    for l in body.splitlines():
        t = l.strip()
        if not t or t.startswith(("::", ">", "~ ", "#", "📚", "---")):
            continue
        t = re.sub(r"\{[A-Za-z0-9_]+@?\}", "N", t)
        t = re.sub(r"\[\[(.+?)\]\]", r"\1", t)
        n += len([w for w in t.split() if re.search(r"\w", w)])
    return n


def section_words(src):
    """report.md → [{"section", "words"}]: the # title (opening card, up to the first ##), then every ## section"""
    parts = re.split(r"^## ", src, flags=re.M)
    m = re.search(r"^# (.+)$", parts[0], re.M)
    out = [{"section": m.group(1).strip() if m else "", "words": prose_words(parts[0][m.end():] if m else parts[0])}]
    for x in parts[1:]:
        ls = x.splitlines()
        out.append({"section": ls[0].strip(), "words": prose_words("\n".join(ls[1:]))})
    return out


def write_words(outdir, src):
    mp = os.path.join(outdir, "cards", "measure.json")
    if not os.path.exists(mp):
        return None
    m = json.load(open(mp))
    m["words"] = section_words(src)
    json.dump(m, open(mp, "w"), indent=1, ensure_ascii=False)
    return m["words"]


def pack(items, h):
    """items (kind, html, block index) → groups of at most PACK css px; a heading, quote or who line sticks to what follows"""
    groups, cur, cur_h = [], [], 0
    for i, it in enumerate(items):
        if it[0] == "break":
            if cur:
                groups.append(cur); cur, cur_h = [], 0
            continue
        bh = h[i]
        if cur and cur_h + bh > PACK:
            tail = []
            if it[0] in BLOCKS and cur and cur[-1][1][0] == "p":   # the sentence that names what a block shows stays with it
                tail.insert(0, cur.pop())
            while cur and cur[-1][1][0] in ("h1", "h2", "quote", "who"):
                tail.insert(0, cur.pop())
            if cur:
                groups.append(cur)
            cur, cur_h = tail, sum(h[j] for j, _ in tail)
        cur.append((i, it)); cur_h += bh
    if cur:
        groups.append(cur)
    return [[it for _, it in g] for g in groups]


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
    max_rows = {}
    try:
        items, used = render_blocks(blocks, N, max_rows)
    except (KeyError, BuildError) as ex:
        sys.exit(f"build.py: {ex.args[0] if ex.args else ex}")
    title = next((re.sub(r"<[^>]+>", "", h) for k, h, _ in items if k == "h1"), os.path.basename(os.path.dirname(outdir) or outdir))
    if not cards:
        groups = [[it for it in items if it[0] != "break"]]
    else:
        for _ in range(4):   # a table taller than a card is split into chunks with the header repeated, then measured again
            singles = [(f"b{i:03d}", [it[:2]]) for i, it in enumerate(items) if it[0] != "break"]
            open(os.path.join(outdir, html), "w", encoding="utf-8").write(page_html(singles, title))
            m1, _ = measure(outdir, "desktop", html)
            hm = {c["slug"]: c["css_height_px"] - 26 for c in m1["cards"]}
            h = [hm.get(f"b{i:03d}", 0) for i in range(len(items))]
            changed = False
            for bi in {it[2] for it in items if it[0] == "table"}:
                idx = [i for i, it in enumerate(items) if it[2] == bi]
                tall = max(h[i] for i in idx)
                if tall > PACK - 20:
                    nrows = len(parse_table(blocks[bi][1])[1])
                    per = max_rows.get(bi, nrows)
                    max_rows[bi] = max(1, int(per * (PACK - 60) / tall))
                    changed = True
            if not changed:
                break
            used = []
            items, used = render_blocks(blocks, N, max_rows)
        groups = pack(items, h)
    unused = sorted(set(N) - set(used) - {k for u in used for k in N[u].get("derived", {}).get("of", [])})
    named = [(slug([(k, hh) for k, hh, _ in c], n + 1), [(k, hh) for k, hh, _ in c]) for n, c in enumerate(groups)]
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
        if md == "report.md":
            write_words(outdir, src)
        print(f"build: {len(named)} card(s), {len(set(used))} figures used of {len(N)}; no cards (--no-cards)")
        return
    m2, summary = measure(outdir, "phone", html)
    heights = ", ".join(f"{c['slug']} {c['css_height_px']}" for c in m2["cards"])
    nblk = ", ".join(f"{b['kind']} {b['css_height_px']}" for b in m2.get("blocks", []))
    print(f"build: {len(named)} cards ({heights}); {len(set(used))} figures used of {len(N)}"
          + (f"; unused keys: {', '.join(unused[:12])}{' …' if len(unused) > 12 else ''}" if unused else "")
          + (f"; blocks: {nblk}" if nblk else "") + f"; {summary}")
    if md == "report.md":
        W = write_words(outdir, src) or []
        print("words: " + ", ".join(f"{w['section'][:24]} {w['words']}" for w in W))
        row = write_ledger(outdir, blocks)
        print(f"ledger: {row['form'] or 'NO FORM (NOTES.md ## Openings lacks a pick: line)'} | {row['title_shape']} → {LEDGER}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0].startswith("-"):
        sys.exit(__doc__)
    outdir = os.path.abspath(a[0])
    data = os.path.abspath(a[a.index("--data") + 1]) if "--data" in a else os.path.dirname(outdir)
    md = a[a.index("--md") + 1] if "--md" in a else "report.md"
    numbers = a[a.index("--numbers") + 1] if "--numbers" in a else "numbers.json"
    build(outdir, data, cards="--no-cards" not in a, md=md, numbers=numbers)
