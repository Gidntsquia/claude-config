#!/bin/bash
# Phone path of the evaluator: render one item to PNG(s) for the Read tool (no window is opened).
#   phone-shot.sh <out-base> url  <url>                 a web page or running app
#   phone-shot.sh <out-base> html <file.html>           an HTML file
#   phone-shot.sh <out-base> md   <file.md>             markdown rendered to HTML (python3 -m markdown if present, else <pre>)
#   phone-shot.sh <out-base> text <file> [A-B]          plain text / log / source with line numbers (optional line range)
#   phone-shot.sh <out-base> tmux <session> [--no-ansi] a tmux pane you created: capture-pane -e, ANSI colours kept
# Output: <out-base>.png (or <out-base>-pN.png parts for pages taller than 3 phone screens); prints "png <path> WxH" per part.
# Playwright Chromium (390 css px, 2x) via phone-shot.mjs; if node/playwright is missing it says so and falls back to
# headless Firefox (--screenshot, window 390 px wide, 1x, no split).
set -e
base="$1"; kind="$2"; src="$3"; arg4="$4"
[ -n "$base" ] && [ -n "$kind" ] && [ -n "$src" ] || { sed -n 2,8p "$0"; exit 2; }
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
mkdir -p "$(dirname "$base")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
esc() { python3 -c 'import html,sys; sys.stdout.write(html.escape(sys.stdin.read()))'; }
wrap() {  # wrap <title> <body-html-file> -> $tmp/page.html
  { printf '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>%s</title>' "$(printf %s "$1" | esc)"
    printf '<style>body{margin:12px;font:15px/1.45 system-ui,sans-serif;color:#111;background:#fff;word-wrap:break-word}pre{font:12px/1.35 ui-monospace,Menlo,monospace;white-space:pre-wrap;word-break:break-all;margin:0}pre.term{background:#111;color:#ddd;padding:8px;border-radius:6px}h1,h2,h3{line-height:1.2}img{max-width:100%%}table{border-collapse:collapse}td,th{border:1px solid #bbb;padding:2px 6px}</style></head><body>'
    cat "$2"; printf '</body></html>'; } > "$tmp/page.html"
}
case "$kind" in
  url)  url="$src" ;;
  html) url="file://$(readlink -f "$src")" ;;
  md)
    if python3 -c 'import markdown' 2>/dev/null; then python3 -m markdown "$src" > "$tmp/body.html"
    else { printf '<pre>'; esc < "$src"; printf '</pre>'; } > "$tmp/body.html"; fi
    wrap "$(basename "$src")" "$tmp/body.html"; url="file://$tmp/page.html" ;;
  text)
    range="${arg4:-}"
    { printf '<pre>'
      if [ -n "$range" ]; then sed -n "${range%-*},${range#*-}p" "$src" | nl -ba -v "${range%-*}" -w4 -s'  ' | esc
      else nl -ba -w4 -s'  ' "$src" | esc; fi
      printf '</pre>'; } > "$tmp/body.html"
    wrap "$(basename "$src")${range:+ lines $range}" "$tmp/body.html"; url="file://$tmp/page.html" ;;
  tmux)
    tmux has-session -t "$src" 2>/dev/null || { echo "phone-shot.sh: no tmux session '$src'"; exit 1; }
    if [ "$arg4" = "--no-ansi" ]; then tmux capture-pane -p -t "$src" > "$tmp/pane.txt"; else tmux capture-pane -e -p -t "$src" > "$tmp/pane.txt"; fi
    python3 - "$tmp/pane.txt" > "$tmp/body.html" <<'PY'
