#!/bin/bash
# usage: file-page.sh <path> [A-B]
# Builds ONE self-contained HTML page of a file, for Firefox (VS Code is retired: every .md, log, text and source file is shown
# this way). Prints `page: <html path>|<title>`; title = `<file name> fp-<6 random characters>` (the page's <title>, unique per
# build, so `win-app.sh --hidden --title "<title>" firefox "<html path>"` and `win.sh show "<title>"` match this build only).
#   .md            rendered by md2html.py (headings, lists, tables, code blocks, links, images) at a readable line width; relative
#                  links point at the source's folder, relative images are embedded (data: URI, up to 5 MB each; larger = linked)
#   anything else  escaped monospace text with line numbers, no colouring
#   A-B            only lines A..B, under their real numbers (a .md is then shown as text too)
#   over 2 MB      the last 5000 lines, under `showing last 5000 of <N> lines` (FILE_PAGE_MAX_BYTES / FILE_PAGE_TAIL change the two)
# Every page starts with the source's absolute path and its modified time in ET.
# The page is written to <session state dir>/pages/ (evsession.sh: EVSHOW_STATE, else this Claude session's dir);
# FILE_PAGE_DIR=<dir> overrides. Nothing is opened. Failure is ONE line `not built: <reason>`, exit 1 (missing, a folder,
# unreadable, binary, a bad range); exit 2 = usage.
here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
[ $# -ge 1 ] && [ $# -le 2 ] && [ -n "$1" ] || { echo "usage: file-page.sh <path> [A-B]" >&2; exit 2; }
out="${FILE_PAGE_DIR:-}"
if [ -z "$out" ]; then
  . "$here/evsession.sh"
  d=$(ev_state_dir create) || { echo "not built: no session state dir (set EVSHOW_STATE or FILE_PAGE_DIR)"; exit 1; }
  out="$d/pages"
fi
mkdir -p "$out" 2>/dev/null || { echo "not built: cannot write to $out"; exit 1; }
exec python3 -I - "$here/md2html.py" "$out" "$1" "${2:-}" <<'PY'
import base64, collections, datetime, html, mimetypes, os, re, secrets, string, subprocess, sys, urllib.parse
md2html, outdir, src, rng = sys.argv[1:5]
MAXB = int(os.environ.get('FILE_PAGE_MAX_BYTES') or 2 * 1024 * 1024); TAIL = int(os.environ.get('FILE_PAGE_TAIL') or 5000)

def fail(why):
    print('not built: ' + why); sys.exit(1)

path = os.path.abspath(os.path.expanduser(src))
if not os.path.exists(path): fail('no such file: ' + path)
if os.path.isdir(path): fail('a folder, not a file: ' + path)
if not os.path.isfile(path): fail('not a regular file: ' + path)
try:
    with open(path, 'rb') as f: head = f.read(8192)
except OSError as e:
    fail('cannot read %s (%s)' % (path, e.strerror))
if b'\0' in head: fail('binary file: ' + path)
a = b = None
if rng:
    m = re.fullmatch(r'(\d+)-(\d+)', rng)
    if not m or int(m.group(1)) < 1 or int(m.group(2)) < int(m.group(1)): fail("bad line range '%s' (want A-B, 1 <= A <= B)" % rng)
    a, b = int(m.group(1)), int(m.group(2))
st = os.stat(path); name = os.path.basename(path)
try:
    from zoneinfo import ZoneInfo
    mt = datetime.datetime.fromtimestamp(st.st_mtime, ZoneInfo('America/New_York'))
except Exception:   # no tz database: fixed EST
    mt = datetime.datetime.fromtimestamp(st.st_mtime, datetime.timezone(datetime.timedelta(hours=-5)))
when = '%s %d:%s ET' % (mt.strftime('%Y-%m-%d'), (mt.hour % 12) or 12, mt.strftime('%M %p'))
tok = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(6))
title = '%s fp-%s' % (name, tok)
big = st.st_size > MAXB
is_md = name.lower().endswith(('.md', '.markdown')) and not rng and not big

def file_url(p):   # a URL Firefox on this machine can load: under WSL the \\wsl.localhost\<distro>\... form
    if os.path.exists('/proc/version') and 'microsoft' in open('/proc/version').read().lower():
        try:
            w = subprocess.run(['wslpath', '-w', p], capture_output=True, text=True).stdout.strip()
            if w: return 'file:///' + urllib.parse.quote(w.replace('\\', '/'), safe='/:')
        except OSError: pass
    return 'file://' + urllib.parse.quote(p)

