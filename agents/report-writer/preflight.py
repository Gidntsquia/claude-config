#!/usr/bin/env python3
"""preflight.py: can a report be built here? The report-writer runs this before it reads any data.

    python3 -I preflight.py          silent, exit 0: build.py, check.py, node and a playwright with its browser are there
                                     else one line `blocked: <what to run>` on stdout, exit 1

Playwright is looked up by cards.mjs itself (`node cards.mjs --find`), so this never disagrees with the build.
$REPORT_WRITER_HOME overrides the folder holding build.py and cards.mjs (default: this file's folder); check.py is
../evals/report-writer/check.py beside it.
"""
import os
import shutil
import subprocess
import sys

HERE = os.environ.get("REPORT_WRITER_HOME") or os.path.dirname(os.path.abspath(__file__))


def blocked(what):
    print("blocked: " + " ".join(what.split()))
    sys.exit(1)


def main():
    need = [os.path.join(HERE, "build.py"), os.path.join(HERE, "cards.mjs"),
            os.path.join(HERE, "..", "evals", "report-writer", "check.py")]
    missing = [os.path.normpath(p) for p in need if not os.path.isfile(p)]
    if missing:
        blocked(f"rerun claude-config's install.sh; missing {', '.join(missing)}")
    if not shutil.which("node"):
        blocked("install Node.js so `node` is on PATH (the cards are drawn by cards.mjs)")
    try:
        r = subprocess.run(["node", os.path.join(HERE, "cards.mjs"), "--find"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as ex:
        blocked(f"`node {os.path.join(HERE, 'cards.mjs')} --find` did not run ({ex.__class__.__name__}); fix node and rerun")
    if r.returncode != 0:
        err = (r.stderr or r.stdout).strip().splitlines()
        last = err[-1] if err else ""
        fix = last.split("install it:", 1)[1].strip() if "install it:" in last else "npm i -g playwright && npx playwright install chromium"
        blocked(fix)


if __name__ == "__main__":
    main()
