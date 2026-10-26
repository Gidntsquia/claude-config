#!/usr/bin/env python3
"""Merge this repo's settings.json into a user's settings.json without changing anything they set.

Usage: merge-settings.py <repo settings.json> <user settings.json> <out> [--drop-key KEY ...] [--force-key KEY ...]

Every key in the user's file keeps the user's value. Keys only the repo has are added. Objects are merged
key by key, lists of strings (permissions.allow/deny/ask, ...) are unioned with the user's entries first.
--drop-key leaves a top-level repo key out (statusLine when the user keeps their own status line).
--force-key makes the repo's value win for a top-level key (statusLine when the user chose the repo's status line).
A missing or empty user file counts as {}. Standard library only.
"""
import json
import sys


def merge(user, repo):
    if isinstance(user, dict) and isinstance(repo, dict):
        out = dict(user)
        for k, v in repo.items():
            out[k] = merge(user[k], v) if k in user else v
        return out
    if isinstance(user, list) and isinstance(repo, list):
        return user + [x for x in repo if x not in user]
    return user


def load(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            text = f.read()
    except FileNotFoundError:
        return {}
    return json.loads(text) if text.strip() else {}


def main(argv):
    args, drop, force = [], [], []
    it = iter(argv)
    for a in it:
        if a == "--drop-key":
            drop.append(next(it))
        elif a == "--force-key":
            force.append(next(it))
        else:
            args.append(a)
    if len(args) != 3:
        sys.exit(__doc__)
    repo_path, user_path, out_path = args
    repo = load(repo_path)
    for k in drop:
        repo.pop(k, None)
    try:
        user = load(user_path)
    except json.JSONDecodeError as e:
        sys.exit(f"{user_path} is not valid JSON ({e}); fix it or rerun with --settings keep")
    if not isinstance(user, dict):
        sys.exit(f"{user_path} is not a JSON object; fix it or rerun with --settings keep")
    merged = merge(user, repo)
    for k in force:
        if k in repo:
            merged[k] = repo[k]
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, indent=2, ensure_ascii=False)
        f.write("\n")
    added = [k for k in repo if k not in user]
    print(f"settings merge: kept {len(user)} of your keys, added {len(added)}" + (f" ({', '.join(added)})" if added else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