def resolve(body):   # relative links -> the source's folder; relative images -> embedded
    base = os.path.dirname(path)
    def rel(u): return not re.match(r'(?i)[a-z][a-z0-9+.-]*:|//|#', u)
    def target(u):
        u2, _, frag = html.unescape(u).partition('#')
        p = os.path.normpath(u2 if u2.startswith('/') else os.path.join(base, urllib.parse.unquote(u2)))
        return p, ('#' + frag if frag else '')
    def img(m):
        u = m.group(2)
        if not rel(u): return m.group(0)
        p, _ = target(u)
        try:
            if os.path.isfile(p) and os.path.getsize(p) <= 5 * 1024 * 1024:
                mime = mimetypes.guess_type(p)[0] or 'application/octet-stream'
                return '%sdata:%s;base64,%s%s' % (m.group(1), mime, base64.b64encode(open(p, 'rb').read()).decode(), m.group(3))
        except OSError: pass
        return m.group(1) + html.escape(file_url(p)) + m.group(3)
    def link(m):
        u = m.group(2)
        if not rel(u): return m.group(0)
        p, frag = target(u)
        return m.group(1) + html.escape(file_url(p) + frag) + m.group(3)
    body = re.sub(r'(<img alt="[^"]*" src=")([^"]+)(")', img, body)
    return re.sub(r'(<a href=")([^"]+)(")', link, body)

note = ''
if is_md:
    r = subprocess.run([sys.executable, '-I', md2html, path], capture_output=True, text=True, errors='replace')
    if r.returncode != 0: fail('md2html.py failed on %s: %s' % (path, (r.stderr.strip().splitlines() or ['exit %d' % r.returncode])[-1]))
    main = '<main class="md">%s</main>' % resolve(r.stdout)
else:
    try:
        with open(path, encoding='utf-8', errors='replace', newline='') as f:
            if rng:
                rows = []; total = 0
                for total, l in enumerate(f, 1):
                    if total > b: break
                    if total >= a: rows.append((total, l))
                if not rows: fail('%s has %d lines, none in %s' % (path, total, rng))
                note = 'lines %d-%d' % (rows[0][0], rows[-1][0])
            elif big:
                dq = collections.deque(maxlen=TAIL); total = 0
                for total, l in enumerate(f, 1): dq.append((total, l))
                rows = list(dq); note = 'showing last %d of %d lines' % (len(rows), total)
            else:
                rows = list(enumerate(f, 1))
    except OSError as e:
        fail('cannot read %s (%s)' % (path, e.strerror))
    w = len(str(rows[-1][0])) if rows else 1
    main = '<pre class="text">%s</pre>' % ''.join(
        '<span class="n">%*d</span>%s\n' % (w, n, html.escape(l.rstrip('\r\n'), quote=False)) for n, l in rows)

CSS = '''
html{background:#fff}body{margin:0;color:#1b1b1b;font:17px/1.6 system-ui,"Segoe UI",sans-serif}
header{position:sticky;top:0;background:#f4f4f1;border-bottom:1px solid #d6d6d0;padding:7px 22px;font:13px/1.4 ui-monospace,Consolas,monospace;color:#444;overflow-wrap:anywhere}
header b{color:#111;font-weight:600}header .note{display:block;color:#8a4b00;font-weight:600}
main.md{max-width:46em;margin:0 auto;padding:18px 26px 60px}
h1,h2,h3,h4{line-height:1.25;margin:1.4em 0 .5em}h1{font-size:1.75em;border-bottom:1px solid #ddd;padding-bottom:.2em}h2{font-size:1.38em;border-bottom:1px solid #e6e6e6;padding-bottom:.15em}h3{font-size:1.15em}
p,ul,ol,table,pre,blockquote{margin:.7em 0}li{margin:.2em 0}img{max-width:100%}a{color:#0b57b0}
code{font:.88em ui-monospace,Consolas,monospace;background:#f0f0ec;padding:.1em .3em;border-radius:3px}
pre.code{background:#f5f5f2;border:1px solid #e2e2dc;border-radius:5px;padding:10px 12px;overflow-x:auto;line-height:1.45}pre.code code{background:none;padding:0}
table{border-collapse:collapse;display:block;overflow-x:auto}th,td{border:1px solid #c9c9c2;padding:5px 9px;vertical-align:top;text-align:left}th{background:#eeeeea}
blockquote{margin-left:0;padding:.1em 1em;border-left:4px solid #c9c9c2;color:#444}hr{border:0;border-top:1px solid #ccc;margin:1.5em 0}
pre.text{margin:0;padding:10px 0 50px;font:14px/1.45 ui-monospace,Consolas,"Cascadia Mono",monospace;white-space:pre-wrap;overflow-wrap:anywhere;tab-size:4}
pre.text .n{display:inline-block;padding:0 12px 0 14px;margin-right:12px;color:#8a8a84;background:#f4f4f1;border-right:1px solid #deded8;user-select:none}
'''
page = ('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>%s</title><style>%s</style></head><body>'
        '<header><b>%s</b> &middot; modified %s%s</header>\n%s</body></html>\n') % (
    html.escape(title), CSS, html.escape(path), when, '\n<span class="note">%s</span>' % note if note else '', main)
dst = os.path.join(outdir, '%s.fp-%s.html' % (re.sub(r'[^A-Za-z0-9._-]', '_', name), tok))
try:
    with open(dst, 'w', encoding='utf-8') as f: f.write(page)
except OSError as e:
    fail('cannot write %s (%s)' % (dst, e.strerror))
try:   # the source beside the page (path, first line shown): a tool that shows the file itself reads it
    with open(dst + '.src', 'w', encoding='utf-8') as f: f.write('%s\n%s\n' % (path, a or ''))
except OSError: pass
print('page: %s|%s' % (dst, title))
PY
