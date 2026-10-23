#!/usr/bin/env python3
"""Mechanical checks for a report-writer report.

    python3 -I check.py <outdir> [--data <data dir>] [--traps <TRAPS.md>] [--mode desktop|phone] [--other <report.html>]
    python3 -I check.py <outdir> --prose [--data …] [--traps …] [--expected expected.json]
        the essay form (report-writer since 2026-10-21; golden r5): figures resolve, numbers, traps-in-body, most_runs, cards,
        card1 (quote + who + [note] + microcosm + "But" with two means and n on one screen), voice, voice_prose, prose_shape,
        no_summary_sections, ending (names the microcosm again), terms_once, ai_tells (every regex-checkable tell of
        docs/ai-tells.md), checker_line (last line: loops/raised/fixed/open/tokens/wall or "checker: off"), expected

<outdir> holds numbers.json, report.html and cards/measure.json (from render.py). --data is the directory that
numbers.json's "file" paths are relative to (default: the fixture's data dir next to this script). Prints one line per
check, "PASS"/"FAIL <name>: <why>", and exits 1 on the first group with a failure, naming it. Stdlib only.

Checks: numbers_match_sources  every numbers.json entry equals the value in the file and field it cites (derived ones
                                are recomputed from the entries they name); a file inside the report dir or outside --data
                                is a writer-made data file and fails (figures come from study files; aggregates use the
                                [?k=v]…|mean field syntax)
        numbers_on_page        every number in the page's visible text is a numbers.json figure with that same text
        one_value_per_quantity no label carries two values; no two keys print different values for the same label
        traps                  every TRAPS.md trap is flagged in "Wrong or missing" and its number is not a plain figure
        first_screen           verdict, next action, deciding number (n + spread + source), Wrong-or-missing box, one
                                chart, decision table with name/change/spread/n/verdict per row
        sections_support       every body section heading names 'verdict' or a decision-table row
        no_ellipsis            no "…" or "..." in visible text
        paragraphs             no paragraph or list item over 3 lines at 390 px (cards/measure.json)
        cards                  phone cards 390 css px wide and <= 1500 css px tall (PNG = that x scale)
        first_screen_fits      the six first-screen elements end within 1000 css px on a 390 px phone (aim 844) and
                                within 1250 css px at 1530 px wide on the desktop (cards/measure.json)
        chart_reading          every chart is followed by a written reading (<p class="reading">) that names a figure
                               (how far ahead) and says whether the gap clears the spread
        voice                  the user's style: no "X, not Y" contrasts, no emphasis words (actually, really, exactly, at
                                all, simply, just, merely, clearly, notably), no em-dashes outside the question block, no
                                heading or paragraph opening with a 1-3 word label and a colon (file names/keys excepted),
                                no one-word verdict after a colon ("spread: unproven."), no semicolon-chained prose, and
                                a verdict that is a sentence (no colon, no comma-chained fragments)
        problem_first          the page opens with the problem and why it is worth solving (#problem, from report.json
                                "problem": {"what", "why"}) before the verdict, at most 4 lines at 390 px
        wrong_short            the Wrong-or-missing box has at most 6 items, each at most 2 lines at 390 px (aim: one),
                                written as plain sentences: no .json file or field named, at most two figures per item
        first_once             card 1 prints each figure once: no numbers.json key in more than one of the verdict, the
                                deciding number and the decision chart's reading
        axis_note              every bars chart whose axis_min > 0 prints "(axis does not start at 0)" on its axis, draws a
                                break mark on every bar, and report.json gives an axis_reason for it
        most_runs              (--traps) each decision-table row's candidate n is at least the largest n the fixture holds for
                                that candidate (TRAPS.md "Expected n per candidate" table)
        modes_match            (--other <report.html>) the decision table is identical, cell by cell, in the other mode's page
        checked_line           the last line names the numbers.json count and the check result
        checker_line           the last line reports the checker (loops, raised, fixed, open) and checker/findings.json exists
"""
import json, os, re, sys, html as H

PROSE = False  # --prose: a hand-written report (golden r4): no verdict box, caveats box or decision table
NUM_RE = re.compile(r"(?<![\w.:/−+-])[−+-]?\d[\d,]*(?:\.\d+)?%?(?![\w.:/−-])")
ALLOW = re.compile(r"^(?:\d{4}-\d\d-\d\d|\d\d?:\d\d)$")
fails = []
out_lines = []


def ok(name, msg=""):
    out_lines.append(f"PASS {name}" + (f": {msg}" if msg else ""))


def bad(name, msg):
    fails.append(name)
    out_lines.append(f"FAIL {name}: {msg}")


# ---------- source resolution -----------------------------------------------------------------------------------------
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
    p = os.path.join(root, path) if not os.path.isabs(path) else path
    if p in cache:
        return cache[p]
    if not os.path.exists(p):
        cache[p] = None
        return None
    txt = open(p, encoding="utf-8", errors="replace").read()
    if p.endswith(".json"):
        try:
            cache[p] = ("json", json.loads(txt))
        except Exception as e:  # noqa
            cache[p] = ("text", txt)
    elif p.endswith(".jsonl"):
        cache[p] = ("json", [json.loads(l) for l in txt.splitlines() if l.strip()])
    else:
        cache[p] = ("text", txt)
    return cache[p]


def close(a, b, fmt):
    if a is None or b is None:
        return a is None and b is None
    if isinstance(a, list) or isinstance(b, list):
        return isinstance(a, list) and isinstance(b, list) and len(a) == len(b) and all(close(x, y, fmt) for x, y in zip(a, b))
    try:
        a, b = float(a), float(b)
    except (TypeError, ValueError):
        return a == b
    if abs(a - b) <= 1e-9 * max(1, abs(a), abs(b)):
        return True
    # a value stored rounded to its print precision is still a match
    d = int(fmt) if isinstance(fmt, int) else (int(fmt[1:] or 0) + 2 if isinstance(fmt, str) and fmt.startswith("%") else 0)
    return abs(a - b) <= 0.5 * 10 ** (-d) + 1e-12


def derive(op, vals, N):
    vals = [v for v in vals]
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
    if op == "mean_slice":  # mean of a list value over [a:b] given as of=[listkey], args=[a,b]
        return None
    raise ValueError(f"unknown derived op {op}")


def writer_made(root, f, outdir):
    """True when a numbers.json "file" is not a study file: it sits inside the report (output) dir, or outside the data dir.
    Rule (INVESTIGATION.md, "Writer-made data files"): the writer never makes data files; every figure is read from a file
    the study shipped, with the [?k=v]…|agg field syntax or a derived op doing any arithmetic."""
    p = os.path.realpath(f if os.path.isabs(f) else os.path.join(root, f))
    out = os.path.realpath(outdir) if outdir else None
    if out and (p == out or p.startswith(out + os.sep)):
        return True
    r = os.path.realpath(root)
    return not (p == r or p.startswith(r + os.sep))


def check_numbers_match_sources(N, root, outdir=None):
    n_ok = 0
    for key, e in N.items():
        fmt = e.get("fmt", 2)
        if "derived" in e:
            d = e["derived"]
            op = d["op"]
            try:
                if op == "mean_slice":
                    src = N[d["of"][0]]["value"]
                    a, b = d.get("args", [0, None])
                    sl = src[a:b]
                    val = sum(sl) / len(sl) if sl else None
                elif op == "literal":
                    val = d.get("value")
                else:
                    vals = []
                    for k in d["of"]:
                        if k not in N:
                            raise KeyError(f"derived from unknown key {k}")
                        v = N[k].get("value")
                        if isinstance(v, list):
                            raise ValueError(f"{k} is a list; use mean_slice")
                        vals.append(v)
                    val = derive(op, vals, N)
            except Exception as ex:  # noqa
                bad("numbers_match_sources", f"{key}: cannot recompute ({ex})")
                continue
            if not close(val, e.get("value"), fmt):
                bad("numbers_match_sources", f"{key}: recomputed {val} from {d['of']} ({op}) but numbers.json says {e.get('value')}")
            else:
                n_ok += 1
            continue
        f, field = e.get("file"), e.get("field")
        if not f or not field:
            if e.get("value") is None:
                n_ok += 1  # a 'not measured' entry may cite only the file that lacks it
                continue
            bad("numbers_match_sources", f"{key}: no file/field")
            continue
        if writer_made(root, f, outdir):
            bad("numbers_match_sources", f"{key}: file {f} is a writer-made data file (inside the report dir or outside the data dir); figures come from study files only")
            continue
        loaded = load_file(root, f)
        if loaded is None:
            bad("numbers_match_sources", f"{key}: file {f} not found under {root}")
            continue
        kind, obj = loaded
        try:
            if kind == "json":
                got = resolve_path(obj, field)
            else:
                m = re.search(field, obj, re.M)
                if not m:
                    raise KeyError(f"regex {field!r} not found in {f}")
                g = m.group(1) if m.groups() else m.group(0)
                got = float(g.replace(",", "")) if re.fullmatch(r"[−+-]?\d[\d,]*(?:\.\d+)?", g) else g
        except Exception as ex:  # noqa
            bad("numbers_match_sources", f"{key}: {f} → {field}: {ex}")
            continue
        if e.get("value") is None:
            if got is None:
                n_ok += 1
            else:
                bad("numbers_match_sources", f"{key}: says not measured but {f} → {field} = {got}")
            continue
        if isinstance(got, bool):
            got = int(got)
        if not close(got, e.get("value"), fmt):
            bad("numbers_match_sources", f"{key}: {f} → {field} = {got}, numbers.json says {e.get('value')}")
        else:
            n_ok += 1
    if "numbers_match_sources" not in fails:
        ok("numbers_match_sources", f"{n_ok} figures match their sources")


