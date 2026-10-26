#!/usr/bin/env python3
"""Usage-by-day stacked bar charts, pure HTML/CSS, from gather_data.py's `days`.

  daychart.py --data <gather output.json> --part css    # paste into the page's <style id="daychart">
  daychart.py --data <gather output.json> --part html [--names <names.json>]
                                                        # the <div class="barchart-wrap"> block

--names maps the output's project names to the page's display names ({"helper-agent-building":
"Helper Agent"}) so the hover titles match the pie and the cards.

The week page gets 8 columns (Sun..Sun); build_archive.py uses archive_html() for one continuous
chart across every week. All sizes are computed here from the script's numbers; the page runs no
percentage math. Segments are drawn bottom-up in the given order (largest first), colored as given.
"""
import argparse
import html
import json
import math

CSS = """.barchart-wrap{margin:16px 0 6px}
.barchart-wrap h2.sub{margin:0 0 10px}
.bc{display:grid;grid-template-columns:auto minmax(0,1fr);column-gap:8px}
.bc-y{position:relative;height:var(--bc-h,160px);min-width:2.2em;font-size:.68rem;color:var(--muted);font-variant-numeric:tabular-nums}
.bc-y span{position:absolute;right:0;transform:translateY(50%);line-height:1}
.bc-plot{position:relative;height:var(--bc-h,160px);display:grid;grid-template-columns:repeat(8,minmax(0,1fr));gap:var(--bc-gap,10px);border-bottom:1px solid var(--line)}
.bc-grid{position:absolute;left:0;right:0;height:0;border-top:1px dashed var(--line);pointer-events:none}
.bc-col{position:relative;z-index:1;height:100%;display:flex;align-items:flex-end;justify-content:center}
.bc-bar{width:100%;display:flex;flex-direction:column-reverse;border-radius:3px 3px 0 0;overflow:hidden}
.bc-seg{flex:none;width:100%;transition:opacity .15s}
.bc-seg:hover{filter:brightness(1.18)}
.bc-plot[data-sel] .bc-seg{opacity:.25}
.bc-plot[data-sel] .bc-seg.on{opacity:1}
.bc-wk .bc-seg{cursor:pointer}
.bc-wk .bc-plot{touch-action:manipulation}
.bc-x{grid-column:2;display:grid;grid-template-columns:repeat(8,minmax(0,1fr));gap:var(--bc-gap,10px);margin-top:5px;font-size:.72rem;font-weight:600;color:var(--muted);text-align:center}
.bc-cap{color:var(--muted);font-size:.72rem;margin-top:8px}
.bc.arch{--bc-h:180px;--bc-gap:3px}
.bc-scroll{overflow-x:auto;overflow-y:hidden;padding-bottom:4px}
.bc-weeks{display:flex;width:max-content}
.bc-week{flex:none;padding:0 6px;border-left:1px solid var(--line)}
.bc-week:first-child{border-left:none;padding-left:0}
.bc-week .bc-plot{grid-template-columns:repeat(8,var(--bc-cw,16px))}
.bc-nodata{grid-column:1/-1;align-self:stretch;display:flex;align-items:center;justify-content:center;z-index:1;font-size:.68rem;color:var(--muted);opacity:.75;background:repeating-linear-gradient(135deg,transparent 0 6px,var(--line) 6px 7px)}
.bc-wlabel{margin-top:5px;font-size:.72rem;font-weight:600;color:var(--muted);text-align:center;white-space:nowrap;font-variant-numeric:tabular-nums}
"""


def y_max(days_lists):
    """Tallest day rounded up to the next 5% (at least 5)."""
    top = max((d["total_pct"] for days in days_lists for d in days), default=0)
    return max(5, int(math.ceil(top / 5 - 1e-9)) * 5)


def _md(iso):
    return f"{int(iso[5:7])}/{int(iso[8:10])}"


def _pct(v):
    return f"{v:.2f}%"


def _grid_lines(ymax):
    return "".join(f'<div class="bc-grid" style="bottom:{_pct(v / ymax * 100)}"></div>' for v in range(5, ymax + 1, 5))


def _y_axis(ymax):
    return '<div class="bc-y" aria-hidden="true">' + "".join(
        f'<span style="bottom:{_pct(v / ymax * 100)}">{v}%</span>' for v in range(0, ymax + 1, 5)) + "</div>"


def _column(d, ymax, solo):
    # The week runs Sunday 22:00 to Sunday 22:00: 8 columns, the opening Sunday (22:00-24:00) first
    # and the closing Sunday (00:00-22:00) last (gather_data.week_days).
    date_title = f'{d["label"]} {d["date"]} · {d["total_pct"]:.1f}%'
    if not d["segments"] or d["total_pct"] <= 0:
        return f'<div class="bc-col" title="{html.escape(date_title)}"></div>'
    segs = []
    for s in d["segments"]:
        who = "" if solo else f' · {s["person"]}'
        title = f'{s["project"]}{who} · {s["pct"]:.1f}%'
        name = f'{s["project"]}{who}'  # the pie slice's data-name
        segs.append(f'<div class="bc-seg" style="height:{_pct(s["pct"] / d["total_pct"] * 100)};background:{s["color"]}" '
                    f'data-name="{html.escape(name)}" title="{html.escape(title)}"></div>')
    return (f'<div class="bc-col" title="{html.escape(date_title)}"><div class="bc-bar" '
            f'style="height:{_pct(d["total_pct"] / ymax * 100)}">' + "".join(segs) + "</div></div>")


