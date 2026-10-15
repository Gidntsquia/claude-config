#!/usr/bin/env bash
# usage: stop-time.sh [time]
# Prints three lines from `journalctl --list-boots` (times already local = ET):
#   stop<TAB><end time of boot -1>      e.g. "stop	Thu 2026-10-15 04:56:11 EDT"   (the WSL/Windows stop)
#   boot<TAB><start time of boot 0>     e.g. "boot	Thu 2026-10-15 06:13:05 EDT"   (this boot)
#   prev<TAB><start time of boot -1>    e.g. "prev	Wed 2026-10-14 23:40:46 EDT"   (the boot that was stopped)
# Exit 1 with "no stop time: <reason>" when journalctl is missing or boot -1 has no end time.
#   stop-time.sh "<time>"  instead checks a time the user gave (anything `date -d` reads, local = ET) and prints
#   only `stop<TAB><it in the same format>`; exit 1 "no stop time: cannot read ..." if date cannot read it.
set -uo pipefail
if [ $# -ge 1 ] && [ -n "$1" ]; then
  e=$(date -d "$1" +%s 2>/dev/null) || { echo "no stop time: cannot read '$1'"; exit 1; }
  printf 'stop\t%s\n' "$(date -d "@$e" '+%a %Y-%m-%d %H:%M:%S %Z')"; exit 0
fi
command -v journalctl >/dev/null || { echo "no stop time: journalctl not found"; exit 1; }
out=$(journalctl --list-boots --no-pager 2>&1) || { echo "no stop time: journalctl --list-boots failed: $out"; exit 1; }
# Columns: IDX BOOT-ID FIRST-ENTRY(4 fields: Day Date Time TZ) LAST-ENTRY(4 fields). Header lines are skipped.
prev=$(awk '$1 == "-1" && NF >= 10 { print $7, $8, $9, $10 }' <<<"$out")
prevstart=$(awk '$1 == "-1" && NF >= 6 { print $3, $4, $5, $6 }' <<<"$out")
cur=$(awk '$1 == "0" && NF >= 6 { print $3, $4, $5, $6 }' <<<"$out")
[ -n "$prev" ] || { echo "no stop time: no previous boot (-1) with an end time in journalctl --list-boots"; exit 1; }
date -d "$prev" +%s >/dev/null 2>&1 || { echo "no stop time: cannot read '$prev'"; exit 1; }
printf 'stop\t%s\n' "$prev"
[ -n "$cur" ] && printf 'boot\t%s\n' "$cur"
[ -n "$prevstart" ] && printf 'prev\t%s\n' "$prevstart"
exit 0