# ---------- page text --------------------------------------------------------------------------------------------------
def visible_text(page):
    page = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", page, flags=re.S)
    page = re.sub(r"<[^>]+>", " ", page)
    return H.unescape(page)


def spans(page):
    """all <span|tspan class="n ..." data-key="k">text</...> on the page → list of (key, text)"""
    out = []
    for m in re.finditer(r'<(span|tspan) class="n[^"]*" data-key="([^"]+)">(.*?)</\1>', page, re.S):
        out.append((H.unescape(m.group(2)), H.unescape(re.sub(r"<[^>]+>", "", m.group(3))).strip()))
    return out


def check_numbers_on_page(N, page):
    # (a) every number span prints its key's value (the rendered text begins with the formatted value)
    sp = spans(page)
    keyed_text = set()
    for key, text in sp:
        if key not in N:
            bad("numbers_on_page", f"span cites unknown key {key}")
            continue
        keyed_text.add(text)
    # (b) every numeric token in visible text is inside a span: strip span contents, then look for leftovers
    stripped = re.sub(r'<(span|tspan) class="n[^"]*" data-key="[^"]+">.*?</\1>', " ", page, flags=re.S)
    stripped = re.sub(r'<span class="src">\(.*?\)</span>', " ", stripped, flags=re.S)  # run names like ab-stack-1
    stripped = re.sub(r'<span class="src"[^>]*>.*?</span>', " ", stripped, flags=re.S)
    stripped = re.sub(r'<p[^>]*id="checked".*?</p>', " ", stripped, flags=re.S)  # the checker line's counts are not figures
    stripped = re.sub(r'<p class="question">.*?</p>', " ", stripped, flags=re.S)  # the user's question, verbatim
    stripped = re.sub(r'<q class="ask">.*?</q>', " ", stripped, flags=re.S)  # the user's ask, quoted verbatim
    stripped = re.sub(r'<span class="who">.*?</span>', " ", stripped, flags=re.S)  # where the ask was said (e.g. round 9)
    if PROSE:
        stripped = re.sub(r'<span class="id">.*?</span>', " ", stripped, flags=re.S)  # a gen, round or run index, not a figure
        stripped = re.sub(r"<title>.*?</title>", " ", stripped, flags=re.S)  # the tab title repeats the h1, whose ids are already skipped
    stripped = re.sub(r'<sup class="ev">.*?</sup>', " ", stripped, flags=re.S)  # evidence markers [1], [2] are links, not figures
    stripped = re.sub(r'<text [^>]*class="axisnote">.*?</text>', " ", stripped, flags=re.S)  # chart axis range, not a figure
    txt = visible_text(stripped)
    loose = []
    for m in NUM_RE.finditer(txt):
        tok = m.group(0)
        if ALLOW.match(tok):
            continue
        ctx = txt[max(0, m.start() - 30):m.end() + 20].replace("\n", " ")
        loose.append(f"{tok!r} in “…{ctx.strip()}…”")
    if loose:
        bad("numbers_on_page", f"{len(loose)} numbers outside numbers.json spans: " + " | ".join(loose[:8]))
    else:
        ok("numbers_on_page", f"{len(sp)} number spans, 0 loose numbers")


def check_one_value(N, page):
    by_label = {}
    for key, e in N.items():
        lab = e.get("label")
        if not lab:
            continue
        v = e.get("value")
        by_label.setdefault(lab.strip().lower(), set()).add(json.dumps(v))
    dup = {l: v for l, v in by_label.items() if len(v) > 1}
    # same key printed with two texts?
    texts = {}
    for key, text in spans(page):
        core = re.match(r"[−+-]?[\d,]+(?:\.\d+)?", text)
        texts.setdefault(key, set()).add(core.group(0) if core else text)
    multi = {k: v for k, v in texts.items() if len(v) > 1}
    if dup or multi:
        bad("one_value_per_quantity", f"labels with two values: {list(dup)[:5]}; keys printed two ways: {multi}")
    else:
        ok("one_value_per_quantity", f"{len(by_label)} labels, each one value")


def box_text(page, el_id):
    m = re.search(rf'<[^>]+id="{el_id}"[^>]*>(.*?)</(div|section|p)>', page, re.S)
    return visible_text(m.group(1)) if m else ""


