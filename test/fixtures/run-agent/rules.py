# argv: repo root, case name. Replays commands against the Bash allow rules in settings.json: a compound command is
# split on && || ; | and newlines, and every part must start with an allowed prefix or be a read-only command.
import json, os, re, sys

repo, case = sys.argv[1], sys.argv[2]
rules = json.load(open(os.path.join(repo, "settings.json")))["permissions"]["allow"]
pre = []
for r in rules:
    m = re.fullmatch(r"Bash\((.*)\)", r)
    if m:
        pat = m.group(1).replace("~/files/claude-config", repo)
        # "<prog> *": the program then a space; "<dir>/*": any path under the folder (a plain prefix)
        pre.append((pat[:-2], True) if pat.endswith(" *") else (pat.rstrip("*"), False))
READ_ONLY = {"tail", "head", "cat", "grep", "ls", "wc", "echo", "sort", "cd", "pwd"}


def allowed(cmd):
    parts = [p.strip() for p in re.split(r"\s*(?:&&|\|\||;|\||\n)\s*", cmd) if p.strip()]
    bad = [p for p in parts if not (any(p == x or p.startswith(x + (" " if sp else "")) for x, sp in pre)
                                    or p.split()[0] in READ_ONLY)]
    return "ok" if not bad else "blocked: " + " / ".join(bad)


RA = "~/.claude/skills/run-agent/scripts/run-agent.sh"
CASES = {
    "pogo1": [repo + '/skills/run-agent/scripts/run-agent.sh worker "Report only: out/ladder-opt-s28 compute race per'
              ' plans/PLAN.md R10–R12" --at 1793410200 2>&1 | tail -3'],
    "pogo2": ['cd /tmp/x/pogo; %s worker "Report only" --at 1793410200 -- --model sonnet --effort low 2>&1 | tail -5;'
              ' %s --jobs 2>&1 | tail -5' % (RA, RA)],
    "slay": ['cd /tmp/x/slay-the-spire-advisor; %s --next evaluator "."; export PATH=$HOME/.dotnet:$PATH;'
             ' dotnet test src/Advisor.Tests 2>&1 | tail -3' % RA],
    "other": ["bash ~/.claude/skills/run-agent/scripts/test.sh", "bash %s/skills/run-agent/scripts/test.sh" % repo,
              "run-agent jobs", '~/.local/bin/run-agent worker "." dry'],
    "envprefix": ["env X=1 %s --jobs" % RA],
}
WANT = ['Bash(~/.claude/skills/run-agent/scripts/run-agent.sh *)',
        'Bash(~/files/claude-config/skills/run-agent/scripts/run-agent.sh *)',
        'Bash(bash ~/.claude/skills/run-agent/scripts/*)', 'Bash(bash ~/files/claude-config/skills/run-agent/scripts/*)',
        'Bash(~/.local/bin/run-agent *)', 'Bash(run-agent *)']
if case == "six":
    missing = [w for w in WANT if w not in rules]
    wild = [r for r in rules if r.startswith("Bash(*")]
    print("ok" if not missing and not wild else "missing %s, leading-wildcard %s" % (missing, wild))
else:
    for c in CASES[case]:
        print(allowed(c))
