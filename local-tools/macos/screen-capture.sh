#!/bin/bash
# usage: screen-capture.sh [name]
# macOS: a picture of the whole display needs the Screen Recording permission, which these tools never ask for. Prints ONE
# line and exits 1. The proof of a show is its `shown:` line and the item's own picture: `evshow.sh path shown`.
echo "not captured: no whole-display picture on macOS (it needs Screen Recording); the item's picture is \`evshow.sh path shown\`"
exit 1