def parse_traps(path):
    traps = []
    for line in open(path, encoding="utf-8"):
        if not line.startswith("|") or line.startswith("| #") or line.startswith("|---"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6 or not cells[0].isdigit():
            continue
        flags = [re.sub(r"`", "", c).strip() for c in cells[4].split(",")]
        # "a or b" inside one cell means either word is enough
        flags = [[w.strip() for w in f.split(" or ")] for f in flags]
        nums = [re.sub(r"`", "", c).strip() for c in re.split(r",\s*(?=`)", cells[5])] if cells[5] not in ("—", "-", "") else []
        nums = [re.split(r"\s+as\s+", n)[0].strip() for n in nums]
        traps.append({"n": int(cells[0]), "flags": flags, "nums": [n for n in nums if n], "desc": cells[1][:60]})
    return traps


def check_traps(page, traps_path):
    if not traps_path or not os.path.exists(traps_path):
        ok("traps", "no TRAPS.md given, skipped")
        return
    traps = parse_traps(traps_path)
    wom = box_text(page, "wrong-or-missing").lower()
    table = box_text(page, "decision-table").lower()
    # text outside the box and the decision table
    rest = re.sub(r'<div id="wrong-or-missing".*?</div>', " ", page, flags=re.S)
    rest = re.sub(r'<div id="decision-table".*?</table></div>', " ", rest, flags=re.S)
    rest_txt = visible_text(rest)
    problems = []
    for t in traps:
        for alts in t["flags"]:
            if not any(a.lower() in wom for a in alts):
                problems.append(f"trap {t['n']}: '{alts[0]}' not in Wrong or missing")
        for n in t["nums"]:
            if re.search(rf"(?<![\d.]){re.escape(n)}(?![\d])", rest_txt):
                problems.append(f"trap {t['n']}: {n} appears as a plain figure outside Wrong-or-missing/decision table")
    if problems:
        bad("traps", "; ".join(problems))
    else:
        ok("traps", f"{len(traps)} traps flagged, none quoted as a plain figure")
    return traps


def check_first_screen(page):
    probs = []
    for el, name in [("verdict", "verdict"), ("next-action", "next action"), ("deciding", "deciding number"), ("wrong-or-missing", "Wrong or missing box"), ("decision-chart", "decision chart"), ("decision-table", "decision table")]:
        if f'id="{el}"' not in page:
            probs.append(f"no {name} (#{el})")
    dec = re.search(r'<p id="deciding".*?</p>', page, re.S)
    if dec:
        d = dec.group(0)
        txt = visible_text(d).lower()
        if not re.search(r"\bn\s*=\s*", txt) and " n " not in txt:
            probs.append("deciding number has no n")
        if "spread" not in txt:
            probs.append("deciding number has no spread")
        if 'class="src"' not in d:
            probs.append("deciding number has no source")
    if 'id="decision-chart"' in page and "<svg" not in (re.search(r'<div id="decision-chart">(.*?)</div>', page, re.S) or [None, ""])[1]:
        probs.append("decision chart has no SVG")
    rows = re.findall(r'<tr data-row="([^"]+)">(.*?)</tr>', page, re.S)
    if not rows:
        probs.append("decision table has no rows")
    for name, body in rows:
        cells = re.findall(r"<td>(.*?)</td>", body, re.S)
        if len(cells) != 5:
            probs.append(f"row {name}: {len(cells)} cells")
            continue
        v = visible_text(cells[4]).strip()
        if v not in ("keep", "drop", "rerun", "unproven"):
            probs.append(f"row {name}: verdict {v!r}")
        for i, lab in [(1, "change"), (2, "spread"), (3, "n")]:
            if not visible_text(cells[i]).strip():
                probs.append(f"row {name}: empty {lab}")
    first_cards = re.findall(r'<section class="card first"', page)
    if len(first_cards) < 1:
        probs.append("no first-screen cards")
    if probs:
        bad("first_screen", "; ".join(probs))
    else:
        ok("first_screen", f"all elements present, {len(rows)} decision rows")
    return [H.unescape(n) for n, _ in rows]


def check_sections(page, rows):
    probs = []
    secs = re.findall(r'<section class="card body" id="([^"]+)" data-supports="([^"]*)">\s*<h2>(.*?)</h2>', page, re.S)
    for sid, sup, h in secs:
        sup = H.unescape(sup)
        htxt = visible_text(h)
        if sup == "verdict":
            if "supports: verdict" not in htxt:
                probs.append(f"{sid}: heading does not say it supports the verdict")
        elif sup.startswith("row: ") and sup[5:] in rows:
            if f"supports: {sup}" not in htxt:
                probs.append(f"{sid}: heading does not name its row")
        else:
            probs.append(f"{sid}: supports {sup!r}, not a verdict or a decision-table row")
    if probs:
        bad("sections_support", "; ".join(probs))
    else:
        ok("sections_support", f"{len(secs)} sections, each names what it supports")


def check_ellipsis(page, measure):
    txt = visible_text(page)
    n = txt.count("…") + len(re.findall(r"\.\.\.", txt))
    if n or (measure and measure.get("ellipsis")):
        bad("no_ellipsis", f"{n} in HTML text, {measure.get('ellipsis') if measure else '?'} at 390 px")
    else:
        ok("no_ellipsis")


def check_paragraphs(measure, limit=3):
    if not measure:
        bad("paragraphs", "cards/measure.json missing (render.py runs cards.mjs)")
        return
    # the "How this was checked" footer is a mandated status line (figures, check.py, checker counts, caveats): 5 lines
    long = [p for p in measure["paragraphs"] if p["lines"] > (5 if p["text"].startswith("How this was checked") else limit)]
    if long:
        bad("paragraphs", f"{len(long)} over {limit} lines at 390 px: " + " | ".join(f"[{p['card']}] {p['text'][:50]!r} ({p['lines']} lines)" for p in long[:5]))
    else:
        ok("paragraphs", f"{len(measure['paragraphs'])} paragraphs/items, none over {limit} lines at 390 px")
    if measure.get("horizontal_scroll") or measure.get("overflow"):
        bad("paragraphs", f"horizontal scroll {measure.get('horizontal_scroll')}, overflowing boxes: {measure.get('overflow')[:3]}")


def check_cards(measure, mode):
    if not measure:
        bad("cards", "no measure.json")
        return
    scale = measure.get("scale", 1)
    probs = []
    for c in measure["cards"]:
        if c["css_height_px"] > 1500:
            probs.append(f"{c['slug']} is {c['css_height_px']} css px tall")
        if mode == "phone":
            if not c.get("png"):
                probs.append(f"{c['slug']} has no PNG")
            elif c["png_width_px"] != 390 * scale or c["png_height_px"] > 1500 * scale:
                probs.append(f"{c['png']} is {c['png_width_px']}x{c['png_height_px']} px (scale {scale}: want {390 * scale} wide, ≤ {1500 * scale} tall)")
    if probs:
        bad("cards", "; ".join(probs))
    else:
        ok("cards", f"{len(measure['cards'])} cards ≤ 1500 css px tall" + (f", PNGs {390 * scale} px wide ({scale}x of 390)" if mode == "phone" else ""))


def check_first_screen_fits(measure, mode):
    if not measure or "first_screen" not in measure:
        bad("first_screen_fits", "cards/measure.json has no first_screen measurement (rerun render.py)")
        return
    fs = measure["first_screen"]
    probs = []
    missing = [k for k, v in fs.items() if v is None and k not in ("bottom_px", "moved")]
    if missing:
        probs.append(f"not on the page: {', '.join(missing)}")
    if fs["bottom_px"] > 1000:
        probs.append(f"ends at {fs['bottom_px']} css px on a 390 px phone (hard limit 1000, aim 844)")
    ds = measure.get("desktop_first_screen") or {}
    if mode == "desktop" and ds.get("bottom_px", 0) > 1250:
        probs.append(f"ends at {ds['bottom_px']} css px at 1530 px wide (limit 1250: no scrolling in Firefox)")
    if probs:
        bad("first_screen_fits", "; ".join(probs))
    else:
        note = f"phone: ends at {fs['bottom_px']} css px of 844" + (" (over the 844 aim, under the 1000 limit)" if fs["bottom_px"] > 844 else "")
        if ds:
            note += f"; desktop: {ds.get('bottom_px')} of 1250"
        if fs.get("moved"):
            note += f"; moved to the numbers card: {', '.join(fs['moved'])}"
        ok("first_screen_fits", note)


def charts(page, R):
    """(id/title, svg html, spec) for every bars chart on the page, paired with its report.json spec by title order."""
    specs = []
    F = (R or {}).get("first", {})
    if F.get("chart", {}).get("type") == "bars":
        specs.append(F["chart"])
    for sec in (R or {}).get("sections", []):
        for bl in sec.get("blocks", []):
            if bl.get("chart", {}).get("type") == "bars":
                specs.append(bl["chart"])
    svgs = re.findall(r'<svg class="chart values"[^>]*>.*?</svg>', page, re.S)
    return list(zip(svgs, specs)) if len(svgs) == len(specs) else [(sv, None) for sv in svgs]


SPREAD_WORDS = ("spread", "noise", "within", "inside", "outside", "clears", "clear of", "overlap", "beyond")


def check_chart_reading(page):
    figs = re.findall(r'<figure class="fig">(.*?)</figure>', page, re.S)
    if not figs:
        bad("chart_reading", "no chart on the page")
        return
    probs = []
    for i, f in enumerate(figs):
        title = re.search(r'<figcaption>([^<]*)', f)
        title = title.group(1).strip() if title else f"chart {i + 1}"
        m = re.search(r'<p class="reading">(.*?)</p>', f, re.S)
        if not m or not m.group(1).strip():
            probs.append(f"chart {i + 1} ({title!r}): no reading under the chart")
            continue
        t = re.sub(r"<[^>]+>", "", m.group(1)).replace("Reading", "", 1).strip()
        if len(t) < 20:
            probs.append(f"chart {i + 1} ({title!r}): reading too short ({t!r})")
            continue
        if not re.search(r"\d", t):
            probs.append(f"chart {i + 1} ({title!r}): reading gives no figure (by how much?): {t[:80]!r}")
        if not any(w in t.lower() for w in SPREAD_WORDS):
            probs.append(f"chart {i + 1} ({title!r}): reading does not say whether the gap clears the spread: {t[:80]!r}")
    if probs:
        bad("chart_reading", "; ".join(probs))
    else:
        ok("chart_reading", f"{len(figs)} charts, each with a reading that gives a figure and speaks to the spread")


# ---------- voice (the user's style, skills/write-readme/references/style.md) -----------------------------------------
EMPH_RE = re.compile(r"\b(actually|really|exactly|simply|just|merely|clearly|notably|importantly)\b|\bat all\b", re.I)
CONTRAST_RE = re.compile(r",\s*not\s+(?:a\s+|an\s+|the\s+)?\w[\w' -]{0,30}?(?=[.;)]|$)|\bnot\s+\w+(?:\s+\w+){0,4},?\s+but\b", re.I)
LABEL_RE = re.compile(r"^([A-Z][A-Za-z' -]*?):\s+\S")
FRAGMENT_RE = re.compile(r":\s+[a-z]+\.(?:\s|$)")


def voice_blocks(page):
    """(kind, text) for every h2/h3 heading and <p> paragraph outside #question and the checked line"""
    page = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", page, flags=re.S)
    page = re.sub(r'<(section|div|aside)[^>]*id="question"[^>]*>.*?</\1>', " ", page, flags=re.S)
    page = re.sub(r'<q class="ask">.*?</q>', " ", page, flags=re.S)  # the user's own words are not judged for voice
    page = re.sub(r'<sup class="ev">.*?</sup>', " ", page, flags=re.S)
    page = re.sub(r'<p[^>]*id="checked".*?</p>', " ", page, flags=re.S)  # the checker line is a fixed status line
    out = []
    for m in re.finditer(r"<(h2|h3|p|li|figcaption)\b([^>]*)>(.*?)</\1>", page, re.S):
        if 'class="cite' in m.group(2):
            continue
        t = re.sub(r"\s+", " ", H.unescape(re.sub(r"<[^>]+>", " ", m.group(3)))).strip()
        if t and not t.startswith("How this was checked") and not t.startswith("Question"):
            out.append((m.group(1), t))
    return out


def check_voice(page):
    probs = []
    for kind, t in voice_blocks(page):
        t2 = re.sub(r"\bReading\b", "", t, count=1).strip() if kind == "p" else t
        if "—" in t2:
            probs.append(f"em-dash in <{kind}>: {t2[:70]!r}")
        m = EMPH_RE.search(t2)
        if m:
            probs.append(f"emphasis word {m.group(0)!r} in <{kind}>: {t2[:70]!r}")
        m = CONTRAST_RE.search(t2)
        if m:
            probs.append(f"'X, not Y' contrast {m.group(0).strip()!r} in <{kind}>: {t2[:70]!r}")
        if kind in ("h2", "h3", "p"):
            m = LABEL_RE.match(t2)
            if m and len(m.group(1).split()) <= 3 and not re.search(r"[./_]", m.group(1)):
                probs.append(f"colon tagline {m.group(1) + ':'!r} opens a <{kind}>: {t2[:70]!r}")
            m = FRAGMENT_RE.search(t2)
            if m:
                probs.append(f"one-word verdict after a colon {m.group(0).strip()!r} in <{kind}>: {t2[:70]!r}")
            if ";" in t2:
                probs.append(f"semicolon-chained prose in <{kind}> (write two sentences): {t2[:70]!r}")
    v = box_text(re.sub(r'<sup class="ev">.*?</sup>', "", page, flags=re.S), "verdict")
    if v:
        v2 = re.sub(r"^Verdict\s*", "", v).strip()
        if ":" in v2:
            probs.append(f"verdict is a label and fragments, not a sentence: {v2[:80]!r}")
        elif v2.count(",") >= 3:
            probs.append(f"verdict is a chain of comma fragments; write one plain sentence: {v2[:80]!r}")
        elif not re.search(r"[.!?]$", v2):
            probs.append(f"verdict does not end as a sentence: {v2[:80]!r}")
    if probs:
        bad("voice", f"{len(probs)} tells: " + " | ".join(probs[:6]) + (" | …" if len(probs) > 6 else ""))
    else:
        ok("voice", f"{len(voice_blocks(page))} headings/paragraphs/items, no contrast, emphasis, em-dash, semicolon or colon-tagline tells; verdict is a sentence")


def check_problem_first(page, R, measure):
    """The report opens with the problem being solved and why it is worth solving, before the verdict (user, round 3)."""
    probs = []
    P = (R or {}).get("problem")
    if not isinstance(P, dict) or not (str(P.get("quote", "")).strip() or str(P.get("what", "")).strip()) or not str(P.get("why", "")).strip():
        probs.append('report.json has no "problem": {"quote" (or "what"), "why"}')
    i_p, i_v = page.find('id="problem"'), page.find('id="verdict"')
    if i_p < 0:
        probs.append("no #problem paragraph on the page")
    elif i_v >= 0 and i_p > i_v:
        probs.append("#problem comes after the verdict")
    txt = box_text(page, "problem")
    if 'class="problem quoted"' in page:
        # quoted ask: the quote is the user's verbatim words (any length); the "why" after it is one or two sentences
        m = re.search(r'id="problem".*?<span class="why">(.*?)</span></p>', page, re.S)
        why = visible_text(m.group(1)).strip() if m else ""
        if not why:
            probs.append("quoted ask has no 'why' sentence after it")
        txt = ""
        # the quote must make sense on its own: a pointer to a numbered item from an earlier page ("number 4",
        # "option 2") needs a [bracketed note] right after it saying what that item was (user, golden r3)
        q = re.sub(r"\[[^\]]*\]", "[]", str((P or {}).get("quote", "")))  # notes themselves are not scanned
        for m in re.finditer(r"\b(?:number|option|item|line|rec(?:ommendation)?|point|step)\s*#?\d+\b(?!\s*\[)", q, re.I):
            probs.append(f"quote points at {m.group(0)!r} without a [note] saying what it was")
        sents = [x for x in re.split(r"(?<=[.!?])\s+", why) if x]
        if len(sents) > 2:
            probs.append(f"why-it-matters line has {len(sents)} sentences (at most 2)")
    if txt:
        sents = [x for x in re.split(r"(?<=[.!?])\s+", txt.strip()) if x]
        if len(sents) < 2:
            probs.append(f"problem paragraph is one sentence; it needs the problem and why it is worth solving: {txt[:80]!r}")
        if len(sents) > 4:
            probs.append(f"problem paragraph has {len(sents)} sentences (at most 4)")
    if measure and 'class="problem quoted"' not in page:
        for q in measure.get("paragraphs", []):
            if q.get("box") == "problem" and q["lines"] > 4:
                probs.append(f"problem paragraph runs {q['lines']} lines at 390 px (at most 4)")
    if probs:
        bad("problem_first", "; ".join(probs))
    else:
        ok("problem_first", f"opens with the problem ({len(sents)} sentences) before the verdict")


def check_wrong_short(page, measure):
    """The Wrong-or-missing box stays a short list: at most 6 items, none over 2 lines at 390 px (aim one line each)."""
    m = re.search(r'<div id="wrong-or-missing".*?</div>', page, re.S)
    items = re.findall(r"<li>(.*?)</li>", m.group(0) if m else "", re.S)
    probs = []
    if len(items) > 6:
        probs.append(f"{len(items)} items (at most 6; details go in a section that supports the verdict)")
    if measure:
        long = [q for q in measure.get("paragraphs", []) if q.get("box") == "wrong-or-missing" and q["lines"] > 2]
        for q in long:
            probs.append(f"item runs {q['lines']} lines at 390 px: {q['text'][:60]!r}")
        one = sum(1 for q in measure.get("paragraphs", []) if q.get("box") == "wrong-or-missing" and q["lines"] <= 1)
    else:
        one = "?"
    for it in items:
        t = re.sub(r"\s+", " ", H.unescape(re.sub(r"<[^>]+>", " ", it))).strip()
        if re.search(r"\.json\b", t):
            probs.append(f"item names a .json file or field (say it in words; the file goes in a section): {t[:60]!r}")
        nfig = len(re.findall(r'class="n[^"]*" data-key=', it))
        if nfig > 2:
            probs.append(f"item carries {nfig} figures (at most two, the two sides of a conflict; the rest go in a section): {t[:60]!r}")
    if probs:
        bad("wrong_short", "; ".join(probs))
    else:
        ok("wrong_short", f"{len(items)} items, {one} of them one line at 390 px, none over 2")


def check_first_once(page):
    """Card 1 says each figure once: verdict, deciding number and the decision chart's reading share no key (user: "wall of AI text")."""
    blocks = {}
    for el in ("verdict", "deciding"):
        m = re.search(rf'<[^>]+id="{el}"[^>]*>(.*?)</(div|p)>', page, re.S)
        blocks[el] = m.group(1) if m else ""
    m = re.search(r'id="decision-chart".*?<p class="reading">(.*?)</p>', page, re.S)
    blocks["reading"] = m.group(1) if m else ""
    keys = {b: set(re.findall(r'class="n[^"]*" data-key="([^"]+)"', t)) for b, t in blocks.items()}
    probs = []
    names = list(keys)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            for k in sorted(keys[a] & keys[b]):
                probs.append(f"{k} printed in both the {a} and the {b}")
    if probs:
        bad("first_once", "; ".join(probs))
    else:
        ok("first_once", f"verdict {len(keys['verdict'])}, deciding {len(keys['deciding'])}, reading {len(keys['reading'])} figures, none repeated")


def check_axis_note(page, R):
    probs, n_above = [], 0
    pairs = charts(page, R)
    if not pairs:
        bad("axis_note", "no bars chart on the page")
        return
    for i, (svg, spec) in enumerate(pairs):
        m = re.search(r'data-axis-min="([\d.eE+-]+)"', svg)
        amin = float(m.group(1)) if m else 0.0
        title = (spec or {}).get("title") or re.search(r'aria-label="([^"]*)"', svg).group(1)
        if spec is not None and float(spec.get("axis_min", 0) or 0) != amin:
            probs.append(f"chart {i + 1} ({title!r}): report.json axis_min {spec.get('axis_min')} but the SVG says {amin:g}")
        if amin <= 0:
            continue
        n_above += 1
        note = re.search(r'class="axisnote">([^<]*)<', svg)
        if not note or "axis does not start at 0" not in note.group(1):
            probs.append(f"chart {i + 1} ({title!r}): axis_min {amin:g} but no '(axis does not start at 0)' axis label")
        bars = len(re.findall(r'<rect [^>]*class="bar[ "]', svg))
        breaks = len(re.findall(r'class="break"', svg))
        if breaks < bars:
            probs.append(f"chart {i + 1} ({title!r}): {bars} bars but {breaks} break marks")
        if spec is None:
            probs.append(f"chart {i + 1} ({title!r}): cannot pair with report.json (chart count differs), axis_reason unchecked")
        elif not str(spec.get("axis_reason", "")).strip():
            probs.append(f"chart {i + 1} ({title!r}): axis_min {amin:g} > 0 but no axis_reason in report.json")
    if probs:
        bad("axis_note", "; ".join(probs))
    else:
        ok("axis_note", f"{len(pairs)} bars charts, {n_above} with an axis above 0, each labelled with break marks and a reason")


def parse_expected_n(path):
    """TRAPS.md table under 'Expected n per candidate': rows | <pattern or pattern> | <n> | <source> |, in order."""
    rows, inside = [], False
    for line in open(path, encoding="utf-8"):
        if line.startswith("#"):
            inside = "expected n per candidate" in line.lower()
            continue
        if not inside or not line.startswith("|") or line.startswith("|--"):
            continue
        cells = [c.strip().strip("`") for c in line.strip().strip("|").split("|")]
        if len(cells) >= 2 and cells[1].isdigit():
            rows.append(([w.strip().lower() for w in cells[0].split(" or ")], int(cells[1]), cells[2] if len(cells) > 2 else ""))
    return rows


def decision_rows(page):
    """[(name, [change, spread, n, verdict])] from the rendered decision table."""
    out = []
    for name, body in re.findall(r'<tr data-row="([^"]+)">(.*?)</tr>', page, re.S):
        cells = [re.sub(r"\s+", " ", visible_text(c)).strip() for c in re.findall(r"<td>(.*?)</td>", body, re.S)]
        out.append((H.unescape(name), cells[1:] if len(cells) == 5 else cells))
    return out


def check_most_runs(page, traps_path):
    if not traps_path or not os.path.exists(traps_path):
        ok("most_runs", "no TRAPS.md given, skipped")
        return
    expected = parse_expected_n(traps_path)
    if not expected:
        ok("most_runs", "TRAPS.md has no 'Expected n per candidate' table, skipped")
        return
    probs, seen = [], 0
    for name, cells in decision_rows(page):
        low = name.lower()
        exp = next(((n, src) for pats, n, src in expected if any(p in low for p in pats)), None)
        if exp is None or len(cells) < 3:
            continue
        seen += 1
        m = re.search(r"\d+", cells[2])
        got = int(m.group(0)) if m else 0
        if got < exp[0]:
            probs.append(f"row {name!r}: n = {cells[2]!r} but the fixture holds {exp[0]} runs ({exp[1]})")
    if probs:
        bad("most_runs", "; ".join(probs))
    else:
        ok("most_runs", f"{seen} rows use the source with the most runs")


def check_modes_match(page, other_path):
    if not other_path:
        ok("modes_match", "no --other page given, skipped")
        return
    if not os.path.exists(other_path):
        bad("modes_match", f"{other_path} not found (build the other mode first)")
        return
    a = decision_rows(page)
    b = decision_rows(open(other_path, encoding="utf-8").read())
    if a == b:
        ok("modes_match", f"decision table identical in both modes ({len(a)} rows)")
        return
    diffs = []
    for (na, ca), (nb, cb) in zip(a, b):
        if na != nb:
            diffs.append(f"row {na!r} vs {nb!r}")
        for lab, x, y in zip(("change", "spread", "n", "verdict"), ca, cb):
            if x != y:
                diffs.append(f"{na} {lab}: {x!r} vs {y!r}")
    if len(a) != len(b):
        diffs.append(f"{len(a)} vs {len(b)} rows")
    bad("modes_match", "; ".join(diffs[:6]))


def check_checker_line(page, outdir):
    m = re.search(r'<p id="checked"[^>]*>(.*?)</p>', page, re.S)
    t = visible_text(m.group(1)) if m else ""
    probs = []
    cm = re.search(r"checker: (.*?)(?:;|$)", t)
    if not cm:
        probs.append("the 'How this was checked' line has no 'checker:' part")
    else:
        for w in ("loop", "raised", "fixed", "open"):
            if w not in cm.group(1):
                probs.append(f"checker part lacks '{w}': {cm.group(1)[:80]!r}")
    fp = os.path.join(outdir, "checker", "findings.json")
    if not os.path.exists(fp):
        probs.append("checker/findings.json missing")
    else:
        try:
            f = json.load(open(fp))
            if not isinstance(f, list):
                probs.append("checker/findings.json is not a list")
        except ValueError as ex:
            probs.append(f"checker/findings.json unreadable: {ex}")
    if not os.path.exists(os.path.join(outdir, "checker", "cold.md")):
        probs.append("checker/cold.md missing")
    if probs:
        bad("checker_line", "; ".join(probs))
    else:
        ok("checker_line", cm.group(1)[:80])


def check_checked_line(page, N):
    m = re.search(r'<p id="checked"[^>]*>(.*?)</p>', page, re.S)
    if not m:
        bad("checked_line", "no 'How this was checked' line")
        return
    t = visible_text(m.group(1))
    after = visible_text(page[m.end():]).strip()
    if str(len(N)) not in t:
        bad("checked_line", f"does not name the numbers.json count {len(N)}: {t[:80]}")
    elif "check.py" not in t:
        bad("checked_line", "does not name the check.py result")
    elif after:
        bad("checked_line", f"is not the last line of the page (text after it: {after[:60]!r})")
    else:
        ok("checked_line", t[:100])



# ---------- --prose: a hand-written report (golden round 4) --------------------------------------------------------------
INFLATED_RE = re.compile(r"\b(pivotal|crucial|robust|delve[sd]?|delving|showcas\w*|serves? as|testament|landscape|leverag\w*|seamless\w*|game-?changer|unlock\w*|elevat\w*|navigat\w*|multifaceted|tapestry|harness\w*)\b", re.I)
TRIPLET_RE = re.compile(r"(?<![\w.])[\w'-]+(?: [\w'-]+)?, [\w'-]+(?: [\w'-]+)?,? (?:and|or) [\w'-]+(?: [\w'-]+)?(?=[.,;:)]|$)", re.I)


def prose_paragraphs(page):
    """(text, html) of every <p>/<li>/<figcaption> outside the ask quote and the who line"""
    page = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", page, flags=re.S)
    out = []
    for m in re.finditer(r"<(p|li|figcaption)\b[^>]*>(.*?)</\1>", page, re.S):
        body = m.group(2)
        if 'class="who"' in body:
            continue
        out.append((visible_text(re.sub(r'<q class="ask">.*?</q>', " ", body, flags=re.S)), body))
    return out


def check_traps_prose(page, traps_path):
    """every trap is stated plainly in one paragraph (all its flag words together); its number appears only there"""
    if not traps_path or not os.path.exists(traps_path):
        ok("traps", "no TRAPS.md given, skipped")
        return
    traps = parse_traps(traps_path)
    paras = [t.lower() for t, _ in prose_paragraphs(page)]
    probs = []
    for t in traps:
        stated = [p for p in paras if all(any(a.lower() in p for a in alts) for alts in t["flags"])]
        if not stated:
            probs.append(f"trap {t['n']} ({t['desc'][:30]}): no paragraph says {' + '.join(a[0] for a in t['flags'])} together")
        for n in t["nums"]:
            for p in paras:
                if re.search(rf"(?<![\d.]){re.escape(n)}(?![\d])", p) and p not in stated:
                    probs.append(f"trap {t['n']}: {n} appears in a paragraph that does not flag it: {p[:60]!r}")
    if probs:
        bad("traps", "; ".join(probs))
    else:
        ok("traps", f"{len(traps)} traps each stated plainly in the body, numbers only beside their flags")


def check_voice_prose(page):
    """the plan's bans on top of check_voice: inflated words, rule-of-three, bold beyond one IMPORTANT, em dashes anywhere"""
    probs = []
    txt_all = visible_text(re.sub(r'<q class="ask">.*?</q>', " ", page, flags=re.S))
    if "—" in txt_all:
        probs.append("em dash on the page")
    bold = re.findall(r"<(?:strong|b)\b[^>]*>(.*?)</(?:strong|b)>", page, re.S)
    if len(bold) > 1 or any(not visible_text(b).strip().startswith("IMPORTANT") for b in bold):
        probs.append(f"bold {len(bold)}x beyond one IMPORTANT: {[visible_text(b)[:20] for b in bold][:3]}")
    for kind, t in voice_blocks(page):
        m = INFLATED_RE.search(t)
        if m:
            probs.append(f"inflated word {m.group(0)!r} in <{kind}>: {t[:60]!r}")
        t_nonum = NUM_RE.sub(" ", t)
        m = TRIPLET_RE.search(t_nonum)
        if m:
            probs.append(f"rule of three {m.group(0)!r} in <{kind}>: {t[:60]!r}")
    if probs:
        bad("voice_prose", f"{len(probs)}: " + " | ".join(probs[:6]))
    else:
        ok("voice_prose", "no inflated words, rule-of-three lists, bold or em dashes")


def check_prose_shape(page):
    """the ask is quoted (with where it was said) in the first card; no verdict box, caveats box or decision table"""
    probs = []
    cards = re.findall(r'<section class="card"[^>]*>(.*?)</section>', page, re.S)
    if len(cards) < 2:
        probs.append(f"{len(cards)} cards")
    if not cards or '<q class="ask">' not in cards[0]:
        probs.append("first card has no <q class=\"ask\">")
    if not cards or 'class="who"' not in cards[0]:
        probs.append("first card has no who line")
    for el in ("verdict", "wrong-or-missing", "decision-table", "next-action"):
        if f'id="{el}"' in page:
            probs.append(f"#{el} on a prose page")
    if page.count("📚") > 1:
        probs.append("sources named more than once")
    if probs:
        bad("prose_shape", "; ".join(probs))
    else:
        ok("prose_shape", f"{len(cards)} cards; ask quoted with its who line on the first; no verdict/caveat boxes")


# ---------- --prose: AI tells (docs/ai-tells.md, round 5) ---------------------------------------------------------------
AI_TELLS = [  # (name, regex on one sentence); the sentence is matched after NUM_RE strips figures. Numbers = docs/ai-tells.md
    ("here_is", re.compile(r"^(Here (is|are)|Here's)\b")),  # 2
    ("x_then", re.compile(r", then[.!?]?$")),  # 5
    ("call_it", re.compile(r"\bCall it\b")),  # 2
    ("rest_of_this", re.compile(r"^The rest of this\b")),  # 2
    ("run_id_subject", None),  # 4: filled per report from numbers.json run names (see run_id_regex)
    ("rather_than", re.compile(r"\brather than\b", re.I)),  # 6
    ("not_only", re.compile(r"\bnot only\b", re.I)),  # 6
    ("in_conclusion", re.compile(r"^(In (conclusion|summary|short)|To sum up|Overall|All in all|Ultimately)\b", re.I)),  # 10
    ("rule_of_three", TRIPLET_RE),  # 7
    ("brochure", re.compile(r"\b(pivotal moment|this matters because|walks? you through|game-?changer|a big deal|the bottom line)\b", re.I)),  # 9
    ("hedge_sandwich", re.compile(r"\b(despite (the |these |its )?challenges|it is worth noting|worth noting that|while .{3,40} is important)\b", re.I)),  # 11
    ("vague_attribution", re.compile(r"\b(experts? (say|agree|suggest)|it is widely (known|accepted)|studies (show|suggest)|research shows|many (people|users) (say|think|believe))\b", re.I)),  # 12
    ("didactic_aside", re.compile(r"^(Read that (twice|again)|Note that|Notice that|Think about that|Let that sink in|Remember that|Keep in mind)\b", re.I)),  # 16
    ("stock_opener", re.compile(r"\b(In today's world|Let's dive in|Here's the thing|At the end of the day|I hope this helps|Without further ado|It goes without saying|Needless to say)\b", re.I)),  # 19
    ("hedge_stack", re.compile(r"\b(it may be the case that|potentially|to some extent|arguably|in some sense|it could be argued|more or less)\b", re.I)),  # 24
    ("emphasis_filler", EMPH_RE),  # 20
]
RUN_ID_FALLBACK = re.compile(r"^r9[a-z0-9-]*\b")


def run_id_regex(N):
    """tell 4: the run names numbers.json cites (and r9… IDs) may not start a sentence"""
    names = sorted({str(e.get("run")) for e in N.values() if e.get("run") and re.search(r"[-_\d]", str(e["run"])) and " " not in str(e["run"])}, key=len, reverse=True)
    if not names:
        return RUN_ID_FALLBACK
    return re.compile(r"^(?:r9[a-z0-9-]*|" + "|".join(re.escape(n) for n in names) + r")\b")


SENT_RE = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9“\"(r])")


