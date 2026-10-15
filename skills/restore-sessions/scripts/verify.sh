#!/usr/bin/env bash
# usage: verify.sh DIR [--no-wait] [--no-screenshot]
# About 12 s after apply.sh: capture-pane on every resumed pane and check it shows the Claude prompt (empty input
# box), the expected agent on the prompt box and the expected mode on the status line; check every pet pane runs
# terminal-pet; take a screenshot (~/.claude/local-tools/screen-capture.sh restore-sessions); then print the report:
# window x pane table, per-pane check results with the captured lines, sessions not reopened, mid-task sessions,
# and any agent/model that differs from the transcript. Nothing is retried. Captures go to DIR/capture-<pane>.txt;
# the report is also saved as DIR/report.md.
set -uo pipefail
dir="${1:?usage: verify.sh DIR [--no-wait] [--no-screenshot]}"; shift
wait=12 shot=1
for a in "$@"; do case "$a" in --no-wait) wait=0 ;; --no-screenshot) shot=0 ;; esac; done
L=(); [ -n "${RS_TMUX_L:-}" ] && L=(-L "$RS_TMUX_L")
[ "$wait" -gt 0 ] && sleep "$wait"

# Raw facts per pane -> DIR/check.tsv (key pane_id target_now current_command capture_file)
: > "$dir/check.tsv"
while IFS=$'\t' read -r k p now planned; do
  cap="$dir/capture-${p#%}.txt"
  tmux "${L[@]}" capture-pane -p -J -S -300 -t "$p" > "$cap" 2>/dev/null || echo "(pane gone)" > "$cap"
  # Claude draws on the alternate screen; the shell line that started it is on the saved normal screen (-a).
  # A resize after the resume (Windows Terminal attaching) can cut that saved line; apply.sh kept a copy taken right
  # after the line was typed (sent-<pane>.txt), used when the live one lost the full id.
  if [ "$(tmux "${L[@]}" display -p -t "$p" '#{alternate_on}' 2>/dev/null)" = 1 ]; then
    tmux "${L[@]}" capture-pane -a -p -J -t "$p" > "${cap%.txt}-shell.txt" 2>/dev/null
  else
    cp "$cap" "${cap%.txt}-shell.txt"
  fi
  sent="$dir/sent-${p#%}.txt"; id=$(awk -F'\t' -v k="$k" '$4 == k { print $5 }' "$dir/plan.tsv")
  if [ -n "$id" ] && [ -f "$sent" ] && ! grep -qF "claude --resume $id" "${cap%.txt}-shell.txt"; then
    { echo "# shell screen saved by apply.sh right after the resume line (the live saved screen was cut by a resize):"
      cat "$sent"; } > "${cap%.txt}-shell.txt"
  fi
  cmd=$(tmux "${L[@]}" display -p -t "$p" '#{pane_current_command}' 2>/dev/null || echo gone)
  printf '%s\t%s\t%s\t%s\t%s\n' "$k" "$p" "$now" "$cmd" "$cap" >> "$dir/check.tsv"
done < "$dir/panes-final.tsv"
# Every pane of the touched windows, for the window x pane table.
tmux "${L[@]}" list-panes -a -F '#{session_name}:#{window_index}	#{pane_index}	#{pane_id}	#{pane_current_command}	#{pane_pid}' > "$dir/after.tsv" 2>/dev/null
tmux "${L[@]}" list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_pid}' > "$dir/after.txt" 2>/dev/null

png=""
if [ "$shot" = 1 ] && [ -x "$HOME/.claude/local-tools/screen-capture.sh" ]; then
  png=$("$HOME/.claude/local-tools/screen-capture.sh" restore-sessions 2>/dev/null | tail -1)
fi
# Windows brought to front: clear topmost now that the screenshot is taken (they stay in front).
if [ -s "$dir/wt.tsv" ] && [ -x "$HOME/.claude/local-tools/win.sh" ]; then
  cut -f3 "$dir/wt.tsv" | while read -r h; do [ -n "$h" ] && "$HOME/.claude/local-tools/win.sh" untop "$h" >/dev/null 2>&1; done
fi

python3 -I - "$dir" "$png" <<'PY' | tee "$dir/report.md"
import os, re, sys
d, png = sys.argv[1], sys.argv[2]
def tsv(n):
    p = os.path.join(d, n)
    return [l.rstrip("\n").split("\t") for l in open(p, encoding="utf-8")] if os.path.exists(p) else []
plan = {r[3]: r for r in tsv("plan.tsv")}
checks = tsv("check.tsv")
MODE_TEXT = {"auto": "auto mode on", "acceptEdits": "accept edits on", "plan": "plan mode on",
             "bypassPermissions": "bypass permissions on", "dontAsk": "don't ask on"}
def model_name(m):  # claude-sonnet-5-5 -> Sonnet 5.5
    m = re.match(r"claude-([a-z]+)-(\d+)-(\d+)", m or "")
    return "%s %s.%s" % (m.group(1).capitalize(), m.group(2), m.group(3)) if m else ""
def short(p): return p.replace(os.path.expanduser("~"), "~")

