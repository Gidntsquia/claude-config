#!/bin/bash
# Source this from a WSL script to get the Windows user's folders without naming the user:
#   WIN_HOME (%USERPROFILE% as a WSL path), WIN_HOME_W (%USERPROFILE% as a Windows path), WIN_LOCALAPPDATA and
#   WIN_PROGRAMFILES (WSL paths). Asked from cmd.exe once, then cached in ~/.cache/claude-config/winenv.
# Run it directly to print the values.
_wc="${XDG_CACHE_HOME:-$HOME/.cache}/claude-config/winenv"
if [ ! -s "$_wc" ]; then
  _we() { cmd.exe /C "echo %$1%" 2>/dev/null | tr -d '\r'; }
  _wh="$(_we USERPROFILE)"; _wl="$(_we LOCALAPPDATA)"; _wp="$(_we ProgramFiles)"
  if [ -n "$_wh" ] && [ "${_wh#%}" = "$_wh" ]; then
    mkdir -p "$(dirname "$_wc")"
    printf 'WIN_HOME_W=%q\nWIN_HOME=%q\nWIN_LOCALAPPDATA=%q\nWIN_PROGRAMFILES=%q\n' \
      "$_wh" "$(wslpath "$_wh")" "$(wslpath "$_wl")" "$(wslpath "$_wp")" > "$_wc"
  fi
  unset -f _we; unset _wh _wl _wp
fi
[ -s "$_wc" ] && . "$_wc"
unset _wc
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ -n "${WIN_HOME:-}" ] || { echo "winenv.sh: cmd.exe gave no %USERPROFILE% (not WSL?)" >&2; exit 1; }
  printf 'WIN_HOME=%s\nWIN_HOME_W=%s\nWIN_LOCALAPPDATA=%s\nWIN_PROGRAMFILES=%s\n' "$WIN_HOME" "$WIN_HOME_W" "$WIN_LOCALAPPDATA" "$WIN_PROGRAMFILES"
fi