def sentences(text):
    """split a paragraph into sentences; a figure like 12.59 s or an ID like r9-ab-tail-1 never splits"""
    t = re.sub(r"\s+", " ", text).strip()
    return [s.strip() for s in SENT_RE.split(t) if s.strip()]


def check_ai_tells(page, N=None):
    """docs/ai-tells.md, the mechanical ones (numbers = the tell in that file): 1 fragments, 2 narrating the text, 5 'X,
    then.', 4 run IDs as subjects, 6 'rather than'/'not only', 10 summary openers, 7 rule of three, 9 brochure, 11 hedge
    sandwich, 12 vague attribution, 16 didactic aside, 19 stock opener, 24 hedge stack, 20 emphasis filler, 25 question
    heading answered with one word; plus style.md's sentence length (over 45 words)"""
    probs = []
    rid = run_id_regex(N or {})
    blocks = voice_blocks(page)
    for i, (kind, t) in enumerate(blocks):
        if kind in ("h2", "h3") and t.rstrip().endswith("?") and i + 1 < len(blocks):
            nxt = blocks[i + 1][1].strip()
            if re.match(r"^(Yes|No|Faster|Slower|Plenty|Barely|Hardly|Partly|Mostly|Both|Neither)[.,:!]", nxt):
                probs.append(f"question heading answered with a verdict word: {t!r} → {nxt[:30]!r}")
        if kind not in ("p", "li", "figcaption"):
            continue
        if t.startswith("📚") or t.startswith("Sources") or t.startswith("checker:"):
            continue
        for s in sentences(t):
            words = [w for w in re.findall(r"[\w'’.%−+-]+", s) if re.search(r"\w", w)]
            if len(words) < 4 and not re.match(r"^\(chart:", s):
                probs.append(f"fragment {s!r}")
            if len(words) > 45:
                probs.append(f"sentence of {len(words)} words: {s[:50]!r}")
            s2 = NUM_RE.sub(" ", s).strip()
            for name, rx in AI_TELLS:
                if name == "run_id_subject":
                    m = rid.search(s)
                else:
                    m = rx.search(s2)
                if m:
                    probs.append(f"{name} {m.group(0).strip()!r} in {s[:60]!r}")
    if probs:
        bad("ai_tells", f"{len(probs)}: " + " | ".join(probs[:8]) + (" | …" if len(probs) > 8 else ""))
    else:
        ok("ai_tells", f"{len(AI_TELLS) + 3} tells coded, none found (fragments, text-narration, run-ID subjects, contrast frames, summary openers, brochure, hedges, asides, question-heading verdicts, long sentences)")