results, changed, holds = [], [], {}
for k, pid, now, cmd, cap in checks:
    r = plan.get(k)
    if not r: continue
    text = open(cap, encoding="utf-8", errors="replace").read()
    lines = [l.rstrip() for l in text.splitlines()]
    shp = cap[:-4] + "-shell.txt"
    shell = [l.rstrip() for l in open(shp, encoding="utf-8", errors="replace").read().splitlines()] if os.path.exists(shp) else lines
    shell_nb = [l for l in shell if l.strip()]
    if r[1] == "pet":
        ok = cmd == "terminal-pet"
        holds[now] = "pet: %s" % r[10]
        results.append((now, "pet " + r[10], ok, "pane runs %s" % cmd, []))
        continue
    sid, cwd, agent, model, mode = r[4], r[5], r[6], r[7], r[8]
    holds[now] = "claude %s (%s)" % (sid[:8], short(cwd))
    want_cmd = "cd '%s' && claude --resume %s" % (cwd.replace("'", "'\\''"), sid)
    probs = []
    n_cmd = sum(1 for l in shell if "claude --resume" in l)
    if not any(want_cmd in l for l in shell): probs.append("resume line not found on the shell screen")
    if n_cmd != 1: probs.append("'claude --resume' appears %d times on the shell screen" % n_cmd)
    elif shell_nb and want_cmd not in shell_nb[-1]: probs.append("more input after the resume line: %r" % shell_nb[-1])
    if any(re.search(r"No conversation found|Session not found|not found.*session", l, re.I) for l in lines):
        probs.append("claude says the session was not found")
    if any("trust this folder" in l for l in lines[-25:]):
        probs.append("Claude is asking whether to trust %s (answer it in that pane)" % short(cwd))
    pi = max((i for i, l in enumerate(lines) if l.lstrip().startswith("❯")), default=-1)
    shown_agent = shown_mode = shown_model = ""
    if pi < 0 or cmd in ("bash", "zsh", "sh", "gone"):
        probs.append("no Claude prompt (pane runs %s)" % cmd)
    else:
        if lines[pi].lstrip()[1:].strip(): probs.append("input box is not empty: %r" % lines[pi].strip())
        border = lines[pi - 1] if pi > 0 else ""
        m = re.search(r"─ (\S+) ─+\s*$", border)
        shown_agent = m.group(1) if m else ""
        tail = "\n".join(lines[pi + 1:])
        shown_mode = next((k2 for k2, v in MODE_TEXT.items() if v in tail), "default")
        m = re.search(r"\b(Opus|Sonnet|Haiku|Fable) (\d+(?:\.\d+)?)", tail)
        shown_model = m.group(0) if m else ""
        if shown_agent != agent:
            probs.append("agent: expected %s, shows %s" % (agent or "(none)", shown_agent or "(none)"))
            changed.append("%s: agent %s in the transcript, %s now" % (sid[:8], agent or "(none)", shown_agent or "(none)"))
        if mode and shown_mode != mode: probs.append("mode: expected %s, shows %s" % (mode, shown_mode))
        if model and shown_model and shown_model != model_name(model):
            changed.append("%s: model %s in the transcript, %s now" % (sid[:8], model_name(model), shown_model))
    ev = ["shell: " + l.strip() for l in shell if "claude --resume" in l] + ([lines[pi - 1].strip(), lines[pi].strip()] if pi > 0 else []) \
         + [l.strip() for l in lines[pi + 1:pi + 4] if l.strip()]
    results.append((now, "claude " + sid[:8], not probs, "; ".join(probs) or
                    "prompt shown; agent %s; mode %s; model %s" % (shown_agent or "(none)", shown_mode, shown_model or "?"), ev))

print("## Panes after the run (window x pane)\n")
after = tsv("after.tsv")
touched = sorted({c[2].rsplit(".", 1)[0] for c in checks if c[2] != "gone"})
print("| window | " + " | ".join("pane %d" % i for i in range(1, 1 + max([sum(1 for a in after if a[0] == w) for w in touched] or [0]))) + " |")
print("|---" * (1 + max([sum(1 for a in after if a[0] == w) for w in touched] or [0])) + "|")
for w in touched:
    cells = []
    for a in sorted((a for a in after if a[0] == w), key=lambda a: int(a[1])):
        cells.append(holds.get("%s.%s" % (w, a[1]), "%s (was already here)" % a[3]))
    print("| %s | %s |" % (w, " | ".join(cells)))
print("\n## Checks (capture-pane, ~12 s after the last resume)\n")
for now, what, ok, msg, ev in results:
    print("- %s %s %s: %s" % ("PASS" if ok else "FAIL", now, what, msg))
    for l in ev: print("    > " + l)
print("\nCaptures: %s/capture-<pane>.txt (Claude screen) and capture-<pane>-shell.txt (shell screen)" % d)
print("Screenshot: %s" % (png or "(none taken)"))
wt = tsv("wt.tsv")
for w in wt: print("Windows Terminal for tmux session %s: %s" % (w[0], w[3]))
print("\n## Not reopened")
sk = tsv("skipped.tsv")
for s in sk: print("- %s %s: %s" % (s[0][:8], short(s[1]), s[2]))
if not sk: print("- none")
print("\n## Stopped mid-task (say `continue` in that pane)")
mids = [r for r in plan.values() if r[1] == "claude" and r[9] == "yes"]
for r in mids: print("- %s %s" % (r[4][:8], short(r[5])))
if not mids: print("- none")
print("\n## Agent or model differs from the transcript")
noag = ["%s: no agent in the transcript (/clear-ed session), came back without one" % r[4][:8] for r in plan.values() if r[1] == "claude" and not r[6]]
for c in changed + noag: print("- " + c)
if not changed and not noag: print("- none")
PY
