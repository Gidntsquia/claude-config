#!/usr/bin/env python3
"""A terminal item as a static page, in the look of file-page.sh's pages.
  termpage.py <title> <tmux session> <out.html>   reads `tmux capture-pane -e -p -S -` text on stdin, colours kept
Minimal ANSI SGR -> HTML (colours 30-37/90-97, 38;5;n, 38;2;r;g;b, bold, reverse, reset); every other escape is dropped.
"""
import datetime, html, re, sys

C = ["#000", "#c33", "#3a3", "#aa3", "#59f", "#c5c", "#3aa", "#ccc", "#777", "#f55", "#5f5", "#ff5", "#7af", "#f5f", "#5ff", "#fff"]


def c256(n):
    if n < 16: return C[n]
    if n >= 232: v = 8 + (n - 232) * 10; return "#%02x%02x%02x" % (v, v, v)
    n -= 16; r, g, b = n // 36, (n // 6) % 6, n % 6
    return "#%02x%02x%02x" % tuple(0 if x == 0 else 55 + x * 40 for x in (r, g, b))


def ansi_html(text):
    out, st, open_ = [], {"fg": None, "bg": None, "bold": False, "rev": False}, False
    text = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)", "", text)   # OSC (titles, links)
    for tok in re.split(r"(\x1b\[[0-9;:?]*[A-Za-z])", text):
        if tok.startswith("\x1b["):
            if not tok.endswith("m"): continue
            ps = [int(p or 0) for p in re.split("[;:]", tok[2:-1]) if p.isdigit() or p == ""] or [0]
            i = 0
            while i < len(ps):
                p = ps[i]
                if p == 0: st.update(fg=None, bg=None, bold=False, rev=False)
                elif p == 1: st["bold"] = True
                elif p == 22: st["bold"] = False
                elif p == 7: st["rev"] = True
                elif p == 27: st["rev"] = False
                elif p == 39: st["fg"] = None
                elif p == 49: st["bg"] = None
                elif 30 <= p <= 37: st["fg"] = C[p - 30]
                elif 90 <= p <= 97: st["fg"] = C[p - 90 + 8]
                elif 40 <= p <= 47: st["bg"] = C[p - 40]
                elif 100 <= p <= 107: st["bg"] = C[p - 100 + 8]
                elif p in (38, 48) and i + 2 < len(ps) and ps[i + 1] == 5:
                    st["fg" if p == 38 else "bg"] = c256(ps[i + 2] % 256); i += 2
                elif p in (38, 48) and i + 4 < len(ps) and ps[i + 1] == 2:
                    st["fg" if p == 38 else "bg"] = "#%02x%02x%02x" % tuple(x % 256 for x in ps[i + 2:i + 5]); i += 4
                i += 1
            if open_: out.append("</span>"); open_ = False
            fg, bg = st["fg"], st["bg"]
            if st["rev"]: fg, bg = bg or "#16181d", fg or "#d8d8d2"
            css = ";".join(x for x in ("color:" + fg if fg else "", "background:" + bg if bg else "", "font-weight:bold" if st["bold"] else "") if x)
            if css: out.append('<span style="%s">' % css); open_ = True
        else:
            out.append(html.escape(tok.replace("\x1b", ""), quote=False))
    if open_: out.append("</span>")
    return "".join(out)


CSS = '''
html{background:#16181d}body{margin:0;color:#1b1b1b;font:17px/1.6 system-ui,sans-serif}
header{position:sticky;top:0;background:#f4f4f1;border-bottom:1px solid #d6d6d0;padding:7px 22px;font:13px/1.4 ui-monospace,Menlo,monospace;color:#444;overflow-wrap:anywhere}
header b{color:#111;font-weight:600}
pre.term{margin:0;padding:12px 16px 50px;background:#16181d;color:#d8d8d2;font:14px/1.35 ui-monospace,Menlo,Consolas,monospace;white-space:pre;overflow-x:auto;tab-size:8}
'''


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("usage: termpage.py <title> <tmux session> <out.html> < capture\n"); return 2
    title, session, dst = sys.argv[1:4]
    text = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    lines = [l.rstrip() for l in text.split("\n")]
    while lines and not re.sub(r"\x1b\[[0-9;:?]*[A-Za-z]", "", lines[-1]).strip(): lines.pop()   # the empty rows under the prompt
    try:
        from zoneinfo import ZoneInfo
        now = datetime.datetime.now(ZoneInfo("America/New_York"))
    except Exception:
        now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-5)))
    when = "%s %d:%s ET" % (now.strftime("%Y-%m-%d"), (now.hour % 12) or 12, now.strftime("%M:%S %p"))
    page = ('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>%s</title><style>%s</style></head><body>'
            '<header><b>terminal %s</b> &middot; snapshot taken %s &middot; %d lines</header>\n<pre class="term">%s</pre></body></html>\n') % (
        html.escape(title), CSS, html.escape(session), when, len(lines), ansi_html("\n".join(lines)))
    with open(dst, "w", encoding="utf-8") as f: f.write(page)
    return 0


if __name__ == "__main__":
    sys.exit(main())
