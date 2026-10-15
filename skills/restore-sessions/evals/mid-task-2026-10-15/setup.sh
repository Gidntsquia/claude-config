#!/usr/bin/env bash
# A session cut right after a tool_result (as if the stop hit at 01:20:00 ET while a tool had just returned),
# for the mid-task column. Run find-sessions.sh '2026-10-15 01:20:00' on this dir: the line must end "yes".
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
touch -d '2026-10-15T01:19:59-04:00' ./-home-jaxon-files-deadlock-street-brawl-helper/cbf1bb64-ae77-47ca-866b-59585cff517e.jsonl
echo "fixture mtimes set"
