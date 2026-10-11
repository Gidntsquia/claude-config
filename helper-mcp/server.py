#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.12"
# dependencies = ["mcp>=1.2,<2"]
# ///
"""Read-only MCP server (stdio) over the local claude-config wiki clone and agent files.

Declared inline under `mcpServers:` in agents/helper.md, so it loads for the helper agent only.
Tools: wiki_list, wiki_read, wiki_search, agent_read, workflow_status.
Run `helper-mcp/stamp-wiki` after a wiki edit to refresh the `Last synced` stamp in Workflow.md.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

ROOT = Path(__file__).resolve().parent.parent  # claude-config/
WIKI = ROOT / "wiki"
AGENTS = ROOT / "agents"
AGENT_FILES = {"planner": "planner.md", "worker": "worker.md", "evaluator": "evaluator.md", "USAGE": "USAGE.txt"}
STAMP_RE = re.compile(r"^<!--\s*Last synced:\s*(?P<date>\S+)\s*\|\s*(?P<hashes>.*?)\s*-->\s*$", re.M)

mcp = FastMCP("helper-wiki", instructions="Read-only access to the claude-config wiki pages and the planner/worker/evaluator agent files.")


def _pages() -> list[Path]:
    return sorted(p for p in WIKI.glob("*.md") if p.is_file())


def _page(name: str) -> Path:
    name = name.strip()
    for cand in (name, f"{name}.md", name.replace(" ", "-"), f"{name.replace(' ', '-')}.md"):
        p = WIKI / cand
        if p.is_file() and p.suffix == ".md":
            return p
    raise FileNotFoundError(f"No wiki page '{name}'. Pages: {', '.join(p.stem for p in _pages())}")


def _hash(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:12]


def _commit_date(p: Path) -> str:
    try:
        out = subprocess.run(["git", "-C", str(p.parent), "log", "-1", "--format=%cs", "--", p.name],
                             capture_output=True, text=True, timeout=10).stdout.strip()
        return out or "uncommitted"
    except Exception:
        return "unknown"


def agent_hashes() -> dict[str, dict]:
    return {n: {"file": f"agents/{f}", "hash": _hash(AGENTS / f), "last_commit": _commit_date(AGENTS / f),
                "uncommitted_changes": _dirty(AGENTS / f)} for n, f in AGENT_FILES.items()}


def _dirty(p: Path) -> bool:
    try:
        out = subprocess.run(["git", "-C", str(p.parent), "status", "--porcelain", "--", p.name],
                             capture_output=True, text=True, timeout=10).stdout.strip()
        return bool(out)
    except Exception:
        return False


def read_stamp() -> dict | None:
    wf = WIKI / "Workflow.md"
    if not wf.is_file():
        return None
    m = STAMP_RE.search(wf.read_text())
    if not m:
        return None
    hashes = {}
    for part in m.group("hashes").split(","):
        if "=" in part:
            k, v = part.strip().split("=", 1)
            hashes[k.strip()] = v.strip()
    return {"date": m.group("date"), "hashes": hashes}


def status() -> dict:
    agents = agent_hashes()
    stamp = read_stamp()
    differing = []
    if stamp is None:
        differing = list(agents)
    else:
        for n, info in agents.items():
            if stamp["hashes"].get(n) != info["hash"]:
                differing.append(n)
    return {
        "stale": bool(differing),
        "wiki_stamp": stamp,
        "agents": agents,
        "differing": differing,
        "summary": ("Wiki is in step with the agent files." if not differing else
                    "Guide may be behind the agents: " + ", ".join(
                        f"{n} changed {agents[n]['last_commit']}" + (" (uncommitted edits)" if agents[n]['uncommitted_changes'] else "")
                        for n in differing) + (f"; guide stamped {stamp['date']}" if stamp else "; Workflow.md has no stamp")),
    }


@mcp.tool()
def wiki_list() -> str:
    """List the wiki page titles (files in claude-config/wiki/)."""
    return "\n".join(p.stem for p in _pages()) or "(no pages)"


@mcp.tool()
def wiki_read(page: str) -> str:
    """Read one wiki page in full by title, e.g. 'Getting-Started' or 'Cheat-Sheet'."""
    p = _page(page)
    return f"# file: wiki/{p.name}\n" + p.read_text()


@mcp.tool()
def wiki_search(query: str) -> str:
    """Case-insensitive search across all wiki pages. Returns matching lines as 'Page:line: text'."""
    q = query.strip().lower()
    hits = []
    for p in _pages():
        for i, line in enumerate(p.read_text().splitlines(), 1):
            if q in line.lower():
                hits.append(f"{p.stem}:{i}: {line.strip()}")
    return "\n".join(hits[:200]) if hits else f"No lines match '{query}' in the wiki."


@mcp.tool()
def agent_read(name: str) -> str:
    """Read an agent file by name: planner, worker, evaluator, or USAGE (agents/USAGE.txt)."""
    key = name.strip()
    key = "USAGE" if key.lower() in ("usage", "usage.txt") else key.lower()
    if key not in AGENT_FILES:
        raise ValueError(f"Unknown agent '{name}'. Choose from: {', '.join(AGENT_FILES)}")
    p = AGENTS / AGENT_FILES[key]
    return f"# file: agents/{p.name}\n" + p.read_text()


@mcp.tool()
def workflow_status() -> str:
    """Staleness check: per agent file its last commit date and content hash, the wiki's 'Last synced' stamp from Workflow.md, and stale: true when any hash differs."""
    return json.dumps(status(), indent=2)


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "--status":
        print(json.dumps(status(), indent=2))
    else:
        mcp.run()
