#!/usr/bin/env python3
"""apply_agents.py <agents dir> [--check]: plan R13 on the five agent files (evaluator, planner, planner-fix10,
planner-fix32, worker): the `tools:` line gains `mcp__run-agent__*`; each "the lines `…run-agent.sh --next <agent>
"<prompt>"` prints" becomes a call of the `mcp__run-agent__next` tool (the standalone Bash call stays named as the fallback for when the tool is not listed yet);
worker.md's schedule line becomes the `mcp__run-agent__schedule` tool. Nothing else in the files changes; a second run
changes nothing. --check prints what would change and writes nothing."""
import os, re, sys

FILES = ["evaluator.md", "planner.md", "planner-fix10.md", "planner-fix32.md", "worker.md"]
S = "~/.claude/skills/run-agent/scripts/run-agent.sh"
NEXT = re.compile(r'`' + re.escape(S) + r' --next (\w+) "([^"`]*?)"`', re.S)
SCHED_OLD = ('run `' + S + ' worker "<this session\'s prompt>"\n--at <that epoch + 5 min> -- --model <model> --effort <effort>`')
SCHED_NEW = ('call the `mcp__run-agent__schedule` tool (agent `worker`, prompt = this session\'s prompt, at = `in <those minutes + 5> min`, model and effort; when the tool is not listed yet, the Bash fallback, run as a standalone command: `'
             + S + ' worker "<this session\'s prompt>"\n--at <that epoch + 5 min> -- --model <model> --effort <effort>`)')


def next_call(m):
    agent, prompt = m.group(1), " ".join(m.group(2).split())
    return (f'the `mcp__run-agent__next` tool (agent `{agent}`, prompt `{prompt}`; when the tool is not listed yet, '
            f'the Bash fallback, run as a standalone command: `{S} --next {agent} "{m.group(2)}"`)')


def convert(text, name):
    out = []
    for line in text.split("\n"):
        if line.startswith("tools:") and "mcp__run-agent__*" not in line:
            line = line.rstrip() + ", mcp__run-agent__*"
        out.append(line)
    text = "\n".join(out)
    if "mcp__run-agent__next" not in text:
        text = NEXT.sub(next_call, text)
        text = text.replace(" prints, as printed", " returns, as returned")
    if name == "worker.md" and "mcp__run-agent__schedule" not in text:
        assert SCHED_OLD in text, "worker.md: schedule line not found"
        text = text.replace(SCHED_OLD, SCHED_NEW)
        text = text.replace("the run-agent.sh line you ran copied in full with its `--at`", "the schedule call you made copied in full with its `at`")
        text = text.replace("exactly as run-agent.sh printed it", "exactly as the tool returned it")
    return text


def main():
    d = sys.argv[1]; check = "--check" in sys.argv
    for name in FILES:
        p = os.path.join(d, name)
        old = open(p, encoding="utf-8").read(); new = convert(old, name)
        a, b = old.split("\n"), new.split("\n")
        assert len(a) == len(b), name
        changed = [i + 1 for i, (x, y) in enumerate(zip(a, b)) if x != y]
        print(f"{name}: lines changed {changed or 'none'}")
        if new != old and not check:
            open(p, "w", encoding="utf-8").write(new)


if __name__ == "__main__":
    main()
