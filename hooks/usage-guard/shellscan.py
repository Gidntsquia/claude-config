"""shellscan: find headless `claude` launches in a shell command without running anything.

analyze(command, cwd, env) -> Result with .launches (list of Launch) and .cmds (the simple commands, for the
tamper check). A heuristic reader of bash, not a parser: quotes, heredocs, comments, `$(...)`, pipes, `&`, groups and
for/while loops are understood well enough to tell a command word from data. Standard library only.
"""
import glob as _glob
import os
import re

UNKNOWN = 3          # iterations / parallelism we cannot read: one more than the limit, so it blocks
MANY = 99
MAX_FILES = 12       # scripts opened per command
MAX_DEPTH = 3        # run.sh -> scene.sh -> drive.py
HEAD_LINES = 200
NEED = ("--max-budget-usd", "--max-turns")
SUBCMDS = {"auth", "agents", "mcp", "config", "update", "doctor", "plugin", "plugins", "install", "setup-token",
           "help", "migrate-installer", "upgrade", "logout", "login"}
WRAPPERS = {"nohup", "time", "nice", "setsid", "command", "exec", "sudo", "unbuffer", "stdbuf", "ionice", "caffeinate",
            "builtin", "chronic"}
KEYWORDS = {"do", "then", "else", "elif", "if", "!", "while", "until"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
PYTHONS = re.compile(r"^(python[\d.]*|pypy[\d.]*|node|bun|deno)$")
VAR = re.compile(r"\$\{?(\w+)(?:\[[@*]\])?\}?")


class Launch:
    def __init__(self, missing, via, script=None, guardflags=False):
        self.conc = 1            # how many of this launch run at once
        self.n = None            # how many launches in total (None: same as conc)
        self.missing = list(missing)
        self.via = via
        self.script = script     # the file whose text holds the launch, None when it is in the command itself
        self.guardflags = guardflags   # the script reads CLAUDE_GUARD_FLAGS
        self.par_var = False     # parallelism came from a variable (so a caller's -j N overrides it)
        self.bg = False
        self.pipe = ()           # pipeline ids from the outermost command inwards

    def total(self):
        return self.n if self.n is not None else self.conc


class Tok:
    __slots__ = ("kind", "text", "quoted", "subs")

    def __init__(self, kind, text, quoted=False):
        self.kind, self.text, self.quoted, self.subs = kind, text, quoted, []

    def __repr__(self):
        return f"{self.kind}:{self.text!r}"


def _balanced(s, i, open_c="(", close_c=")"):
    """s[i] is just past an opener; return index just past its matching closer"""
    depth, n, q = 1, len(s), ""
    while i < n:
        c = s[i]
        if q:
            if c == "\\" and q == '"':
                i += 1
            elif c == q:
                q = ""
        elif c in "'\"":
            q = c
        elif c == "\\":
            i += 1
        elif c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def lex(s):
    """-> list of Tok: kind w (word), op, redir, heredoc (text = body, quoted = fed to the command as stdin)"""
    toks, cur, i, n = [], None, 0, len(s)
    pending = []   # heredoc delimiters waiting for the next newline: (delim, strip_tabs)

    def word():
        nonlocal cur
        if cur is None:
            cur = Tok("w", "")
        return cur

    def flush():
        nonlocal cur
        if cur is not None:
            toks.append(cur)
            cur = None

    while i < n:
        c = s[i]
        if c == "\\":
            if i + 1 < n and s[i + 1] == "\n":
                i += 2
                continue
            word().text += s[i + 1:i + 2]
            cur.quoted = True
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            j = n if j < 0 else j
            word().text += s[i + 1:j]
            cur.quoted = True
            i = j + 1
            continue
        if c == '"':
            w = word()
            w.quoted = True
            i += 1
            while i < n and s[i] != '"':
                if s[i] == "\\" and i + 1 < n:
                    if s[i + 1] in '"\\$`\n':
                        w.text += "" if s[i + 1] == "\n" else s[i + 1]
                    else:
                        w.text += s[i:i + 2]
                    i += 2
                elif s[i] == "$" and s[i + 1:i + 2] == "(":
                    j = _balanced(s, i + 2)
                    w.subs.append(s[i + 2:j - 1])
                    w.text += s[i:j]
                    i = j
                elif s[i] == "`":
                    j = s.find("`", i + 1)
                    j = n if j < 0 else j
                    w.subs.append(s[i + 1:j])
                    w.text += s[i:j + 1]
                    i = j + 1
                else:
                    w.text += s[i]
                    i += 1
            i += 1
            continue
        if c == "$" and s[i + 1:i + 2] == "(":
            j = _balanced(s, i + 2)
            w = word()
            w.subs.append(s[i + 2:j - 1])
            w.text += s[i:j]
            i = j
            continue
        if c == "$" and s[i + 1:i + 2] == "{":
            j = _balanced(s, i + 2, "{", "}")
            word().text += s[i:j]
            i = j
            continue
        if c == "`":
            j = s.find("`", i + 1)
            j = n if j < 0 else j
            w = word()
            w.subs.append(s[i + 1:j])
            w.text += s[i:j + 1]
            i = j + 1
            continue
        if c in "<>" and s[i + 1:i + 2] == "(" and cur is None:   # process substitution
            j = _balanced(s, i + 2)
            w = word()
            w.subs.append(s[i + 2:j - 1])
            w.text += s[i:j]
            i = j
            continue
        if c == "#" and cur is None:
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "\n":
            flush()
            toks.append(Tok("op", "\n"))
            i += 1
            while pending:
                delim, strip = pending.pop(0)
                body = []
                while i <= n:
                    j = s.find("\n", i)
                    line = s[i:] if j < 0 else s[i:j]
                    i = n + 1 if j < 0 else j + 1
                    if (line.lstrip("\t") if strip else line) == delim:
                        break
                    body.append(line)
                toks.append(Tok("heredoc", "\n".join(body)))
            i = min(i, n)
            continue
        if c in " \t\r":
            flush()
            i += 1
            continue
        if c in "<>":
            # fd prefix (2>, 1>>) belongs to the redirect, not to a word
            if cur is not None and cur.text.isdigit() and not cur.quoted:
                cur = None
            flush()
            m = re.match(r"<<<|<<-?|<>|<&|>>|>&|>\||[<>]", s[i:])
            op = m.group(0)
            i += len(op)
            if op in ("<<", "<<-"):
                while i < n and s[i] in " \t":
                    i += 1
                m2 = re.match(r"""'([^']*)'|"([^"]*)"|\\?([\w.+-]+)""", s[i:])
                if m2:
                    pending.append((next(g for g in m2.groups() if g is not None), op == "<<-"))
                    i += len(m2.group(0))
                continue
            toks.append(Tok("redir", op))
            continue
        if c == "&":
            if s[i + 1:i + 2] == ">":                      # &> file
                flush()
                toks.append(Tok("redir", "&>"))
                i += 3 if s[i + 2:i + 3] == ">" else 2
                continue
            flush()
            if s[i + 1:i + 2] == "&":
                toks.append(Tok("op", "&&"))
                i += 2
            else:
                toks.append(Tok("op", "&"))
                i += 1
            continue
        if c == "|":
            flush()
            if s[i + 1:i + 2] == "|":
                toks.append(Tok("op", "||"))
                i += 2
            else:
                toks.append(Tok("op", "|"))
                i += 2 if s[i + 1:i + 2] == "&" else 1
            continue
        if c == ";":
            flush()
            toks.append(Tok("op", ";"))
            i += 2 if s[i + 1:i + 2] == ";" else 1
            continue
        if c in "()":
            flush()
            toks.append(Tok("op", c))
            i += 1
            continue
        word().text += c
        i += 1
    flush()
    return toks


class Cmd:
    def __init__(self):
        self.words, self.redirs, self.heredoc = [], [], None
        self.bg, self.loop, self.loop_known, self.pipe = False, 1, True, 0


def _iters(words, cwd):
    """iterations of `for x in ...` (words after `in`); None when unreadable"""
    n = 0
    for w in words:
        t = w.text
        m = re.fullmatch(r"\{(-?\d+)\.\.(-?\d+)\}", t)
        if m and not w.quoted:
            n += abs(int(m.group(2)) - int(m.group(1))) + 1
        elif w.subs:
            m = re.fullmatch(r"\s*seq\s+(?:(\d+)\s+)?(\d+)\s*", w.subs[0])
            if not m or len(w.subs) > 1:
                return None
            n += int(m.group(2)) - int(m.group(1) or 1) + 1
        elif "$" in t:
            return None
        elif not w.quoted and re.search(r"[*?\[]", t):
            hits = _glob.glob(os.path.join(cwd, t)) if cwd else []
            if not hits:
                return None
            n += len(hits)
        else:
            n += 1
    return n


def split_cmds(toks, cwd):
    """tokens -> list of Cmd with bg / loop multiplier / pipeline id"""
    cmds, cur, groups, loops, pipe = [], Cmd(), [], [], 0
    last_close = None      # (start index) of a group or loop that just closed, for a following &
    want_target = None

    def flush():
        nonlocal cur, last_close
        if cur.words or cur.redirs or cur.heredoc is not None:
            first = cur.words[0].text if cur.words and not cur.words[0].quoted else ""
            if first == "done" or first == "fi" or first == "esac" or first == "}":
                if first == "done" and loops:
                    start = loops.pop()[2]
                    last_close = start
                elif first == "}" and groups:
                    last_close = groups.pop()
                cur = Cmd()
                return
            if first == "{":
                groups.append(len(cmds))
                cur.words = cur.words[1:]
            if first == "for" or first == "select":
                it = None
                names = [w.text for w in cur.words]
                if "in" in names:
                    it = _iters(cur.words[names.index("in") + 1:], cwd)
                loops.append((it if it is not None else UNKNOWN, it is not None, len(cmds)))
                cur = Cmd()
                return
            if first in ("while", "until"):
                loops.append((UNKNOWN, False, len(cmds)))
            for it, known, _ in loops:
                cur.loop *= it
                cur.loop_known = cur.loop_known and known
            cur.pipe = pipe
            if cur.words or cur.heredoc is not None or cur.redirs:
                cmds.append(cur)
                last_close = None
        cur = Cmd()

    for t in toks:
        if t.kind == "redir":
            want_target = t.text
            continue
        if t.kind == "heredoc":
            tgt = cur if (cur.words or not cmds) else cmds[-1]
            tgt.heredoc = t.text
            continue
        if t.kind == "w":
            if want_target is not None:
                cur.redirs.append((want_target, t))
                want_target = None
            else:
                cur.words.append(t)
            continue
        want_target = None
        op = t.text
        if op == "|":
            flush()
            continue
        if op == "(":
            flush()
            groups.append(len(cmds))
            continue
        if op == ")":
            flush()
            last_close = groups.pop() if groups else None
            continue
        was_close = last_close
        flush()
        if op == "&":
            if cmds and last_close is None and was_close is None:
                cmds[-1].bg = True
                # the whole pipeline goes to the background
                for c in cmds:
                    if c.pipe == cmds[-1].pipe:
                        c.bg = True
            elif last_close is not None or was_close is not None:
                start = last_close if last_close is not None else was_close
                for c in cmds[start:]:
                    c.bg = True
        last_close = None
        pipe += 1
    flush()
    return cmds


def _expand(text, env):
    return VAR.sub(lambda m: env.get(m.group(1), m.group(0)), text)


def _is_claude(word, env):
    t = word.strip()
    m = re.fullmatch(r"\$\{?(\w+)\}?", t)
    if m:
        v = env.get(m.group(1))
        if v is not None:
            return os.path.basename(v.strip()) == "claude"
        return "claude" in m.group(1).lower()
    return os.path.basename(_expand(t, env)) == "claude"


def claude_args(args, env):
    """-> None when this claude call is not a headless launch, else the list of missing flags"""
    flat = []
    for a in args:
        e = _expand(a, env)
        flat += e.split() if e != a else [a]
    if flat and flat[0] in SUBCMDS:
        return None
    if any(a in ("--version", "-v", "--help", "-h") for a in flat):
        return None
    if not any(a in ("-p", "--print", "--agent", "--bg") or a.startswith("--agent=")
               or re.fullmatch(r"-[a-oq-zA-Z]*p[a-zA-Z]*", a) for a in flat):
        return None
    return [f for f in NEED if not any(a == f or a.startswith(f + "=") for a in flat)]


def _num(text, env):
    """(value, from_var) of a -j/-P argument"""
    if text is None:
        return None, False
    e = _expand(text, env).strip()
    from_var = "$" in text
    if e.isdigit():
        v = int(e)
        return (MANY if v == 0 else v), from_var
    return None, True


def _jobs(args, env):
    """-j N / -jN / --jobs N / -P N among a script's arguments -> (N or None, the other arguments)"""
    n, rest, i = None, [], 0
    while i < len(args):
        a = args[i]
        m = re.fullmatch(r"(?:-j|-P|--jobs=|--max-procs=|--parallel=|--workers=)(\d+)", a)
        if m:
            n = int(m.group(1))
        elif a in ("-j", "-P", "--jobs", "--max-procs", "--parallel", "--workers") and i + 1 < len(args):
            v, _ = _num(args[i + 1], env)
            n = v if v is not None else UNKNOWN
            i += 1
        else:
            rest.append(a)
        i += 1
    return n, rest


class Scan:
    def __init__(self, cwd, env=None):
        self.cwd = cwd or "/"
        self.origin = self.cwd
        self.env = dict(env or {})
        self.files = 0
        self.cmds = []          # every simple command seen at the top level (for the tamper check)
        self.script_texts = []  # (path, text) of scripts opened

    # -- files ---------------------------------------------------------------------------------------------------
    def _resolve(self, text, base, env):
        cands = []
        for t in (os.path.expanduser(_expand(text, env)), os.path.expanduser(text)):
            cands.append(t)
            # "$HERE/x.sh", "$(dirname "$0")/x.sh": drop the part we cannot read and look beside the script
            u = t
            while True:
                if u.startswith("$("):
                    u = u[_balanced(u, 2):]
                elif u.startswith("`") and "`" in u[1:]:
                    u = u[u.index("`", 1) + 1:]
                else:
                    m = re.match(r"\$\{?\w+\}?", u)
                    if not m:
                        break
                    u = u[m.end():]
            if u != t and u.startswith("/"):
                cands.append(u.lstrip("/"))
        for c in cands:
            if "$" in c or "`" in c:
                continue
            for b in (base, self.cwd, self.origin):
                p = c if os.path.isabs(c) else os.path.join(b, c)
                if os.path.isfile(p):
                    return os.path.normpath(p)
        return None

    def _head(self, path):
        try:
            with open(path, "rb") as f:
                raw = f.read(65536)
        except OSError:
            return None
        if b"\0" in raw[:1024]:
            return None
        return "\n".join(raw.decode("utf-8", "replace").split("\n")[:HEAD_LINES])

    def script(self, path, args, depth, env):
        """launches a script file would make, with the caller's -j N and scene arguments applied"""
        if depth > MAX_DEPTH or self.files >= MAX_FILES:
            return []
        text = self._head(path)
        if text is None:
            return []
        self.files += 1
        self.script_texts.append((path, text))
        first = text.split("\n", 1)[0]
        is_py = path.endswith((".py", ".js", ".mjs", ".ts")) or (first.startswith("#!") and re.search(r"python|node", first))
        if is_py:
            found = self.code(text, path, depth)
        else:
            sub = Scan(os.path.dirname(path), {})
            sub.origin = self.origin
            sub.files, sub.script_texts = self.files, self.script_texts
            found = sub.shell(text, depth, script=path)
            self.files = sub.files
        if not found:
            return []
        jn, rest = _jobs(args, env)
        positional = [a for a in rest if not a.startswith("-")]
        listed = None
        if positional and re.search(r'\$[@*]|\$\{[@*]\}', text):
            listed = len(positional)
            if any(re.search(r"[$*?`]", a) for a in positional):   # $ST, scenes/a0*: several names, count unknown
                listed = max(listed, jn or UNKNOWN)
        elif not is_py:
            listed = self._listable(text, os.path.dirname(path))
        for L in found:
            if L.script is None:
                L.script = path
            if "CLAUDE_GUARD_FLAGS" in text:
                L.guardflags = True
            parallel = L.par_var or L.conc > 1 or jn is not None
            if jn is not None and (L.par_var or L.conc <= 1):
                L.conc = jn
            if parallel and listed is not None:
                L.n = listed if L.n is None else max(L.n, listed)
                L.conc = min(L.conc, listed)
        return found

    def _listable(self, text, base):
        """the size of the work list a script builds with `ls <dir>/*.x` (the scene list), when it can be read"""
        for line in text.split("\n"):
            if line.lstrip().startswith("#") or "*" not in line or not re.search(r"\b(ls|for|find|printf|echo)\b", line):
                continue
            for m in re.finditer(r"""["']?((?:\$\([^)]*\)|\$\{?\w+\}?)?["']?/?[\w./"'-]*\*[\w.*-]*)""", line):
                pat = m.group(1).replace('"', "").replace("'", "")
                pat = re.sub(r"^(?:\$\([^)]*\)|\$\{?\w+\}?)/?", "", pat)
                if not pat or pat.startswith("*") and "/" not in pat and "." not in pat:
                    continue
                hits = [h for h in _glob.glob(os.path.join(base, pat)) if os.path.isfile(h)]
                if "grep -v '^_'" in line or 'grep -v "^_"' in line:
                    hits = [h for h in hits if not os.path.basename(h).startswith("_")]
                if hits:
                    return len(hits)
        return None

    def code(self, text, path, depth):
        """Python / JS text: argv lists and command strings that start a headless claude"""
        out, body = [], "\n".join(l for l in text.split("\n") if not l.lstrip().startswith(("#", "//")))
        flags_here = [f for f in NEED if f not in body]
        guardflags = "CLAUDE_GUARD_FLAGS" in body
        hit = False
        for m in re.finditer(r"""[\[(]\s*(?:[frb]?["']([^"']*)["']|([A-Za-z_][\w.\[\]"']*))\s*,([^\]\)]*)""", body):
            lit, ident, rest = m.group(1), m.group(2), m.group(3)
            if lit is not None and os.path.basename(lit) != "claude":
                continue
            if lit is None and "claude" not in ident.lower():
                continue
            if re.search(r"""["'](-p|--print|--agent|--bg)["']""", rest):
                hit = True
        if re.search(r"""(?:system|[pP]open|run|call|check_output|check_call|spawn\w*|exec\w*)\s*\(\s*[frb]?["'](?:[^"'\s]*/)?claude\s[^"'\n]*?(?<![\w-])(-p|--print|--agent|--bg)(?![\w-])""", body):
            hit = True
        if hit:
            out.append(Launch(flags_here, "script", script=path, guardflags=guardflags))
        # one more level: scripts this file starts
        elif depth < MAX_DEPTH and re.search(r"subprocess|os\.system|Popen|spawn|exec", body):
            for m in re.finditer(r"""["']([\w./-]+\.(?:sh|py))["']""", body):
                p = self._resolve(m.group(1), os.path.dirname(path), {})
                if p and p != path and all(p != q for q, _ in self.script_texts):
                    out += self.script(p, [], depth + 1, {})
        return out

    # -- shell ---------------------------------------------------------------------------------------------------
    def shell(self, text, depth=0, script=None):
        cmds = split_cmds(lex(text), self.cwd)
        if depth == 0 and script is None:
            self.cmds += cmds
        out = []
        for c in cmds:
            found = []
            for w in c.words + [t for _, t in c.redirs]:
                for sub in w.subs:
                    found += self.shell(sub, depth, script)
            found += self.cmd(c, depth, script)
            for L in found:
                if c.loop > 1:
                    tot = L.total()
                    if c.bg:
                        L.conc *= c.loop
                    L.n = tot * c.loop
                if c.bg:
                    L.bg = True
                L.pipe = (c.pipe,) + L.pipe
            out += found
        return out

    def cmd(self, c, depth, script):
        words = [w.text for w in c.words]
        env = self.env
        local = {}
        # keywords, assignments and wrappers in front of the command word
        i = 0
        while i < len(words):
            w = words[i]
            m = re.fullmatch(r"(\w+)=(.*)", w, re.S)
            if m:
                val = m.group(2)
                if c.words[i].subs and re.search(r"(command\s+-v|which|type\s+-P)\s+claude", " ".join(c.words[i].subs)):
                    val = "claude"
                local[m.group(1)] = _expand(val, {**env, **local})
                i += 1
            elif w in KEYWORDS and not c.words[i].quoted:
                i += 1
            elif w in ("export", "local", "declare", "readonly", "typeset") and i + 1 < len(words):
                i += 1
                while i < len(words) and words[i].startswith("-"):
                    i += 1
            elif w in WRAPPERS:
                i += 1
                two = {"sudo": ("-u", "-g"), "nice": ("-n",), "ionice": ("-c", "-n")}.get(w, ())
                while i < len(words) and words[i].startswith("-"):
                    i += 2 if words[i] in two else 1
            elif w == "env":
                i += 1
                while i < len(words) and (words[i].startswith("-") or re.fullmatch(r"\w+=.*", words[i], re.S)):
                    m2 = re.fullmatch(r"(\w+)=(.*)", words[i], re.S)
                    if m2:
                        local[m2.group(1)] = m2.group(2)
                    elif words[i] in ("-u", "-C", "-S"):
                        i += 1
                    i += 1
            elif w == "timeout":
                i += 1
                while i < len(words) and words[i].startswith("-"):
                    i += 2 if words[i] in ("-k", "-s", "--signal", "--kill-after") else 1
                i += 1   # the duration
            else:
                break
        if i >= len(words):
            env.update(local)      # a bare assignment lasts for the rest of the command
            return []
        e = {**env, **local}
        w, args = words[i], words[i + 1:]
        base = os.path.basename(_expand(w, e))

        if w == "cd" and args and script is None:
            p = os.path.expanduser(_expand(args[-1], e))
            if "$" not in p:
                self.cwd = os.path.normpath(os.path.join(self.cwd, p))
            return []

        if _is_claude(w, e):
            missing = claude_args(args, e)
            if missing is None:
                return []
            return [Launch(missing, "claude")]

        if base == "xargs":
            par, pv, j = None, False, 0
            while j < len(args):
                a = args[j]
                if a in ("-P", "--max-procs") and j + 1 < len(args):
                    par, pv = _num(args[j + 1], e)
                    par = UNKNOWN if par is None else par
                    j += 2
                elif re.fullmatch(r"(-P|--max-procs=)(.+)", a):
                    par, pv = _num(re.fullmatch(r"(-P|--max-procs=)(.+)", a).group(2), e)
                    par = UNKNOWN if par is None else par
                    j += 1
                elif a in ("-n", "-I", "-L", "-d", "-a", "-s", "-E"):
                    j += 2
                elif a.startswith("-"):
                    j += 1
                else:
                    break
            found = self._words(args[j:], c, depth, script, e)
            for L in found:
                if par is not None:
                    L.conc *= par
                    L.par_var = L.par_var or pv
            return found

        if base == "parallel":
            par, pv, j = os.cpu_count() or 8, False, 0
            while j < len(args):
                a = args[j]
                if a in ("-j", "--jobs", "-P", "--max-procs") and j + 1 < len(args):
                    par, pv = _num(args[j + 1].rstrip("%"), e)
                    par = UNKNOWN if par is None else par
                    j += 2
                elif re.fullmatch(r"(-j|--jobs=|-P)(\d+)%?", a):
                    par = int(re.fullmatch(r"(-j|--jobs=|-P)(\d+)%?", a).group(2)) or MANY
                    j += 1
                elif a.startswith("-"):
                    j += 1
                else:
                    break
            rest = args[j:]
            items = None
            if ":::" in rest:
                k = rest.index(":::")
                items = len([x for x in rest[k + 1:] if x != ":::"])
                rest = rest[:k]
            found = self._words(rest, c, depth, script, e)
            for L in found:
                L.conc *= par
                L.par_var = L.par_var or pv
                if items:
                    L.n = items
                    L.conc = min(L.conc, items)
            return found

        if base == "find" and any(a in ("-exec", "-execdir") for a in args):
            k = next(j for j, a in enumerate(args) if a in ("-exec", "-execdir"))
            found = self._words(args[k + 1:], c, depth, script, e)
            for L in found:
                L.n = max(L.total(), UNKNOWN)
            return found

        if base in SHELLS or base in ("source", ".", "eval"):
            j = 0
            if base == "eval":
                return self.shell(" ".join(args), depth, script)
            while j < len(args) and args[j].startswith("-") and base in SHELLS:
                if "c" in args[j] and not args[j].startswith("--"):
                    return self.shell(args[j + 1], depth, script) if j + 1 < len(args) else []
                j += 2 if args[j] in ("-o", "-O", "--rcfile", "--init-file") else 1
            if j >= len(args):
                return self.shell(c.heredoc, depth, script) if c.heredoc else []
            p = self._resolve(args[j], self.cwd, e)
            return self._script(p, args[j + 1:], depth, e, local)

        if PYTHONS.match(base) or (base == "uv" and args[:1] == ["run"]):
            j = 1 if base == "uv" else 0
            while j < len(args) and args[j].startswith("-"):
                if args[j] == "-c":
                    return self.code(args[j + 1], script or "-c", depth) if j + 1 < len(args) else []
                if args[j] == "-m" or args[j] == "-":
                    break
                j += 2 if args[j] in ("-W", "-X", "--with", "--python", "-p") else 1
            if j < len(args) and args[j] == "-" or (j >= len(args) and c.heredoc):
                return self._mark(self.code(c.heredoc or "", script or "stdin", depth), local)
            if j >= len(args) or args[j] == "-m":
                return []
            p = self._resolve(args[j], self.cwd, e)
            return self._script(p, args[j + 1:], depth, e, local)

        if base in ("tmux", "watch", "script", "su"):
            found = []
            for k, a in enumerate(args):
                if "claude" in a and " " in a:
                    found += self.shell(a, depth, script)
                elif _is_claude(a, e) and not a.startswith("$"):
                    found += self._words(args[k:], c, depth, script, e)
                    break
            return found

        # a script run by its path
        if "/" in w or w.endswith((".sh", ".py")):
            p = self._resolve(w, self.cwd, e)
            if p:
                return self._script(p, args, depth, e, local)
        return []

    def _mark(self, found, local):
        ok = local.get("CLAUDE_GUARD_FLAGS", self.env.get("CLAUDE_GUARD_FLAGS", ""))
        for L in found:
            if L.guardflags and L.missing:
                L.missing = [f for f in L.missing if f not in ok.split() and not any(x.startswith(f + "=") for x in ok.split())]
        return found

    def _script(self, p, args, depth, e, local):
        if not p:
            return []
        return self._mark(self.script(p, args, depth + 1, e), local)

    def _words(self, words, c, depth, script, env):
        """analyze a word list as a command of its own (the tail of xargs / parallel / find -exec)"""
        if not words:
            return []
        sub = Cmd()
        sub.words = [Tok("w", w) for w in words]
        sub.heredoc = c.heredoc
        saved = self.env
        self.env = dict(env)
        try:
            return self.cmd(sub, depth, script)
        finally:
            self.env = saved


class Result:
    def __init__(self, launches, scan):
        self.launches = launches
        self.cmds = scan.cmds
        self.script_texts = scan.script_texts
        self.cwd = scan.cwd
        # background launches all run together; foreground ones run one pipeline at a time
        bg = sum(L.conc for L in launches if L.bg)
        pipes = {}
        for L in launches:
            if not L.bg:
                pipes[L.pipe] = pipes.get(L.pipe, 0) + L.conc
        self.conc = bg + (max(pipes.values()) if pipes else 0)
        self.total = sum(L.total() for L in launches)
        self.missing = sorted({f for L in launches for f in L.missing}, key=NEED.index)
        self.in_script = next((L.script for L in launches if L.missing and L.script), None)


def analyze(command, cwd, env=None):
    s = Scan(cwd, env)
    return Result(s.shell(command or ""), s)
