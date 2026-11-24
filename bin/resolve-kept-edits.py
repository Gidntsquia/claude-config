#!/usr/bin/env python3
"""Resolve the conflicts an update leaves, keeping your lines and adding the release's (UPDATING.md steps 6 and 7).

Usage: resolve-kept-edits.py [clone] [--mine theirs|ours]

Run it when `git stash pop` (step 7) or `git merge <tag>` (step 6) stops on a conflict. For every conflicted file:
  - a .json file is merged value by value from the three versions git holds (the old release, yours, the new
    release): a value you changed keeps your value, a list keeps the release's entries and adds the ones you
    added, everything else is the release's. The result must parse as JSON.
  - any other text file keeps both sides' lines where they clash (yours first), with no conflict markers.
After a stash pop (--mine theirs, the default) every edit is left uncommitted and unstaged, as a clean pop
would leave it; drop the stash afterwards with `git stash drop`. After a merge (--mine ours) each resolved file is
staged; finish with `git commit --no-edit`.
Exits 0 when every conflicted file was resolved. Exits 1 and names each file it left alone (one side deleted it,
it is binary, or its JSON does not parse): ask the user about those. It never discards a file. Standard library only.
"""
import json
import os
import subprocess
import sys
import tempfile


def git(repo, *args, check=True):
    p = subprocess.run(["git", "-C", repo] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and p.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args), p.stderr.decode("utf-8", "replace").strip()))
    return p


def stage(repo, n, path):
    """The file's bytes at index stage n (1 old release, 2 ours, 3 theirs), or None when that side has no file."""
    p = git(repo, "show", ":%d:%s" % (n, path), check=False)
    return p.stdout if p.returncode == 0 else None


def merge3(base, mine, rel):
    """mine's changes since base, applied on top of rel."""
    if isinstance(mine, dict) and isinstance(rel, dict):
        b = base if isinstance(base, dict) else {}
        out = {}
        for k, v in rel.items():
            if k in mine:
                out[k] = merge3(b.get(k), mine[k], v)
            elif k in b and b[k] == v:
                continue                      # I removed a key the release did not change: stays removed
            else:
                out[k] = v
        for k, v in mine.items():
            if k not in rel and (k not in b or b[k] != v):
                out[k] = v                    # my own key, or one the release dropped after I changed it
        return out
    if isinstance(mine, list) and isinstance(rel, list):
        b = base if isinstance(base, list) else []
        removed = [x for x in b if x not in mine]
        out = [x for x in rel if x not in removed]
        return out + [x for x in mine if x not in b and x not in out]
    return rel if mine == base else mine


def resolve_json(base, mine, rel):
    docs = [json.loads(x.decode("utf-8-sig")) for x in (base, mine, rel)]
    rel_text = rel.decode("utf-8-sig")
    ascii_only = "\\u" in rel_text or all(ord(c) < 128 for c in rel_text)
    return (json.dumps(merge3(*docs), indent=2, ensure_ascii=ascii_only) + "\n").encode("utf-8")


def resolve_text(base, mine, rel):
    for x in (base, mine, rel):
        if b"\0" in x:
            raise ValueError("binary file")
    d = tempfile.mkdtemp(prefix="cc-resolve.")
    try:
        names = []
        for name, data in (("mine", mine), ("base", base), ("release", rel)):
            names.append(os.path.join(d, name))
            with open(names[-1], "wb") as f:
                f.write(data)
        p = subprocess.run(["git", "merge-file", "-p", "--union"] + names, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if p.returncode < 0 or p.returncode > 127:
            raise ValueError("git merge-file: " + p.stderr.decode("utf-8", "replace").strip())
        return p.stdout
    finally:
        for n in os.listdir(d):
            os.remove(os.path.join(d, n))
        os.rmdir(d)


def main(argv):
    mine_side, args = "theirs", []
    it = iter(argv)
    for a in it:
        if a == "--mine":
            mine_side = next(it, "")
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            args.append(a)
    if mine_side not in ("theirs", "ours") or len(args) > 1:
        sys.exit(__doc__)
    repo = args[0] if args else "."
    top = git(repo, "rev-parse", "--show-toplevel").stdout.decode().strip()
    paths = [p for p in git(top, "diff", "--name-only", "--diff-filter=U", "-z").stdout.decode().split("\0") if p]
    if not paths:
        print("resolve-kept-edits: no conflicted file in %s" % top)
        return 0
    left = []
    for path in paths:
        base, ours, theirs = (stage(top, n, path) for n in (1, 2, 3))
        mine, rel = (theirs, ours) if mine_side == "theirs" else (ours, theirs)
        if mine is None or rel is None:
            left.append((path, "one side deleted it"))
            continue
        try:
            if path.lower().endswith(".json"):
                out = resolve_json(base if base is not None else b"{}", mine, rel)
                how = "your values kept, the release's keys and entries added"
            else:
                out = resolve_text(base if base is not None else b"", mine, rel)
                how = "both sides' lines kept"
        except (ValueError, RuntimeError) as e:
            left.append((path, str(e)))
            continue
        with open(os.path.join(top, path), "wb") as f:
            f.write(out)
        git(top, "add", "--", path)
        if mine_side == "theirs":
            git(top, "reset", "-q", "--", path)
        print("resolved %s (%s)" % (path, how))
    if mine_side == "theirs" and not left:
        git(top, "reset", "-q")               # a clean pop leaves every edit unstaged; so does this
    for path, why in left:
        print("LEFT %s: %s; ask the user about this file" % (path, why))
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
