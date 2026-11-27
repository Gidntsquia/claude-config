#!/usr/bin/env bats
# local-tools/ as shipped: which file lives in which folder, that every script parses, and that the macOS tools do
# not reach for commands a Mac lacks.

load ../helpers/common
load ../helpers/evaluator-tools

setup() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) skip "the evaluator's tools are for WSL, Linux and macOS" ;; esac
}

# code lines (not comment lines) of the named files that match the extended regex
code_lines() {
  local re="$1" f; shift
  for f in "$@"; do [ -f "$f" ] || { echo "missing: $f"; return 0; }; done
  grep -nE "$re" /dev/null "$@" | grep -v '^[^:]*:[0-9]*:#' || true
}

# bats test_tags=feature:evaluator-tools
@test "the shared evaluator tools are in local-tools/common" {
  for f in evshow.sh evshow_watch.py evshow_noflash.py evsession.sh file-page.sh md2html.py phone-shot.sh phone-shot.mjs; do
    assert_file_exist "$LT/common/$f"
  done
}

# bats test_tags=feature:evaluator-tools
@test "the Mac-only page makers are in local-tools/macos" {
  assert_file_exist "$LT/macos/phone-bidi.py"
  assert_file_exist "$LT/macos/termpage.py"
}

# bats test_tags=feature:evaluator-tools
@test "WSL and macOS each have the five window commands, executable" {
  for f in win.sh win-app.sh term-open.sh term-close.sh screen-capture.sh; do
    for os in wsl macos; do
      [ -x "$LT/$os/$f" ] || { echo "$os/$f missing or not executable"; return 1; }
    done
  done
}

# bats test_tags=feature:evaluator-tools
@test "no PowerShell file sits in the common or macOS tool folders" {
  assert_file_exist "$LT/common/evshow.sh"
  assert_file_exist "$LT/macos/win.sh"
  run find "$LT/common" "$LT/macos" -name '*.ps1'
  assert_success
  assert_output ""
}

# bats test_tags=feature:evaluator-tools
@test "no tool name exists both in common and in an OS folder, so links cannot collide" {
  n=0
  for f in "$LT"/common/*; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    for os in macos wsl; do
      if [ -e "$LT/$os/${f##*/}" ]; then echo "${f##*/} is in common and in $os"; return 1; fi
    done
  done
  [ "$n" -ge 8 ]
}

# bats test_tags=feature:evaluator-tools
@test "the old top-level wsl/local-tools folder is gone" {
  [ -d "$LT/wsl" ]
  [ ! -e "$REPO/wsl/local-tools" ]
}

# bats test_tags=feature:evaluator-tools
@test "every evaluator shell script parses" {
  n=0; bad=""
  for f in "$LT"/common/*.sh "$LT"/macos/*.sh "$LT"/wsl/*.sh; do
    n=$((n + 1))
    bash -n "$f" || bad="$bad $f"
  done
  [ "$n" -ge 13 ] || { echo "only $n scripts found"; return 1; }
  [ -z "$bad" ] || { echo "do not parse:$bad"; return 1; }
}

# bats test_tags=feature:evaluator-tools
@test "the Mac and shared scripts parse under bash 3.2" {
  case "$(/bin/bash --version 2>/dev/null)" in
    *"version 3."*) ;;
    *) skip "/bin/bash here is not bash 3.x";;
  esac
  bad=""
  for f in "$LT"/common/*.sh "$LT"/macos/*.sh; do /bin/bash -n "$f" || bad="$bad $f"; done
  [ -z "$bad" ] || { echo "do not parse:$bad"; return 1; }
}

# bats test_tags=feature:evaluator-tools
@test "the macOS scripts call no command a stock Mac lacks" {
  x=$(code_lines '(^|[^a-zA-Z_.-])(flock|setsid|timeout|node|wslpath|swiftc|screencapture|powershell\.exe)( |$)' "$LT"/macos/*.sh | grep -v 'no `timeout`' || true)
  [ -z "$x" ] || { echo "$x"; return 1; }
}

# bats test_tags=feature:evaluator-tools
@test "the macOS tools open no iTerm tab, drive no other browser and need no screen permission" {
  x=$(code_lines 'set bounds|osascript|iTerm|split-window|split vertically|create tab|EVSHOW_MAC_MODE|Safari|Chrome|chromium|screencapture' "$LT"/macos/*.sh "$LT"/macos/*.py)
  [ -z "$x" ] || { echo "$x"; return 1; }
}

# bats test_tags=feature:evaluator-tools
@test "evshow.sh has no rotation between ways of showing" {
  x=$(code_lines 'modeidx|EVSHOW_MAC_MODE|iTerm' "$LT/common/evshow.sh")
  [ -z "$x" ] || { echo "$x"; return 1; }
}

# bats test_tags=feature:evaluator-tools
@test "the evaluator asks no question about which way of showing to use" {
  assert_file_exist "$REPO/agents/evaluator.md"
  run grep -niE 'Which way of showing|EVSHOW_MAC_MODE|mode=tmux|mode=iterm|mode=tab' "$REPO/agents/evaluator.md"
  assert_failure 1
}

# bats test_tags=feature:evaluator-tools
@test "every evaluator Python tool parses" {
  run python3 -c 'import ast,sys
for p in sys.argv[1:]: ast.parse(open(p, encoding="utf-8").read(), p)
print(len(sys.argv) - 1)' "$LT"/common/*.py "$LT"/macos/*.py
  assert_success
  [ "${output%$'\r'}" -ge 5 ]
}

# bats test_tags=feature:evaluator-tools
@test "the Mac phone picture tool needs no Node, Playwright or Chromium" {
  assert_file_exist "$LT/macos/phone-bidi.py"
  run grep -niE 'node|playwright|chrom' "$LT/macos/phone-bidi.py"
  assert_failure 1
}
