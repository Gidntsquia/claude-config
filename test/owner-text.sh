#!/bin/bash
# No installed file carries the author's own project or tells Claude to push the config repo.
# Fails when CLAUDE.md, settings.json, agents/, skills/, hooks/ or bin/ hold "descent-of-essence", "Wordbound" or
# "push changes there"; also when settings.json is not valid JSON. Prints each hit as file:line. Exit 0 = none.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$R" || exit 1
fails=0
hits=$(grep -rn -e 'push changes there' -e 'descent-of-essence' -e 'Wordbound' CLAUDE.md settings.json agents skills hooks bin 2>/dev/null)
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | cut -c1-160 | sed 's/^/FAIL /'; fails=$((fails + $(printf '%s\n' "$hits" | grep -c .)))
else echo "PASS no installed file holds descent-of-essence, Wordbound or 'push changes there'"; fi
if python3 -m json.tool settings.json >/dev/null 2>&1; then echo "PASS settings.json is valid JSON"; else echo "FAIL settings.json is not valid JSON"; fails=$((fails + 1)); fi
l=$(sed -n '8p' CLAUDE.md)
case "$l" in *"(the clone chosen at install).") echo "PASS CLAUDE.md line 8 ends at (the clone chosen at install).";; *) echo "FAIL CLAUDE.md line 8: $l"; fails=$((fails + 1));; esac
echo "$([ $fails -eq 0 ] && echo "all checks passed" || echo "$fails check(s) failed")"
exit $((fails > 0))
