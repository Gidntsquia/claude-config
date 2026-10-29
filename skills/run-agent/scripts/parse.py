#!/usr/bin/env python3
"""parse.py: turn the raw /run-agent $ARGUMENTS string into one JSON block (agent, prompt, dir, flags, force,
run time, corrections, unsure, dry). Called by `run-agent.sh --parse '<raw>'`. Stdlib only.

Also: `parse.py --reset` prints the 5-hour window reset epoch (or `error: ...`, exit 2), and
`parse.py --fmt <epoch>` prints it as `9:40 PM ET`.

Env: RUN_AGENT_NOW (epoch, "now" for tests), RUN_AGENT_USAGE_FILE (JSON file standing in for the usage API),
RUN_AGENT_HOME (state dir), RUN_AGENT_TZ (zone name; default the machine's local zone).
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "run-agent.sh")

MODELS = ["fable", "opus", "sonnet", "haiku"]
EFFORTS = ["low", "medium", "high", "xhigh", "max"]
FORCE_WORDS = ["force", "now", "go", "yolo-run"]
TIME_WORDS = ["window", "at", "in", "after", "until", "next", "reset", "resets", "when", "the", "ends", "before",
              "tomorrow", "tonight", "today", "evening", "current", "usage", "this", "day", "days", "week", "weeks"]
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
WEEKDAY_SHORT = {"mon": 0, "tue": 1, "tues": 1, "wed": 2, "thu": 3, "thur": 3, "thurs": 3, "fri": 4, "sat": 5, "sun": 6}
NUMBER_WORDS = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "half": 0.5}
# words the haiku fallback may resolve itself when the parser cannot (time-ish words next to an unsure one)
TIMEY = set(TIME_WORDS) | set(WEEKDAYS) | set(WEEKDAY_SHORT) | set(NUMBER_WORDS) | {
    "hours", "hour", "hr", "hrs", "h", "min", "mins", "minute", "minutes", "m", "noon", "midnight", "am", "pm",
    "morning", "afternoon", "night", "week", "day", "later", "o'clock", "oclock", "early", "late", "around", "by"}
KEYWORDS = ["effort", "model", "dry", "run", "using", "with", "on", "resume", "continue", "yolo", "claude",
            "permissions", "skipped", "skip", "confirm", "just", "do", "it", "no", "hours", "hour", "min",
            "minutes", "noon", "midnight", "am", "pm", "split", "pane", "new", "tab"] + WEEKDAYS
NOVALUE_FLAGS = {"--continue", "-c", "--dangerously-skip-permissions", "--verbose", "--debug", "--force",
                 "--dry-run", "--print", "-p", "--yolo"}
DELAY_RE = re.compile(r"^(\d+(?:\.\d+)?)(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)?(?:(\d{1,2})(m|min|mins)?)?$", re.I)
UNIT_RE = re.compile(r"^(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)$", re.I)
CLOCK_RE = re.compile(r"^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?$", re.I)
HHMM_RE = re.compile(r"^(\d{2})(\d{2})$")
AMPM_RE = re.compile(r"^(am|pm|a\.m\.|p\.m\.)$", re.I)


def now_ts():
    v = os.environ.get("RUN_AGENT_NOW")
    return float(v) if v else time.time()


def tz():
    name = os.environ.get("RUN_AGENT_TZ")
    if name:
        try:
            from zoneinfo import ZoneInfo
            return ZoneInfo(name)
        except Exception:
            pass
    return datetime.now().astimezone().tzinfo


def local(ts):
    return datetime.fromtimestamp(ts, tz())


def fmt_et(ts):
    d = local(ts)
    return f"{d.strftime('%I').lstrip('0')}:{d.strftime('%M')} {d.strftime('%p')} ET"


def fmt_in(ts, now=None):
    now = now_ts() if now is None else now
    m = int(round((ts - now) / 60))
    if m < 0:
        m = 0
    h, m = divmod(m, 60)
    return f"in {h}h {m}m" if h else f"in {m}m"


def fetch_reset():
    """Return (epoch, None) or (None, reason) for five_hour.resets_at."""
    path = os.environ.get("RUN_AGENT_USAGE_FILE")
    try:
        if path:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        else:
            cred = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")
            with open(cred, encoding="utf-8") as f:
                tok = json.load(f)["claudeAiOauth"]["accessToken"]
            req = urllib.request.Request(
                "https://api.anthropic.com/api/oauth/usage",
                headers={"Authorization": f"Bearer {tok}", "anthropic-beta": "oauth-2025-04-20"})
            with urllib.request.urlopen(req, timeout=15) as r:
                data = json.load(r)
    except Exception as e:  # noqa: BLE001
        return None, f"{type(e).__name__}: {e}"
    fh = data.get("five_hour") if isinstance(data, dict) else None
    if not fh or not fh.get("resets_at"):
        return None, "no five_hour.resets_at in the reply (stale token?)"
    try:
        return datetime.fromisoformat(fh["resets_at"].replace("Z", "+00:00")).timestamp(), None
    except Exception as e:  # noqa: BLE001
        return None, f"bad resets_at {fh['resets_at']!r}: {e}"


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def list_agents():
    try:
        out = subprocess.run([SCRIPT, "--list"], capture_output=True, text=True, timeout=10).stdout
        return [l.strip() for l in out.splitlines() if l.strip()]
    except Exception:  # noqa: BLE001
        return []


# ---------------------------------------------------------------- tokenizer
# Phone keyboards mix straight and curly quotes ("I'm on my phone” was logged), so any double quote closes
# any double quote and any single quote closes any single quote.
OPEN_Q = {'"': '"”“', "'": "'’‘", "“": '”"“', "‘": "’'‘"}


def tokenize(raw):
    """Split on whitespace; a quoted span ("..", '..', curly) becomes one token flagged quoted."""
    toks = []
    i, n = 0, len(raw)
    while i < n:
        c = raw[i]
        if c.isspace():
            i += 1
            continue
        if c in OPEN_Q:
            close = OPEN_Q[c]
            j = i + 1
            while j < n and raw[j] not in close:
                j += 1
            toks.append((raw[i + 1:j], True))
            i = j + 1
            continue
        j = i
        while j < n and not raw[j].isspace():
            j += 1
        toks.append((raw[i:j], False))
        i = j
    return toks


def split_bare(word):
    """Loose forms -> list of plain tokens: commas, key=value, key:value, model+effort, dash flags."""
    out = []
    for part in re.split(r",+", word):
        if not part:
            continue
        # dashes: --x, -x, em/en dash x
        m = re.match(r"^(?:--|—|–|-)(.*)$", part)
        if m and m.group(1) and not re.match(r"^\d", m.group(1)):
            body = m.group(1)
            if "=" in body:
                k, v = body.split("=", 1)
                out.append("--" + k if len(k) > 1 or k == "C" else "-" + k)
                if v:
                    out.append(v)
            else:
                out.append("--" + body if len(body) > 1 else "-" + body)
            continue
        if re.match(r"^[A-Za-z][\w-]*[=:]", part):
            k, v = re.split(r"[=:]", part, maxsplit=1)
            out.append(k)
            if v:
                out.append(v)
            continue
        if part in ("=", ":"):
            continue
        if part.endswith("!") and len(part) > 1:
            out.extend([part[:-1], "!"])
            continue
        if part.startswith("=") or part.startswith(":"):
            out.append(part[1:])
            continue
        if "+" in part and not part.startswith("/") and not part.startswith("~"):
            out.extend(p for p in part.split("+") if p)
            continue
        out.append(part)
    return out


# ------------------------------------------------------------------ parser
class Parse:
    def __init__(self, raw, agents):
        self.raw = raw
        self.agents = agents
        self.agent = ""
        self.prompt = None
        self.dir = None
        self.dirs = []
        self.flags = []
        self.force = 0
        self.dry = 0
        self.target = ""  # "" = replace this pane; "split" / "window" = a new tmux window (never an existing one)
        self.target_ignored = False
        self.at = None
        self.at_text = ""
        self.at_kind = ""  # clock|delay|window|relwin (N before/after the window reset; fixed once the reset is known)
        self.rel_offset = 0  # relwin: seconds added to the reset time
        self.derive = ""  # how the time was read, for at_shown (e.g. "1 hr before window 6:30 AM"); "" = at_text
        self.until = None
        self.until_text = ""
        self.corrections = []
        self.unsure = []
        self.now = now_ts()
        self.known = set(agents) | set(MODELS) | set(EFFORTS) | set(FORCE_WORDS) | set(TIME_WORDS) | set(KEYWORDS)

    # near-miss: unique known word within distance 2 (1 for tokens up to 3 chars); never numbers.
    def correct(self, tok, pool=None):
        low = tok.lower()
        pool = pool if pool is not None else self.known
        if low in pool:
            return low, False
        if not re.search(r"[A-Za-z]", low) or re.search(r"\d", low):
            return None, False
        limit = 1 if len(low) <= 3 else 2
        best, bd = [], limit + 1
        for w in pool:
            d = edit_distance(low, w)
            if d < bd:
                best, bd = [w], d
            elif d == bd:
                best.append(w)
        if len(best) == 1 and bd <= limit:
            c = f"{tok} -> {best[0]}"
            if c not in self.corrections:
                self.corrections.append(c)
            return best[0], True
        return None, False

    def set_flag(self, name, value=None):
        self.flags.append(name)
        if value is not None:
            self.flags.append(value)

    def set_model(self, tok, typed=None):
        w, _ = self.correct(tok, MODELS)
        self.set_flag("--model", w or tok)

    def set_effort(self, tok):
        w, _ = self.correct(tok, EFFORTS)
        self.set_flag("--effort", w or tok)

    # ---- time
    def parse_clock(self, toks, i, day=None, pm_hint=False):
        """Try to read a clock time at toks[i:]; return (epoch, n_tokens) or (None, 0)."""
        for n in (2, 1):
            if i + n > len(toks):
                continue
            s = " ".join(t.lower() for t in toks[i:i + n])
            if n == 2 and not AMPM_RE.match(toks[i + 1]):
                continue
            ts = self.clock_to_epoch(s, day, pm_hint)
            if ts is not None:
                return ts, n
        return None, 0

    def parse_span(self, toks, i):
        """A span at toks[i:] ("2 hours", "two hours", "1 hr 30 min", "an hour", "90m"); (seconds, n) or (None, 0)."""
        if i < len(toks) and toks[i].lower() in NUMBER_WORDS and i + 1 < len(toks) and UNIT_RE.match(toks[i + 1]):
            num = NUMBER_WORDS[toks[i].lower()]
            unit = toks[i + 1].lower()
            secs = num * (3600 if unit.startswith("h") else 60)
            n = 2
            more, k = self.parse_delay(toks, i + 2)
            if k and toks[i + 2].lower() not in NUMBER_WORDS:
                secs += more; n += k
            return secs, n
        return self.parse_delay(toks, i)

    def day_at(self, day, h, mi=0):
        base = local(self.now)
        return (base + timedelta(days=day)).replace(hour=h, minute=mi, second=0, microsecond=0).timestamp()

    def weekday_offset(self, word):
        """days until the next such weekday (never today), or None"""
        w = word.lower().rstrip(",.")
        idx = WEEKDAYS.index(w) if w in WEEKDAYS else WEEKDAY_SHORT.get(w)
        if idx is None:
            return None
        today = local(self.now).weekday()
        return (idx - today) % 7 or 7

    def clock_to_epoch(self, s, day=None, pm_hint=False):
        """epoch of clock string s: the next occurrence (day=None), or on today+day (day=0 today, 1 tomorrow, ...)."""
        s = s.replace("a.m.", "am").replace("p.m.", "pm")
        if s in ("noon", "midnight"):
            h, mi, ap = (12 if s == "noon" else 0), 0, "x"
        else:
            m = CLOCK_RE.match(s)
            if m:
                h, mi, ap = int(m.group(1)), int(m.group(2) or 0), (m.group(3) or "").lower()
                if m.group(2) is None and ap == "" and len(m.group(1)) == 4:
                    h, mi = divmod(int(m.group(1)), 100)
            else:
                m = HHMM_RE.match(s)
                if not m:
                    m2 = re.match(r"^(\d{1,2})(\d{2})(am|pm)$", s)
                    if not m2:
                        return None
                    h, mi, ap = int(m2.group(1)), int(m2.group(2)), m2.group(3)
                else:
                    h, mi, ap = int(m.group(1)), int(m.group(2)), ""
        if mi > 59 or h > 23:
            return None
        if ap in ("am", "pm"):
            if h > 12 or h == 0:
                return None
            h = h % 12 + (12 if ap == "pm" else 0)
            cands = [h]
        elif ap == "x" or h == 0 or h > 12:
            cands = [h]
        elif pm_hint and h < 12:
            cands = [h + 12]  # "tonight at 9" = 9 PM
        else:
            cands = [h, h + 12]  # bare 1-12: next occurrence
        base = local(self.now)
        best = None
        days = (0, 1) if day is None else (day,)
        for hh in cands:
            for dd in days:
                d = (base + timedelta(days=dd)).replace(hour=hh, minute=mi, second=0, microsecond=0)
                if day is not None and len(cands) == 2 and hh < 12 and d.timestamp() <= self.now:
                    continue  # today, bare hour already past: try the PM reading
                if (day is not None or d.timestamp() > self.now) and (best is None or d.timestamp() < best):
                    best = d.timestamp()
        return best

    def parse_delay(self, toks, i):
        """Read a delay at toks[i:]; return (seconds, n_tokens) or (None, 0)."""
        secs, n, j = 0.0, 0, i
        while j < len(toks) and j < i + 4:
            t = toks[j].lower()
            m = DELAY_RE.match(t)
            if not m:
                break
            num, unit, extra = float(m.group(1)), (m.group(2) or "").lower(), m.group(3)
            if not unit:
                # bare number: next token must be a unit
                if j + 1 < len(toks) and UNIT_RE.match(toks[j + 1]):
                    unit = toks[j + 1].lower()
                    j += 1
                else:
                    break
            secs += num * (3600 if unit.startswith("h") else 60)
            if extra:
                secs += int(extra) * 60
            j += 1
            n = j - i
        return (secs, n) if n else (None, 0)

    def run(self):
        toks = tokenize(self.raw)
        # flatten: bare tokens through split_bare; quoted ones stay
        flat = []
        for text, quoted in toks:
            if quoted:
                flat.append((text, True))
            else:
                flat.extend((p, False) for p in split_bare(text))
        # trailing "!" alone = force; "agent!" handled below
        words = [t for t, _ in flat]
        quoted = [q for _, q in flat]
        i = 0
        pending_dir = False
        after_window = False
        while i < len(words):
            w, q = words[i], quoted[i]
            lw = w.lower()
            nxt = words[i + 1] if i + 1 < len(words) else None
            nxt_q = quoted[i + 1] if i + 1 < len(words) else False
            nl = nxt.lower() if nxt and not nxt_q else None
            if q:
                if pending_dir:
                    self.dirs.append(w); pending_dir = False
                elif self.prompt is None:
                    self.prompt = w
                else:
                    self.unsure.append(w)
                i += 1
                continue
            if pending_dir:
                self.dirs.append(w); pending_dir = False; i += 1; continue
            if w == "!":
                self.force = 1; i += 1; continue
            if w == ".":
                if self.prompt is None:
                    self.prompt = "."
                i += 1; continue
            if lw == "claude" and not self.agent:
                i += 1; continue
            # ---- flags
            if w.startswith("-"):
                f = lw
                if f == "--agent" and nxt:
                    self.agent = self.correct(nxt, set(self.agents))[0] or nxt; i += 2; continue
                if f in ("--force", "-f"):
                    self.force = 1; i += 1; continue
                if f in ("--dry-run", "--dry"):
                    self.dry = 1; i += 1; continue
                if f in ("--split", "--new-pane", "--new-window", "--tab"):
                    self.set_target("split" if f in ("--split", "--new-pane") else "window", w); i += 1; continue
                if f in ("--cwd", "-c") and w == "-C" or f == "--cwd":
                    pending_dir = True; i += 1; continue
                if f in ("--model", "-m"):
                    if nxt and not nxt_q:
                        self.set_model(nxt); i += 2
                    else:
                        self.unsure.append(w); i += 1
                    continue
                if f == "--effort":
                    if nxt and not nxt_q:
                        self.set_effort(nxt); i += 2
                    else:
                        self.unsure.append(w); i += 1
                    continue
                if f == "--yolo":
                    self.set_flag("--dangerously-skip-permissions"); i += 1; continue
                if f in ("--resume", "--continue", "-c") and (nl is None or nl.startswith("-") or nl in self.known):
                    self.set_flag("--continue"); i += 1; continue
                if f == "--at":
                    n = self.take_time(words, quoted, i + 1, "at")
                    if n:
                        i += 1 + n; continue
                if f == "--in":
                    n = self.take_time(words, quoted, i + 1, "in")
                    if n:
                        i += 1 + n; continue
                if f == "--after":
                    n = self.take_time(words, quoted, i + 1, "after")
                    if n:
                        i += 1 + n; continue
                if f == "--until":
                    n = self.take_until(words, i + 1)
                    if n:
                        i += 1 + n; continue
                    self.unsure.append(" ".join(words[i:i + 2])); i += 2; continue
                if f == "-n":
                    f = "--name"
                if f in NOVALUE_FLAGS or nxt is None or (nxt.startswith("-") and not nxt_q) \
                        or (not nxt_q and (nl in self.known or nl in self.agents)):
                    self.set_flag(f); i += 1
                else:
                    self.set_flag(f, nxt); i += 2
                continue
            # ---- launch target: split / pane / window / tab (and "new ...") -> a new tmux window; the value kept is
            # "split" for split/pane words, "window" otherwise (both open a new window).
            # A bare "window" is the target; the usage window needs "after/next/when/the window".
            saved = list(self.corrections)
            tw = self.correct(w)[0]
            if tw not in ("new", "split", "pane", "window", "tab"):
                self.corrections = saved
            if tw == "new" and nl in ("pane", "window", "tab"):
                self.set_target("split" if nl == "pane" else "window", w + " " + nxt); i += 2; continue
            if tw in ("split", "pane", "window", "tab"):
                self.set_target("split" if tw in ("split", "pane") else "window", w); i += 1; continue
            # ---- time words
            n = self.take_time(words, quoted, i, None)
            if n:
                i += n; continue
            if lw == "until":
                n = self.take_until(words, i + 1)
                if n:
                    i += 1 + n; continue
                self.unsure.append(" ".join(words[i:i + 2])); i += 2; continue
            # ---- path tokens
            if "/" in w or w.startswith("~"):
                self.dirs.append(w); i += 1; continue
            # ---- near-miss correction on the word itself
            cw, _ = self.correct(w)
            if cw is None:
                if not self.agent and not re.search(r"\d", w):
                    self.agent = w  # unknown agent; validated later
                else:
                    self.unsure.append(w)
                i += 1; continue
            # ---- keywords
            if cw in ("in",):
                if nl is not None:
                    secs, n = self.parse_span(words, i + 1)
                    if n:
                        self.set_at(self.now + secs, " ".join(words[i:i + 1 + n]), "delay"); i += 1 + n; continue
                    pending_dir = True; i += 1; continue
                self.unsure.append(w); i += 1; continue
            if cw in ("using", "with", "on") and nl is not None:
                mw, _ = self.correct(nxt, MODELS)
                if mw:
                    self.set_model(mw); i += 2; continue
                self.unsure.append(w); i += 1; continue
            if cw == "model":
                if nl is not None:
                    self.set_model(nxt); i += 2
                else:
                    self.unsure.append(w); i += 1
                continue
            if cw == "effort":
                if nl is not None and (self.correct(nxt, EFFORTS)[0]):
                    self.set_effort(nxt); i += 2
                else:
                    self.unsure.append(w); i += 1
                continue
            if cw in MODELS:
                self.set_model(cw); i += 1; continue
            if cw in EFFORTS:
                self.set_effort(cw); i += 1
                if nl is not None and self.correct(nxt, ["effort"])[0] == "effort":
                    i += 1
                continue
            if cw == "yolo":
                self.set_flag("--dangerously-skip-permissions"); i += 1; continue
            if cw in ("permissions", "skip") and nl in ("skipped", "permissions"):
                self.set_flag("--dangerously-skip-permissions"); i += 2; continue
            if cw in ("resume", "continue"):
                self.set_flag("--continue"); i += 1; continue
            if cw in FORCE_WORDS:
                self.force = 1; i += 1; continue
            if cw == "just" and nl == "do" and i + 2 < len(words) and words[i + 2].lower() == "it":
                self.force = 1; i += 3; continue
            if cw == "no" and nl == "confirm":
                self.force = 1; i += 2; continue
            if cw == "dry":
                self.dry = 1; i += 1
                if nl == "run":
                    i += 1
                continue
            if cw in self.agents:
                if not self.agent:
                    self.agent = cw
                else:
                    self.unsure.append(w)
                i += 1; continue
            # a known word that fits nowhere here
            self.unsure.append(w); i += 1
        if pending_dir:
            self.unsure.append("in")
        if self.until is not None and self.at_kind != "window":
            self.unsure.append(self.until_text)
            self.until, self.until_text = None, ""

    def set_target(self, target, text):
        # split and window both open a new tmux window now, so "new window split" is not a conflict.
        # RUN_AGENT_IGNORE_TARGET=1 (an agent session calling run-agent): the word is read but dropped, and the
        # output says target_ignored so the caller can print `ignored: agents replace their own pane`.
        if os.environ.get("RUN_AGENT_IGNORE_TARGET"):
            self.target_ignored = True
            return
        if not self.target:
            self.target = target

    def set_at(self, ts, text, kind):
        if self.at is not None:
            self.unsure.append(text)
            return False
        self.at, self.at_text, self.at_kind = ts, text, kind
        return True

    def take_time(self, words, quoted, i, lead, bare=False):
        """Read a time phrase at words[i:], lead = 'at'|'in'|'after'|None (word itself at words[i]).
        Returns the number of tokens consumed (0 = no time phrase here)."""
        if i >= len(words):
            return 0
        lw = words[i].lower() if not quoted[i] else ""
        head = lead or lw
        # window phrases
        j = i if lead else i
        seq = [w.lower() for w in words[i:i + 4]]
        if lead is None:
            n = self.take_day_phrase(words, quoted, i)
            if n:
                return n
            n = self.take_relative(words, quoted, i)
            if n:
                return n
            if seq[0] == "window":
                self.window("window"); return 1
            if seq[0] in ("after", "next", "when") or (seq[0] == "the" and len(seq) > 1 and seq[1] in ("window",)):
                k = 0
                phr = []
                while k < len(seq) and seq[k] in ("after", "next", "when", "the", "window", "reset", "resets", "ends", "usage"):
                    phr.append(seq[k]); k += 1
                    if seq[k - 1] in ("window", "reset", "resets", "ends") and \
                            not (k < len(seq) and seq[k] in ("resets", "ends", "reset")):
                        break
                if any(p in ("window", "reset", "resets") for p in phr):
                    self.window(" ".join(words[i:i + k])); return k
                return 0
            if seq[0] == "at":
                n = self.take_time(words, quoted, i + 1, "at", bare=True)
                if n:
                    return 1 + n
                if len(seq) > 1 and not quoted[i + 1]:
                    self.unsure.append(" ".join(words[i:i + 2])); return 2
                self.unsure.append("at"); return 1
            return 0
        # lead given by a flag (--at / --in / --after): words[i:] are the value
        if head == "after":
            if seq and seq[0] in ("window", "reset", "the", "next"):
                k = 0
                while k < len(seq) and seq[k] in ("the", "window", "reset", "resets", "next", "ends"):
                    k += 1
                self.window("after " + " ".join(words[i:i + k])); return max(k, 1)
            self.unsure.append("--after " + (words[i] if i < len(words) else "")); return 1
        if head == "in":
            secs, n = self.parse_span(words, i)
            if n:
                self.set_at(self.now + secs, "in " + " ".join(words[i:i + n]), "delay"); return n
            self.unsure.append("--in " + words[i]); return 1
        if head == "at":
            if seq[0] in ("window", "after", "next", "when"):
                return self.take_time(words, quoted, i, None)
            n = self.take_day_phrase(words, quoted, i, lead="at")
            if n:
                return n
            ts, n = self.parse_clock(words, i)
            if n:
                # "at 1am tomorrow"
                if i + n < len(words) and not quoted[i + n] and words[i + n].lower() == "tomorrow":
                    ts = self.clock_to_epoch(" ".join(words[i:i + n]).lower(), day=1)
                    self.set_at(ts, "at " + " ".join(words[i:i + n + 1]), "clock"); return n + 1
                self.set_at(ts, "at " + " ".join(words[i:i + n]), "clock"); return n
            secs, n = self.parse_delay(words, i)
            if n:
                self.set_at(self.now + secs, "in " + " ".join(words[i:i + n]), "delay"); return n
            if bare:
                return 0
            self.unsure.append("--at " + words[i]); return 1
        return 0

    def window(self, text):
        self.set_at(-1, text, "window")

    # ---- day phrases: tomorrow [at] <clock>, <clock> tomorrow, tonight, today, this evening, noon, midnight,
    # weekday names [at <clock>]. Returns tokens consumed (0 = none here).
    def take_day_phrase(self, words, quoted, i, lead=None):
        def lw(k):
            return words[k].lower() if k < len(words) and not quoted[k] else ""
        w0 = lw(i)
        head = i
        skip_at = 1 if lead == "at" else 0
        # <clock> tomorrow
        if w0 not in ("tomorrow", "tonight", "today", "this", "noon", "midnight", "next") and self.weekday_offset(w0) is None:
            ts, n = self.parse_clock(words, i)
            if n and lw(i + n) == "tomorrow":
                ts = self.clock_to_epoch(" ".join(words[i:i + n]).lower(), day=1)
                self.set_at(ts, ("at " if lead == "at" else "") + " ".join(words[i:i + n + 1]), "clock")
                return n + 1
            return 0
        k = i
        day = None; default_h = None; pm_hint = False; label = []
        if w0 == "tomorrow":
            day, default_h = 1, 9; k += 1
        elif w0 == "tonight":
            day, default_h, pm_hint = 0, 19, True; k += 1
        elif w0 == "today":
            day = 0; k += 1
        elif w0 == "this" and lw(i + 1) in ("evening", "afternoon", "morning"):
            day, pm_hint = 0, lw(i + 1) != "morning"
            default_h = {"evening": 19, "afternoon": 15, "morning": 9}[lw(i + 1)]; k += 2
        elif w0 in ("noon", "midnight"):
            ts = self.clock_to_epoch(w0)
            self.set_at(ts, ("at " if lead == "at" else "") + words[i], "clock"); return 1
        else:
            off = None
            if w0 == "next":
                off = self.weekday_offset(lw(i + 1))
                if off is None:
                    return 0
                k += 2
            else:
                off = self.weekday_offset(w0); k += 1
            day, default_h = off, 9
        # optional "at <clock>" / "<clock>" after the day word
        if lw(k) == "at":
            ts, n = self.parse_clock(words, k + 1, day=day, pm_hint=pm_hint)
            if n:
                k += 1 + n
            else:
                self.unsure.append(" ".join(words[i:k + 2])); return k + 2 - i
        else:
            ts, n = self.parse_clock(words, k, day=day, pm_hint=pm_hint)
            if n and not (lw(k) in self.known and not re.match(r"^\d", lw(k))):
                k += n
            else:
                ts = None
        if ts is None:
            if default_h is None:  # "today" with no clock
                self.unsure.append(" ".join(words[i:k])); return k - i
            ts = self.day_at(day, default_h)
            label.append(f"default {fmt_et(ts).replace(' ET', '')}")
        if ts <= self.now:
            self.unsure.append(" ".join(words[i:k]) + " (already past)"); return k - i
        text = ("at " if lead == "at" else "") + " ".join(words[i:k])
        if self.set_at(ts, text, "clock") and label:
            self.derive = text + ", " + ", ".join(label)
        return k - i

    # ---- relative phrases: <span> before|after [the] [current] window [ends|resets] | <span> before|after <clock>
    def take_relative(self, words, quoted, i):
        def lw(k):
            return words[k].lower() if k < len(words) and not quoted[k] else ""
        secs, n = self.parse_span(words, i)
        if not n or lw(i + n) not in ("before", "after"):
            return 0
        sign = -1 if lw(i + n) == "before" else 1
        k = i + n + 1
        span_text = " ".join(words[i:i + n])
        j = k
        while lw(j) in ("the", "current", "usage", "my", "this"):
            j += 1
        if lw(j) in ("window", "reset"):
            j += 1
            while lw(j) in ("ends", "resets", "reset", "end"):
                j += 1
            if self.set_at(-1, " ".join(words[i:j]), "relwin"):
                self.rel_offset = sign * secs
                self.derive = f"{span_text} {'before' if sign < 0 else 'after'} window"
            return j - i
        ts, m = self.parse_clock(words, k)
        if m:
            ts += sign * secs
            if ts <= self.now:
                self.unsure.append(" ".join(words[i:k + m]) + " (already past)"); return k + m - i
            if self.set_at(ts, " ".join(words[i:k + m]), "clock"):
                self.derive = f"{span_text} {'before' if sign < 0 else 'after'} {fmt_et(ts - sign * secs).replace(' ET', '')}"
            return k + m - i
        if lw(k) in ("noon", "midnight", "tomorrow", "tonight"):
            save = (self.at, self.at_text, self.at_kind)
            self.at = None
            m = self.take_day_phrase(words, quoted, k)
            if m and self.at is not None and self.at >= 0:
                anchor = self.at
                self.at = None
                self.set_at(anchor + sign * secs, " ".join(words[i:k + m]), "clock")
                self.derive = f"{span_text} {'before' if sign < 0 else 'after'} {fmt_et(anchor).replace(' ET', '')}"
                if save[0] is not None:
                    self.unsure.append(self.at_text); self.at, self.at_text, self.at_kind = save
                return k + m - i
            self.at, self.at_text, self.at_kind = save
        self.unsure.append(" ".join(words[i:k + 1])); return k + 1 - i

    def take_until(self, words, i):
        ts, n = self.parse_clock(words, i)
        if n:
            if self.until is None:
                self.until, self.until_text = ts, "until " + " ".join(words[i:i + n])
            else:
                self.unsure.append("until " + " ".join(words[i:i + n]))
            return n
        return 0


def shell(args):
    return " ".join(shlex.quote(a) for a in args)


def main():
    argv = sys.argv[1:]
    if argv and argv[0] == "--reset":
        ts, err = fetch_reset()
        if err:
            print(f"error: {err}"); sys.exit(2)
        print(int(ts)); return
    if argv and argv[0] == "--fmt":
        print(fmt_et(float(argv[1]))); return
    raw = " ".join(argv)
    agents = list_agents()
    p = Parse(raw, agents)
    p.run()

    out = {"agent": p.agent, "agent_ok": p.agent in agents, "prompt": p.prompt, "dir": "", "dir_state": "",
           "flags": shell(p.flags), "force": p.force, "at": "", "at_text": p.at_text, "at_shown": "",
           "until": "", "until_shown": "", "reset": "", "reset_shown": "",
           "corrections": p.corrections, "unsure": p.unsure, "dry": p.dry}
    if len(p.dirs) > 1:
        out["error"] = "usage: two directories: " + ", ".join(p.dirs)
    elif p.dirs:
        r = subprocess.run([SCRIPT, "--resolve", p.dirs[0]], capture_output=True, text=True)
        if r.returncode == 0:
            out["dir"], out["dir_state"] = r.stdout.rstrip("\n").split("\t")
        else:
            out["error"] = (r.stderr or r.stdout).strip()
    out["dir_typed"] = p.dirs[0] if p.dirs else ""
    # default prompt
    prompt = p.prompt
    if prompt is None and p.agent in ("worker", "evaluator", "helper"):
        prompt = "."
    out["prompt"] = prompt if prompt is not None else ""
    # window / reset
    need_reset = p.at is not None or p.dry or p.at_kind == "relwin"
    if need_reset:
        reset, err = fetch_reset()
        if reset is not None:
            out["reset"] = int(reset)
            out["reset_shown"] = fmt_et(reset)
        elif p.at_kind == "window":
            out["at_error"] = f"usage API: {err}; open any claude session to refresh the token"
        else:
            out["reset_shown"] = f"unavailable ({err})"
        if p.at_kind == "window" and reset is not None:
            p.at = reset
        if p.at_kind == "relwin":
            if reset is None:
                out["at_error"] = f"usage API: {err}; open any claude session to refresh the token"
            else:
                p.at = reset + p.rel_offset
                p.derive += f" {fmt_et(reset).replace(' ET', '')}"
                if p.at <= p.now:
                    out["at_error"] = f"{p.at_text} = {fmt_et(p.at)}, already past (window resets {fmt_et(reset)})"
                    p.at = None
    if p.at is not None and p.at >= 0:
        out["at"] = int(p.at)
        out["at_shown"] = f"{fmt_et(p.at)} ({p.derive or p.at_text}, {fmt_in(p.at, p.now)})"
    if p.until is not None:
        out["until"] = int(p.until)
        out["until_shown"] = fmt_et(p.until)
        out["until_text"] = p.until_text
        if out.get("reset") and p.until < out["reset"]:
            out["skipped"] = f"skipped: reset {out['reset_shown']} is after until {out['until_shown']}"
    # the claude command as shown in the confirmation, and the S call that runs it
    folder = ""
    if out["dir"]:
        folder = os.path.basename(out["dir"])
    else:
        try:
            top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
        except Exception:  # noqa: BLE001
            top = ""
        folder = os.path.basename(top or os.getcwd())
    flags = list(p.flags)
    has_name = any(f in ("--name", "-n") or f.startswith("--name=") for f in flags)
    model = ""
    for k, f in enumerate(flags):
        if f in ("--model", "-m") and k + 1 < len(flags):
            model = flags[k + 1]
    if not has_name and p.agent:
        name = f"{p.agent}: {folder}" + (f" ({model})" if model else "")
        flags += ["--name", name]
    shown = f"claude --agent {p.agent}"
    if prompt is not None:
        shown += f' "{prompt}"'
    prev = ""
    for f in flags:
        shown += f' "{f}"' if prev in ("--name", "-n") else f" {f}"
        prev = f
    out["command"] = shown
    run = ["S", p.agent]
    if prompt is not None:
        run.append(prompt)
    if out["dir"]:
        run += ["--cwd", out["dir"]]
    if out["at"] != "":
        run += ["--at", str(out["at"]), "--at-text", p.at_text]
        if p.at_kind == "window":
            run.append("--window")
        if p.derive:
            run += ["--at-shown", out["at_shown"]]
        if out["until"] != "":
            run += ["--until", str(out["until"])]
    if p.target:
        out["target"] = p.target  # only present when given, so the parse of every older string is unchanged
        run += ["--target", p.target]
    if p.target_ignored:
        out["target_ignored"] = 1
    if p.flags:
        run.append("--")
        run += p.flags
    out["run"] = shell(run)
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
