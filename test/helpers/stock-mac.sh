#!/bin/bash
# usage: test/helpers/stock-mac.sh <script> [args...]
# Runs the script the way a Mac runs it before anything is added to it: under /bin/bash (3.2) with an empty
# environment and PATH=/usr/bin:/bin:/usr/sbin:/sbin. Two programs the tests cannot do without, tmux and claude,
# are reached through one extra folder that holds links to those two and nothing else, so Homebrew's bash, GNU
# date, sed and stat stay out of reach. ~/.local/bin is on PATH too: install.sh adds it in the shell rc file, so it
# is what a new terminal on that Mac has. HOME, USER, TMPDIR and every SCN_* variable pass through.
# The install workflow's macOS job runs install.sh, --check and every test script through this file. Homebrew's
# tools on a runner's own PATH hid 140 failures that a real Mac then showed.
set -u
[ $# -ge 1 ] || { echo "usage: test/helpers/stock-mac.sh <script> [args...]" >&2; exit 2; }
/bin/bash --version | grep -q 'version 3\.2' || { echo "stock-mac.sh: /bin/bash is not 3.2: $(/bin/bash --version | head -1)" >&2; exit 2; }
B="$(mktemp -d "${TMPDIR:-/tmp}/stock-bin.XXXX")" || exit 2
trap 'rm -rf "$B"' EXIT
for t in tmux claude; do
  p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$B/$t"
done
keep=()
for v in $(env | sed -n 's/^\(SCN_[A-Z0-9_]*\)=.*/\1/p'); do keep[${#keep[@]}]="$v=$(eval "printf '%s' \"\${$v}\"")"; done
env -i HOME="$HOME" USER="${USER:-$(id -un)}" TMPDIR="${TMPDIR:-/tmp}" TERM=xterm-256color LANG=en_US.UTF-8 \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin:$B:$HOME/.local/bin" ${keep[@]+"${keep[@]}"} /bin/bash "$@"