def card_sections(page):
    return re.findall(r'<section class="card"[^>]*>(.*?)</section>', page, re.S)


QUESTION = ""


def check_card1(page, measure):
    """R3/R5: the first card holds the ask quote with its who line, a [note] when the ask points ("number 4", "that
    one"), the microcosm (a paragraph with a figure and an identifier or clock time) and the "But" paragraph with two
    figure spans and an n, all within one 844 css px phone screen"""
    cards = card_sections(page)
    if not cards:
        bad("card1", "no cards")
        return
    c = cards[0]
    probs = []
    q = re.search(r'<q class="ask">(.*?)</q>', c, re.S)
    if not q:
        probs.append("no ask quote")
    else:
        qt = visible_text(q.group(1))
        if re.search(r"\b(number \d+|#\d+|that one|the (first|second|third|last) (one|option)|this one|option \d+)\b", qt, re.I) and "[" not in qt:
            # a pointer: a [bracketed note] in the quote, or a label line (short paragraph right after the who line)
            after_who = c.split('class="who"', 1)[-1]
            lab = re.search(r"<p[^>]*>(.*?)</p>", after_who, re.S)
            lab_t = visible_text(lab.group(1)).strip() if lab else ""
            if not lab_t or len(lab_t.split()) > 12 or 'class="n"' in (lab.group(1) if lab else ""):
                probs.append(f"the ask points at something ({qt[:40]!r}) and carries no [bracketed note] or label line")
        if re.search(r"\b(candidates?|options?)\b|which (one|of)", qt + " " + QUESTION, re.I):
            # the ask names options: a label line of at most six words, no figure, right after the who line (R3)
            after_who = c.split('class="who"', 1)[-1]
            lab = re.search(r"<p[^>]*>(.*?)</p>", after_who, re.S)
            lab_t = visible_text(lab.group(1)).strip() if lab else ""
            if not lab_t or len(lab_t.split()) > 6 or 'class="n"' in (lab.group(1) if lab else ""):
                probs.append(f"the ask names candidates but no label line of at most six words follows the who line (found {lab_t[:60]!r})")
    if 'class="who"' not in c:
        probs.append("no who line")
    paras = [visible_text(b).strip() for b in re.findall(r"<p(?![^>]*class=\"who\")[^>]*>(.*?)</p>", c, re.S)]
    paras = [p for p in paras if p]
    but = [p for p in paras if re.match(r"^But\b", p)]
    if not but:
        probs.append('no paragraph starting "But"')
    else:
        b = but[0]
        html_b = next(h for h in re.findall(r"<p[^>]*>(.*?)</p>", c, re.S) if visible_text(h).strip() == b)
        nsp = len(re.findall(r'class="n"', html_b))
        if nsp < 3:
            probs.append(f'"But" paragraph has {nsp} figure spans, needs two means and n')
        if not re.search(r"\bn\s*=|\bn of\b|\bruns? a side\b|\bruns? each\b|\beach of\b", b):
            probs.append('"But" paragraph does not state n')
    phtml = [h for h in re.findall(r"<p(?![^>]*class=\"who\")[^>]*>(.*?)</p>", c, re.S) if visible_text(h).strip()]
    micro = [h for h in phtml if not re.match(r"^But\b", visible_text(h).strip()) and 'class="n"' in h and re.search(r"\d\d?:\d\d|\((?:[a-z0-9]+[-_])+[a-z0-9]+\)|\b(generation|gen|run|task|week|round|session|day|cycle|build)\b", visible_text(h), re.I)]
    if not micro:
        probs.append("no microcosm paragraph (a figure plus a named unit: generation, run, task, week, or a clock time)")
    if measure and measure.get("cards"):
        h = measure["cards"][0]["css_height_px"]
        if h > 844:
            probs.append(f"first card is {h} css px, over one 844 px phone screen")
    if probs:
        bad("card1", "; ".join(probs))
    else:
        ok("card1", f"quote, who line, microcosm and \"But\" with {nsp} figures on card 1" + (f" ({measure['cards'][0]['css_height_px']} css px)" if measure and measure.get('cards') else ""))


