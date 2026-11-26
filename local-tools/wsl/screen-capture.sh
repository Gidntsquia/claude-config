#!/bin/bash
# usage: screen-capture.sh [name]  -> saves a DPI-aware capture of the whole Windows display
# and prints the WSL path of the PNG (read it with the Read tool).
# DPI awareness matters: without it PowerShell captures only the top-left part of a scaled screen.
grep -qi microsoft /proc/version 2>/dev/null || { echo "screen-capture.sh: WSL only (this is $(uname))" >&2; exit 1; }
name="${1:-eval_screen}"
. "$(dirname "$(readlink -f "$0")")/winenv.sh"
win="$WIN_HOME_W\\${name}.png"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$HOME/.claude/local-tools/screen-capture.ps1")" "$win" >/dev/null || exit 1
echo "$WIN_HOME/${name}.png"
