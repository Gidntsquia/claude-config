#!/bin/bash
# usage: screen-capture.sh [name]
# macOS: a picture of the display needs the Screen Recording permission, which these tools never ask for. Prints ONE line
# and exits 1. The proof of a show on a Mac is its `shown: ... mode=firefox` line and what the user says they saw.
echo "not captured: no picture on macOS (it needs Screen Recording); the proof is the shown: line and the user's answer"
exit 1