import html, re, sys
# minimal ANSI SGR -> HTML (colours 30-37/90-97, 38;5;n, bold, reset); anything else is dropped
C = ["#000","#c33","#3a3","#aa3","#36c","#a3a","#3aa","#ccc","#777","#f55","#5f5","#ff5","#59f","#f5f","#5ff","#fff"]
def c256(n):
    if n < 16: return C[n]
    if n >= 232: v = 8 + (n - 232) * 10; return "#%02x%02x%02x" % (v, v, v)
    n -= 16; r, g, b = n // 36, (n // 6) % 6, n % 6
    return "#%02x%02x%02x" % tuple(0 if x == 0 else 55 + x * 40 for x in (r, g, b))
out, fg, bg, bold, open_ = [], None, None, False, False
def style():
    s = []
    if fg: s.append("color:" + fg)
    if bg: s.append("background:" + bg)
    if bold: s.append("font-weight:bold")
    return ";".join(s)
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for tok in re.split(r"(\x1b\[[0-9;]*m)", text):
    if tok.startswith("\x1b["):
        ps = [int(p or 0) for p in tok[2:-1].split(";")] or [0]
        i = 0
        while i < len(ps):
            p = ps[i]
            if p == 0: fg = bg = None; bold = False
            elif p == 1: bold = True
            elif p == 22: bold = False
            elif p == 39: fg = None
            elif p == 49: bg = None
            elif 30 <= p <= 37: fg = C[p - 30]
            elif 90 <= p <= 97: fg = C[p - 90 + 8]
            elif 40 <= p <= 47: bg = C[p - 40]
            elif 100 <= p <= 107: bg = C[p - 100 + 8]
            elif p in (38, 48) and i + 2 < len(ps) and ps[i + 1] == 5:
                col = c256(ps[i + 2]); i += 2
                if p == 38: fg = col
                else: bg = col
            elif p in (38, 48) and i + 4 < len(ps) and ps[i + 1] == 2:
                col = "#%02x%02x%02x" % tuple(ps[i + 2:i + 5]); i += 4
                if p == 38: fg = col
                else: bg = col
            i += 1
        if open_: out.append("</span>"); open_ = False
        st = style()
        if st: out.append('<span style="%s">' % st); open_ = True
    else:
        out.append(html.escape(tok))
if open_: out.append("</span>")
sys.stdout.write('<pre class="term">' + "".join(out).rstrip("\n") + "</pre>")
PY
    wrap "tmux $src" "$tmp/body.html"; url="file://$tmp/page.html" ;;
  *) echo "phone-shot.sh: unknown kind '$kind' (url|html|md|text|tmux)"; exit 2 ;;
esac
# node: the nvm install if the shell has no node on PATH
command -v node >/dev/null 2>&1 || { for n in "$HOME"/.nvm/versions/node/*/bin; do PATH="$n:$PATH"; done; }
if command -v node >/dev/null 2>&1 && node "$here/phone-shot.mjs" "$base" "$url"; then exit 0; fi
echo "phone-shot.sh: playwright screenshot failed; falling back to headless Firefox (1x, no split)" >&2
FF=/mnt/c/Program\ Files/Mozilla\ Firefox/firefox.exe
[ -x "$FF" ] || FF="$(command -v firefox || true)"
[ -n "$FF" ] || { echo "phone-shot.sh: no firefox for the fallback"; exit 1; }
out="$base.png"
if [ "${url#file://}" != "$url" ] && [ "${FF#/mnt/c}" != "$FF" ]; then url="file:///$(wslpath -w "${url#file://}" | sed 's#\\#/#g')"; fi
"$FF" --headless --screenshot "$( [ "${FF#/mnt/c}" != "$FF" ] && wslpath -w "$out" || echo "$out" )" --window-size=390,"${PHONE_FF_HEIGHT:-2532}" "$url" >/dev/null 2>&1 || true
[ -s "$out" ] || { echo "phone-shot.sh: firefox fallback produced no file"; exit 1; }
python3 -c 'import struct,sys; b=open(sys.argv[1],"rb").read(24); print("png", sys.argv[1], "%dx%d" % struct.unpack(">II", b[16:24]))' "$out"
