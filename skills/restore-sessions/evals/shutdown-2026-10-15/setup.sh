#!/usr/bin/env bash
# Sets the fixture transcripts' mtimes to what they were at the 2026-10-15 04:56:11 EDT stop
# (git checkout does not keep mtimes). Times carry an explicit -04:00 (EDT) offset.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# killed by the stop: last write a few seconds before 04:56:11 ET
touch -d '2026-10-15T04:56:01-04:00' ./-srv-demo-files-terminal-pet/f720125e-19b7-4ad5-8943-324c137ba71d.jsonl
touch -d '2026-10-15T04:56:02-04:00' ./-srv-demo-files-deadlock-street-brawl-helper/cbf1bb64-ae77-47ca-866b-59585cff517e.jsonl
touch -d '2026-10-15T04:56:03-04:00' ./-srv-demo-files-pogo-gbl-team-generator/c7a00432-9f38-4988-a9bf-f7e7fa463d9b.jsonl
# closed with /exit just before the stop: written in the window, but must not be listed
touch -d '2026-10-15T04:55:30-04:00' ./-srv-demo-files-deadlock-street-brawl-helper/5587f09e-bfe8-450c-be0e-40d089ec5b45.jsonl
# ended hours earlier: their original mtimes
touch -d '2026-10-15T01:00:46-04:00' ./-srv-demo-files-claude-config/4c2bf428-624d-4f45-a579-59db3f64b2a0.jsonl
touch -d '2026-10-15T00:57:53-04:00' ./-srv-demo-files-archery-simulator/bb8545fa-0f8c-453b-9c80-323aa73166ad.jsonl
echo "fixture mtimes set"