def check_no_summary_sections(page):
    """no section titled caveats, summary, verdict, conclusion, wrong or missing, next action"""
    heads = [visible_text(h).strip() for h in re.findall(r"<h[1-3][^>]*>(.*?)</h[1-3]>", page, re.S)]
    badh = [h for h in heads if re.search(r"\b(caveats?|summary|verdict|conclusions?|wrong or missing|next action|limitations?|tl;?dr|takeaways?)\b", h, re.I)]
    if badh:
        bad("no_summary_sections", f"headings: {badh}")
    else:
        ok("no_summary_sections", f"{len(heads)} headings, none a caveats/summary/verdict section")


def microcosm_markers(page):
    """identifiers of the microcosm paragraph on card 1: its <span class=id> texts, run IDs in parentheses, clock times"""
    cards = card_sections(page)
    if not cards:
        return []
    marks = []
    for h in re.findall(r"<p(?![^>]*class=\"who\")[^>]*>(.*?)</p>", cards[0], re.S):
        t = visible_text(h).strip()
        if re.match(r"^But\b", t) or 'class="n"' not in h:
            continue
        for m in re.finditer(r'(?:([A-Za-z]+)\s+)?<span class="id">(.*?)</span>', h):
            ident = visible_text(m.group(2)).strip()
            if re.fullmatch(r"\d{1,3}", ident):
                # a bare number ("[[7]]") is only a marker with the word before it: "generation 7", never "7"
                if m.group(1):
                    marks.append(f"{m.group(1)} {ident}")
            else:
                marks.append(ident)
        marks += re.findall(r"\(((?:[a-z0-9]+[-_])+[a-z0-9]+)\)", t)
        marks += re.findall(r"\b\d\d?:\d\d\b", t)
        if marks:
            break
    return [m for m in marks if m]