# Week page only. Click a segment: its project (pie slice name) lights up across every day and the
# projects pie selects that slice (by clicking it, so the pie's own script does the selecting);
# click it again or anywhere else to clear. Double-click: jump to the project's deep-dive card, found
# like pie-jump-js does (a list pill's text, minus a trailing " · <person>"). The chart follows the
# pie, so a pie or legend click re-highlights the bars too.
WEEK_JS = """<script>(function(){var w=document.currentScript.parentNode,p=w.querySelector('.bc-plot');if(!p)return;
var segs=[].slice.call(p.querySelectorAll('.bc-seg[data-name]')),map={},last=null,at=0;
document.querySelectorAll('.proj-btn[href^="#"]').forEach(function(a){map[a.textContent.trim()]=a.getAttribute('href').slice(1)});
function card(n){var i=n.lastIndexOf(' · '),id=map[n]||(i>0?map[n.slice(0,i)]:null);return id?document.getElementById(id):null}
function slice(n){return document.querySelector('svg.pie .pie-slice[data-name="'+CSS.escape(n)+'"]')}
function paint(n){if(n)p.setAttribute('data-sel','');else p.removeAttribute('data-sel');segs.forEach(function(s){s.classList.toggle('on',s.dataset.name===n)})}
function sync(){var a=document.querySelector('svg.pie .pie-slice.active[data-name]');paint(a&&segs.some(function(s){return s.dataset.name===a.dataset.name})?a.dataset.name:null)}
document.addEventListener('click',function(){setTimeout(sync)},true);
segs.forEach(function(s){s.addEventListener('click',function(e){e.stopPropagation();var n=s.dataset.name,t=Date.now();
if(last===n&&t-at<450){last=null;var c=card(n);if(c)c.scrollIntoView({behavior:'smooth',block:'start'});return}
last=n;at=t;var sl=slice(n);if(sl)sl.dispatchEvent(new MouseEvent('click',{bubbles:true}));else paint(s.classList.contains('on')?null:n)})})})();</script>"""


def week_html(days, solo):
    """The week page's "Usage by day" block: 8 columns, shared y-axis, caption, click script."""
    ymax = y_max([days])
    cols = "".join(_column(d, ymax, solo) for d in days)
    labels = "".join(f"<span>{d['label']}<br>{_md(d['date'])}</span>" for d in days)
    return ('<div class="barchart-wrap"><h2 class="sub">Usage by day</h2><div class="bc bc-wk">' + _y_axis(ymax)
            + '<div class="bc-plot">' + _grid_lines(ymax) + cols + "</div>"
            + f'<div class="bc-x">{labels}</div></div>'
            + '<div class="bc-cap">Colors match the projects pie above.</div>' + WEEK_JS + "</div>")


def short_label(label):
    """'Oct 4–11, 2026' -> 'Oct 4–11'."""
    return label.split(",")[0].strip()


def archive_html(weeks):
    """One continuous chart, oldest week left: 8 columns per archive week, weeks without `days`
    as 8 empty columns with a "no daily data" marker, the week label under each week."""
    weeks = sorted(weeks, key=lambda w: w["weekStart"])
    ymax = y_max([w["days"] for w in weeks if w.get("days")])
    parts = []
    for w in weeks:
        days = w.get("days")
        if days:
            solo = len({s["person"] for d in days for s in d["segments"]}) <= 1
            body = "".join(_column(d, ymax, solo) for d in days)
        else:
            body = '<div class="bc-nodata">no daily data</div>'
        parts.append(f'<div class="bc-week" data-week="{w["weekStart"]}"><div class="bc-plot">' + _grid_lines(ymax) + body
                     + f'</div><div class="bc-wlabel">{html.escape(short_label(w["label"]))}</div></div>')
    return ('<div class="bc arch">' + _y_axis(ymax) + '<div class="bc-scroll" id="bc-scroll"><div class="bc-weeks">'
            + "".join(parts) + "</div></div></div>"
            + "<script>(function(){var s=document.getElementById('bc-scroll');if(s)s.scrollLeft=s.scrollWidth})();</script>")


def display_days(days, names):
    """A copy of `days` with project names swapped for display names (Misc stays Misc)."""
    return [{**d, "segments": [{**s, "project": names.get(s["project"], s["project"])} for s in d["segments"]]}
            for d in days]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True, help="gather_data.py output JSON")
    ap.add_argument("--part", choices=["css", "html"], required=True)
    ap.add_argument("--names", help='JSON file {"<project name>": "<display name>"}')
    a = ap.parse_args()
    out = json.load(open(a.data))
    if a.part == "css":
        print(CSS, end="")
    else:
        names = json.load(open(a.names)) if a.names else {}
        print(week_html(display_days(out["days"], names), solo=len(out.get("people", [])) <= 1))


if __name__ == "__main__":
    main()
