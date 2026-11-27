#!/bin/bash
# Stand-in win.sh for term-close.sh: logs its arguments and exits $STUB_WIN_EXIT.
echo "win.sh $*" >> "$STUB_LOG"
exit "${STUB_WIN_EXIT:-0}"
