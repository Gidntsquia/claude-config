#!/bin/bash
# Stands in for win.sh under evshow.sh: records each call and answers start and next as win.sh does.
echo "$*" >> "$EVSHOW_STATE/calls"
case "$1" in
  start) echo "shown: 1001 $2 mode=firefox"; echo "shown-at $(TZ=America/New_York date +%T).000";;
  next)  echo "shown: 1002 $3 mode=firefox"; echo "shown-at $(TZ=America/New_York date +%T).000";;
esac
exit 0
