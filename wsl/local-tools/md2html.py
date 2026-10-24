#!/usr/bin/env python3
"""Minimal markdown -> HTML body (stdlib only): # headings, -/*/1. lists (nested by indent), | tables |, ``` fences,
> quotes, --- rules, paragraphs; inline **bold**, *em*, `code`, [text](url), ~~del~~. Enough for reports, notes, EVAL.md."""
import html, re, sys

def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r'`([^`]+)`', lambda m: '<code>%s</code>' % m.group(1), t)
    t = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)', r'<em>\1</em>', t)
    t = re.sub(r'(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)', r'<em>\1</em>', t)
    t = re.sub(r'~~(.+?)~~', r'<del>\1</del>', t)
    t = re.sub(r'!\[([^\]]*)\]\(([^)\s]+)\)', r'<img alt="\1" src="\2">', t)
    t = re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', r'<a href="\2">\1</a>', t)
    return t

def cells(line):
    line = line.strip()
    if line.startswith('|'): line = line[1:]
    if line.endswith('|'): line = line[:-1]
    return [c.strip() for c in re.split(r'(?<!\\)\|', line)]

def render(lines):
    out, i, n = [], 0, len(lines)
    para = []
    def flush():
        if para: out.append('<p>%s</p>' % inline(' '.join(para))); para.clear()
    while i < n:
        l = lines[i]
        if l.startswith('```'):
            flush(); j = i + 1; buf = []
            while j < n and not lines[j].startswith('```'): buf.append(lines[j]); j += 1
            out.append('<pre class="code"><code>%s</code></pre>' % html.escape('\n'.join(buf))); i = j + 1; continue
        m = re.match(r'^(#{1,6})\s+(.*)$', l)
        if m:
            flush(); out.append('<h%d>%s</h%d>' % (len(m.group(1)), inline(m.group(2).rstrip('# ')), len(m.group(1)))); i += 1; continue
        if re.match(r'^\s*([-*_])(\s*\1){2,}\s*$', l):
            flush(); out.append('<hr>'); i += 1; continue
        if l.strip().startswith('|') and i + 1 < n and re.match(r'^\s*\|?\s*:?-{2,}', lines[i + 1]):
            flush(); head = cells(l); j = i + 2; rows = []
            while j < n and lines[j].strip().startswith('|'): rows.append(cells(lines[j])); j += 1
            t = ['<table><thead><tr>%s</tr></thead><tbody>' % ''.join('<th>%s</th>' % inline(c) for c in head)]
            for r in rows: t.append('<tr>%s</tr>' % ''.join('<td>%s</td>' % inline(c) for c in r))
            t.append('</tbody></table>'); out.append(''.join(t)); i = j; continue
        if l.startswith('>'):
            flush(); buf = []
            while i < n and lines[i].startswith('>'): buf.append(lines[i][1:].lstrip()); i += 1
            out.append('<blockquote>%s</blockquote>' % render(buf)); continue
        m = re.match(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$', l)
        if m:
            flush(); out.append(render_list(lines, i)[0]); i = render_list(lines, i)[1]; continue
        if not l.strip():
            flush(); i += 1; continue
        para.append(l.strip()); i += 1
    flush()
    return '\n'.join(out)

def render_list(lines, i):
    n = len(lines)
    m = re.match(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$', lines[i])
    ind = len(m.group(1)); ordered = m.group(2)[0].isdigit()
    tag = 'ol' if ordered else 'ul'; items = []
    while i < n:
        m = re.match(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$', lines[i])
        if m and len(m.group(1)) == ind:
            text = m.group(3); i += 1; sub = []
            while i < n and (lines[i].startswith(' ' * (ind + 2)) and lines[i].strip() or (lines[i].strip() and not re.match(r'^(\s*)([-*+]|\d+[.)])\s+', lines[i]) and not lines[i].startswith('#') and not lines[i].strip().startswith('|'))):
                sub.append(lines[i]); i += 1
            body = inline(text)
            if sub:
                if re.match(r'^\s*([-*+]|\d+[.)])\s+', sub[0]): body += render(sub)
                else: body += ' ' + inline(' '.join(s.strip() for s in sub))
            items.append('<li>%s</li>' % body)
        elif m and len(m.group(1)) > ind:
            h, i = render_list(lines, i); items[-1] = items[-1][:-5] + h + '</li>'
        else: break
    return '<%s>%s</%s>' % (tag, ''.join(items), tag), i

src = sys.argv[1] if len(sys.argv) > 1 else '/dev/stdin'
text = open(src, encoding='utf-8', errors='replace').read()
text = re.sub(r'^---\n.*?\n---\n', '', text, count=1, flags=re.S)  # frontmatter
sys.stdout.write(render(text.replace('\r', '').split('\n')))
