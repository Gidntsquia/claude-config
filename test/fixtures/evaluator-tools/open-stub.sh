#!/bin/bash
# Stands in for macOS `open`: records the call; fails with $OPEN_FAIL when set.
echo "$*" >> "$OPEN_LOG"
[ -n "${OPEN_FAIL:-}" ] && { echo "$OPEN_FAIL" >&2; exit 1; }
exit 0