def mark_re(m):
    """a microcosm marker as a regex: whole-token, case-blind, any run of spaces between its words"""
    return re.compile(r"(?<![\w-])" + r"\s+".join(re.escape(w) for w in m.split()) + r"(?![\w-])", re.I)


def check_ending(page):
    """the ending (last body paragraphs before the sources line) names the microcosm's unit again"""
    marks = microcosm_markers(page)
    paras = [t for t, _ in prose_paragraphs(page) if t.strip() and not t.startswith("📚") and not t.startswith("checker:")]
    if not marks:
        bad("ending", "could not find the microcosm's identifiers on card 1 (an [[ident]], a run ID in parentheses or a clock time)")
        return
    tail = " ".join(paras[-4:])
    hit = [m for m in marks if mark_re(m).search(tail)]
    if not hit:
        bad("ending", f"the last paragraphs do not name the microcosm's unit ({marks[:4]}): {tail[:80]!r}")
    else:
        ok("ending", f"ending returns to the microcosm ({hit[0]!r})")


DEF_RE = re.compile(r"(?:, the | \(that is, |, meaning |, which is |, which means |, i\.e\. )([a-z][a-z' -]+(?: [a-z][a-z' -]+){3,})")


def check_terms_once(page):
    """a defining clause (", the stretch after…", "(that is, …") appears once: the same six-word run of a definition twice is a term defined twice"""
    seen, dup = {}, []
    for t, _ in prose_paragraphs(page):
        for m in DEF_RE.finditer(NUM_RE.sub(" ", t)):
            words = m.group(1).split()
            key = " ".join(words[:6]).lower()
            if key in seen:
                dup.append(key)
            seen[key] = 1
    if dup:
        bad("terms_once", f"defined twice: {dup[:4]}")
    else:
        ok("terms_once", f"{len(seen)} defining clauses, each once")


# ---------- --prose: round of 2026-10-21 amendments (INVESTIGATION.md in agent-eval-experiment/report-writer) ---------------
def first_card_blocks(page):
    """top-level blocks of card 1 after the <h1>, as (tag, html) in order"""
    cards = card_sections(page)
    if not cards:
        return []
    c = re.sub(r"^.*?</h1>", "", cards[0], count=1, flags=re.S)
    return [(m.group(1), m.group(0)) for m in re.finditer(r"<(blockquote|p|h2|h3|figure|ul|ol)\b[^>]*>.*?</\1>", c, re.S)]


def question_sentences():
    """sentences of eight words or more from the study's question.txt (the decision question the writer answers, never quotes)"""
    return [re.sub(r"\s+", " ", q).strip().lower() for q in re.split(r"(?<=[.?!])\s+|\n", QUESTION) if len(q.split()) >= 8]


def check_ask_quote(page):
    """the first quote is the user's own words: the who line names the user (you / a name / the user) and not question.txt,
    the quote is at most 60 words, and no sentence of question.txt appears inside it (INVESTIGATION difference 1)"""
    cards = card_sections(page)
    if not cards:
        bad("ask_quote", "no cards")
        return
    q = re.search(r'<q class="ask">(.*?)</q>', cards[0], re.S)
    who = re.search(r'<p class="who">(.*?)</p>', cards[0], re.S)
    if not q or not who:
        bad("ask_quote", "card 1 has no ask quote with a who line")
        return
    qt = re.sub(r"\s+", " ", visible_text(q.group(1))).strip()
    wt = visible_text(who.group(1)).strip()
    probs = []
    n = len(qt.split())
    if n > 60:
        probs.append(f"quote is {n} words (the user's ask, not the study's question; 60 at most)")
    if re.search(r"question\.txt|README|PROTOCOL", wt, re.I):
        probs.append(f"who line names a file as the speaker: {wt[:60]!r}")
    if not re.search(r"\b(you|the user|jaxon|he|she|they)\b", wt, re.I) and not re.search(r"^[A-Z][a-z]+,", wt):
        probs.append(f"who line does not name who spoke: {wt[:60]!r}")
    low = qt.lower()
    hits = [qs for qs in question_sentences() if qs.rstrip(".?") in low]
    if hits:
        probs.append(f"quote repeats question.txt: {hits[0][:60]!r}")
    if probs:
        bad("ask_quote", "; ".join(probs))
    else:
        ok("ask_quote", f"{n}-word quote of the user's words, said by {wt.split(',')[0]!r}")


def check_lead_answer(page):
    """card 1 leads with the answer, not with the question: the first block after the title is either a plain paragraph
    carrying a figure (the answer line) or the user's own ask quote (ask_quote passes); a question.txt block or a question
    first is a FAIL (INVESTIGATION difference 2)"""
    blocks = first_card_blocks(page)
    if not blocks:
        bad("lead_answer", "card 1 has no blocks after the title")
        return
    tag, html = blocks[0]
    text = visible_text(html).strip()
    title = visible_text((re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S) or re.search(r"()", "")).group(1)).strip()
    probs = []
    if "?" in title:
        probs.append(f"title asks a question: {title!r}")
    if tag == "p":
        if 'class="n"' not in html:
            probs.append(f"first paragraph carries no figure, so it is not the answer: {text[:60]!r}")
        if text.rstrip().endswith("?"):
            probs.append(f"first paragraph is a question: {text[:60]!r}")
        if re.match(r"^But\b", text):
            probs.append("first paragraph is the \"But\"")
    elif tag == "blockquote":
        qt = re.sub(r"\s+", " ", visible_text(html)).strip()
        who = re.search(r'<p class="who">(.*?)</p>', card_sections(page)[0], re.S)
        wt = visible_text(who.group(1)) if who else ""
        if len(qt.split()) > 60 or re.search(r"question\.txt", wt, re.I) or any(qs.rstrip(".?") in qt.lower() for qs in question_sentences()):
            probs.append(f"the first box is the study's question, not the user's ask or the answer: {qt[:60]!r}")
    else:
        probs.append(f"first block is a <{tag}>")
    if probs:
        bad("lead_answer", "; ".join(probs))
    else:
        ok("lead_answer", "card 1 opens with " + ("the answer line" if tag == "p" else "the user's own ask") + f" under {title!r}")


def check_headings_ask(page):
    """one puzzle, one thread: every section heading but the last asks the question the section settles (ends with ?),
    and no two headings ask the same question (INVESTIGATION difference 3)"""
    heads = [visible_text(h).strip() for h in re.findall(r"<h2[^>]*>(.*?)</h2>", page, re.S)]
    if len(heads) < 2:
        bad("headings_ask", f"{len(heads)} section heading(s); a thread needs at least two sections")
        return
    body, last = heads[:-1], heads[-1]
    flat = [h for h in body if not h.rstrip().endswith("?")]
    if flat:
        bad("headings_ask", f"{len(flat)} of {len(body)} section headings state a topic instead of asking the next question: {flat[:3]}")
        return
    keys = [re.sub(r"[^a-z ]", "", h.lower()).strip() for h in body]
    if len(set(keys)) < len(keys):
        bad("headings_ask", "two sections ask the same question")
        return
    ok("headings_ask", f"{len(body)} question headings, then {last!r}")


def check_microcosm_thread(page):
    """the microcosm's unit (its [[ident]], run ID or clock time from card 1) is picked up again in at least one middle
    section, so the sections follow the same unit instead of surveying the arms (INVESTIGATION difference 4)"""
    marks = microcosm_markers(page)
    if not marks:
        bad("microcosm_thread", "no microcosm identifiers on card 1")
        return
    secs = re.split(r"<h2[^>]*>", page)[1:]
    mid = secs[:-1]
    if not mid:
        bad("microcosm_thread", "fewer than two sections")
        return
    hit = [i for i, s in enumerate(mid) if any(mark_re(m).search(visible_text(s)) for m in marks)]
    if not hit:
        bad("microcosm_thread", f"none of the {len(mid)} middle sections names the microcosm's unit ({marks[:3]})")
    else:
        ok("microcosm_thread", f"the microcosm's unit ({marks[0]!r}) returns in {len(hit)} of {len(mid)} middle sections")


