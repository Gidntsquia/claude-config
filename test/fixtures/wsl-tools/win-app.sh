#!/bin/bash
# Stand-in win-app.sh for term-open.sh: logs its arguments, then reports a hidden window or the failure in $STUB_APP_FAIL.
echo "win-app.sh $*" >> "$STUB_LOG"
echo "hide-log: stub event"
if [ -n "${STUB_APP_FAIL:-}" ]; then echo "not hidden: $STUB_APP_FAIL"; exit 1; fi
[ -z "${STUB_APP_SILENT:-}" ] || exit 0
echo "hidden: 4242 10 10 stub-title (create 5 12)"
