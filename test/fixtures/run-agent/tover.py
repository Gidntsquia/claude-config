# argv: <run-agent scripts dir> <epoch> <at_text> <derived text or ""> <extra json or ""> <base overrides json>
# Prints the overrides pcheck.py needs for a "run later" answer: at, at_text, at_shown, run, the fake API's reset.
import json, shlex, sys
sys.path.insert(0, sys.argv[1])
from parse import fmt_et, fmt_in
at, text, derive, extra = int(sys.argv[2]), sys.argv[3], sys.argv[4], json.loads(sys.argv[5] or "{}")
shown = "%s (%s, %s)" % (fmt_et(at), derive or text, fmt_in(at))
run = "S worker . --at %d --at-text %s" % (at, shlex.quote(text))
if derive:
    run += " --at-shown '%s'" % shown
tail = extra.pop("_run", "")
if tail:
    run += " " + tail
over = {"at": at, "at_text": text, "at_shown": shown, "run": run}
over.update(json.loads(sys.argv[6]))
over.update(extra)
print(json.dumps(over))