def check_checker_line_prose(page, outdir, no_checker_ok=True):
    """last line prints 'checker: N loops, N raised, N fixed, N open; checker tokens N, wall N s' or 'checker: off'"""
    m = re.search(r'<p[^>]*id="checked"[^>]*>(.*?)</p>', page, re.S)
    if not m:
        bad("checker_line", "no checker line (::checker in report.md)")
        return
    t = visible_text(m.group(1)).strip()
    after = visible_text(page[m.end():]).strip()
    if after:
        bad("checker_line", f"not the last line: {after[:40]!r}")
        return
    if t == "checker: off":
        ok("checker_line", "checker: off")
        return
    need = ("loop", "raised", "fixed", "open", "tokens", "wall")
    miss = [w for w in need if w not in t]
    fp = os.path.join(outdir, "checker", "findings.json")
    if miss:
        bad("checker_line", f"lacks {miss}: {t[:80]!r}")
    elif not os.path.exists(fp):
        bad("checker_line", "checker/findings.json missing")
    elif not os.path.exists(os.path.join(outdir, "checker", "cold.md")):
        bad("checker_line", "checker/cold.md missing")
    else:
        ok("checker_line", t[:90])


def check_figures_resolve(outdir, N):
    """every {key} in report.md is a numbers.json key; every derived key names existing keys"""
    src = os.path.join(outdir, "report.md")
    if not os.path.exists(src):
        bad("figures", "no report.md")
        return
    txt = open(src, encoding="utf-8").read()
    keys = re.findall(r"\{([A-Za-z0-9_]+)@?\}", txt)
    missing = sorted({k for k in keys if k not in N})
    bad_derived = {k: [x for x in e["derived"].get("of", []) if x not in N] for k, e in N.items() if "derived" in e}
    bad_derived = {k: v for k, v in bad_derived.items() if v}
    # digits typed in prose: outside {key}, [[ident]], the quote, the who line, the ::checker line, code spans and the sources line
    body = re.sub(r"\{[A-Za-z0-9_]+@?\}|\[\[.*?\]\]|`[^`]*`|\[[^\]]*\]", " ", txt)
    loose = []
    for line in body.splitlines():
        if line.startswith(("> ", "~ ", "::", "📚", "#")):
            continue
        for mm in NUM_RE.finditer(line):
            if not ALLOW.match(mm.group(0)):
                loose.append(f"{mm.group(0)!r} in {line.strip()[:50]!r}")
    if missing or bad_derived or loose:
        bad("figures", f"unknown keys {missing[:6]}; derived of unknown {bad_derived}; digits typed in prose: {loose[:5]}")
    else:
        ok("figures", f"{len(set(keys))} keys in report.md all resolve; no digit typed in prose")


def check_expected(outdir, N, page, exp_path, traps_path):
    """--expected expected.json: deciding figures within tolerance, the ask's state words in the ending, trap list complete"""
    if not exp_path or not os.path.exists(exp_path):
        return
    E = json.load(open(exp_path))
    probs = []
    by_label = {}
    for k, e in N.items():
        by_label.setdefault((e.get("label") or "").strip().lower(), []).append((k, e.get("value")))
    for f in E.get("figures", []):
        tol = f.get("tol", 0)
        cands = []
        if f.get("key") in N:
            cands.append((f["key"], N[f["key"]].get("value")))
        cands += by_label.get(f.get("label", "").strip().lower(), [])
        # any key whose value is within tolerance also counts (the writer may name the key differently); a share may be
        # stored as a fraction or a percentage
        near = lambda v: isinstance(v, (int, float)) and min(abs(abs(v) - abs(f["value"])) if f.get("sign") == "either" else abs(v - f["value"]), abs(v * 100 - f["value"]), abs(v / 100 - f["value"])) <= tol + 1e-9
        if not any(near(v) for _, v in cands):
            cands = [(k, e.get("value")) for k, e in N.items() if near(e.get("value"))]
        hit = [k for k, v in cands if near(v)]
        if not hit:
            probs.append(f"{f.get('label') or f.get('key')}: expected {f['value']}±{tol}, no figure within tolerance")
    txt = visible_text(page).lower()
    tail = " ".join(t for t, _ in prose_paragraphs(page) if t.strip())[-1500:].lower()
    body = " ".join(t for t, _ in prose_paragraphs(page) if t.strip()).lower()
    for i, w in enumerate(E.get("state_words", [])):   # a string, or a list of wordings that all mean the same state
        alts = [w] if isinstance(w, str) else list(w)
        where = tail if i == 0 else body   # the first state (the ask's answer) in the ending; the others anywhere in the body
        if not any(a.lower() in where for a in alts):
            probs.append(f"state word {alts[0]!r} missing from the {'ending' if i == 0 else 'body'}")
    if traps_path and os.path.exists(traps_path):
        for t in parse_traps(traps_path):
            if not all(any(a.lower() in txt for a in alts) for alts in t["flags"]):
                probs.append(f"trap {t['n']} flag words not all on the page")
    if probs:
        bad("expected", "; ".join(probs[:6]))
    else:
        ok("expected", f"{len(E.get('figures', []))} figures within tolerance, state words {E.get('state_words')} present, traps complete")


def check_most_runs_prose(N, traps_path):
    """(--traps) for each candidate in TRAPS.md's 'Expected n per candidate' table, some numbers.json n-figure for it is at
    least that n (a smaller n means a file with fewer runs decided it)"""
    if not traps_path or not os.path.exists(traps_path):
        ok("most_runs", "no TRAPS.md given, skipped")
        return
    exp = parse_expected_n(traps_path)
    if not exp:
        ok("most_runs", "TRAPS.md has no Expected n table, skipped")
        return
    probs = []
    for pats, n, src in exp:
        ns = []
        for k, e in N.items():
            lab = (e.get("label") or "").lower()
            name = lab + " " + k.lower().replace("_", " ")
            if any(pt in name for pt in pats) and re.search(r"\bn\b|runs|count", name) and isinstance(e.get("value"), (int, float)):
                ns.append(e["value"])
        if ns and max(ns) < n:
            probs.append(f"{' or '.join(pats)}: n {max(ns)} shown, {n} runs exist ({src})")
    if probs:
        bad("most_runs", "; ".join(probs))
    else:
        ok("most_runs", f"{len(exp)} candidates, no n below the file with most runs")


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    outdir = a[0]
    here = os.path.dirname(os.path.abspath(__file__))
    data = a[a.index("--data") + 1] if "--data" in a else os.path.join(here, "fixture", "data")
    traps = a[a.index("--traps") + 1] if "--traps" in a else (os.path.join(here, "fixture", "TRAPS.md") if "--data" not in a else None)
    global QUESTION   # the study's question.txt (beside --data or one level up): the ask that may name candidates
    for qp in (os.path.join(data, "question.txt"), os.path.join(os.path.dirname(os.path.abspath(data)), "question.txt")):
        if os.path.exists(qp):
            QUESTION = open(qp, encoding="utf-8").read()
            break
    mode = a[a.index("--mode") + 1] if "--mode" in a else None
    other = a[a.index("--other") + 1] if "--other" in a else None
    expected = a[a.index("--expected") + 1] if "--expected" in a else None
    rpath = os.path.join(outdir, "report.json")
    R = json.load(open(rpath)) if os.path.exists(rpath) else None
    N = json.load(open(os.path.join(outdir, "numbers.json")))
    page = open(os.path.join(outdir, "report.html"), encoding="utf-8").read()
    if mode is None:
        mm = re.search(r'<body data-mode="(\w+)"', page)
        mode = mm.group(1) if mm else "desktop"
    mpath = os.path.join(outdir, "cards", "measure.json")
    measure = json.load(open(mpath)) if os.path.exists(mpath) else None
    global PROSE
    PROSE = "--prose" in a
    check_numbers_match_sources(N, data, outdir)
    check_numbers_on_page(N, page)
    check_one_value(N, page)
    if PROSE:
        check_figures_resolve(outdir, N)
        check_traps_prose(page, traps)
        check_most_runs_prose(N, traps)
        check_ellipsis(page, measure)
        check_paragraphs(measure, limit=8)
        check_cards(measure, mode)
        check_card1(page, measure)
        check_voice(page)
        check_voice_prose(page)
        check_prose_shape(page)
        check_no_summary_sections(page)
        check_ending(page)
        check_terms_once(page)
        check_ask_quote(page)
        check_lead_answer(page)
        check_headings_ask(page)
        check_microcosm_thread(page)
        check_ai_tells(page, N)
        check_checker_line_prose(page, outdir)
        check_expected(outdir, N, page, expected, traps)
        print("\n".join(out_lines))
        if fails:
            print(f"check.py: FAIL ({len(fails)} failing: {', '.join(dict.fromkeys(fails))})")
            sys.exit(1)
        print(f"check.py: PASS (prose: {len(out_lines)} checks, {len(N)} figures)")
        return
    check_traps(page, traps)
    rows = check_first_screen(page)
    check_sections(page, rows)
    check_ellipsis(page, measure)
    check_paragraphs(measure)
    check_cards(measure, mode)
    check_first_screen_fits(measure, mode)
    check_problem_first(page, R, measure)
    check_wrong_short(page, measure)
    check_first_once(page)
    check_axis_note(page, R)
    check_chart_reading(page)
    check_voice(page)
    check_most_runs(page, traps)
    check_modes_match(page, other)
    check_checked_line(page, N)
    check_checker_line(page, outdir)
    print("\n".join(out_lines))
    if fails:
        print(f"check.py: FAIL ({len(fails)} failing: {', '.join(dict.fromkeys(fails))})")
        sys.exit(1)
    print(f"check.py: PASS ({len(out_lines)} checks, {len(N)} figures)")


if __name__ == "__main__":
    main()
