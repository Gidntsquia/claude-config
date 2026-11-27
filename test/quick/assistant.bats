#!/usr/bin/env bats
# The assistant agent's guard hook (assistant/hooks/guard.py) and the server code it reads panes with.
# The `mcp` package is the stand-in in test/fixtures/mcp-stub; tmux is real, on a socket of this test's own.

load ../helpers/common

setup() {
  temp_home
  mkdir -p "$TEST_HOME/.claude/skills" "$TEST_HOME/bin"
  ln -s "$REPO/skills/run-agent" "$TEST_HOME/.claude/skills/run-agent"
  # no claude here: `claude agents --json` fails and the server reads the screen
  export ASSISTANT_CLAUDE_BIN="$TEST_HOME/bin/no-claude" ASSISTANT_FILES="$TEST_HOME/files"
  export PYTHONPATH="$REPO/test/fixtures/mcp-stub" PYTHONDONTWRITEBYTECODE=1
  unset TMUX TMUX_PANE ASSISTANT_SELF_PANE ASSISTANT_GUARD_LOG
  SOCK=""
}

teardown() {
  [ -z "$SOCK" ] || tmux -S "$SOCK" kill-server 2>/dev/null || true
  [ -z "$SOCK" ] || rm -rf "$(dirname "$SOCK")"
}

# hook <tool name> <tool input as JSON>: run the guard as Claude Code does
hook() {
  printf '{"tool_name":"%s","tool_input":%s}' "$1" "$2" > "$BATS_TEST_TMPDIR/in.json"
  run bash -c 'python3 "$1" < "$2"' _ "$REPO/assistant/hooks/guard.py" "$BATS_TEST_TMPDIR/in.json"
}
bash_hook() { hook Bash "{\"command\":\"$1\"}"; }

# a private tmux server with one idle shell pane; sets PANE
panes() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) skip "Windows Git Bash has no tmux" ;; esac
  # a socket path under the test's folder is too long for a Unix socket
  SOCK="$(mktemp -d /tmp/asst.XXXXXX)/s"
  without_bats_fds tmux -S "$SOCK" -f /dev/null new-session -d -s t -x 120 -y 40 'bash --norc --noprofile' >/dev/null 2>&1
  PANE="$(tmux -S "$SOCK" list-panes -F '#{pane_id}')"
  export TMUX="$SOCK,0,0"
}

# bats test_tags=feature:assistant
@test "assistant guard: tmux commands that only read are allowed" {
  for c in "tmux list-panes -a" "tmux -S /tmp/x capture-pane -p" "tmux display-message -p ok" "git status"; do
    bash_hook "$c"
    assert_success
    assert_output ""
  done
}

# bats test_tags=feature:assistant
@test "assistant guard: typing into a pane from the shell is blocked and names assistant_send" {
  bash_hook "tmux send-keys -t %1 hello Enter"
  assert_failure 2
  assert_output --partial "blocked: \`tmux send-keys\` is not run from the shell"
  assert_output --partial "assistant_send"
}

# bats test_tags=feature:assistant
@test "assistant guard: starting and closing panes from the shell are blocked, wrapped or chained too" {
  bash_hook "tmux split-window -h"
  assert_failure 2
  assert_output --partial "assistant_launch"
  bash_hook "ls; /opt/homebrew/bin/tmux kill-pane -t %2"
  assert_failure 2
  assert_output --partial "assistant_layout"
  bash_hook "bash -c 'tmux kill-server'"
  assert_failure 2
  bash_hook "tmux list-panes \\\; kill-server"
  assert_failure 2
  assert_output --partial "a chained tmux command"
}

# bats test_tags=feature:assistant
@test "assistant guard: background commands are blocked and point at assistant_schedule" {
  hook Bash '{"command":"echo hi","run_in_background":true}'
  assert_failure 2
  assert_output --partial "assistant_schedule"
}

# bats test_tags=feature:assistant
@test "assistant guard: a forced launch needs confirmed=True" {
  hook mcp__assistant__assistant_launch '{"agent":"worker","force":true}'
  assert_failure 2
  assert_output --partial "needs confirmed=True"
  hook mcp__assistant__assistant_launch '{"agent":"worker","force":true,"confirmed":true}'
  assert_success
  hook mcp__assistant__assistant_launch '{"agent":"worker"}'
  assert_success
}

# bats test_tags=feature:assistant
@test "assistant guard: other tools and unreadable input are let through" {
  hook Read '{"file_path":"/etc/hosts"}'
  assert_success
  run bash -c 'echo not-json | python3 "$1"' _ "$REPO/assistant/hooks/guard.py"
  assert_success
}

# bats test_tags=feature:assistant
@test "assistant guard: typing into the assistant's own pane needs self=True" {
  panes
  export ASSISTANT_SELF_PANE="$PANE"
  hook mcp__assistant__assistant_send "{\"pane_ids\":[\"$PANE\"],\"text\":\"hi\"}"
  assert_failure 2
  assert_output --partial "is my own pane"
  hook mcp__assistant__assistant_send "{\"pane_ids\":[\"$PANE\"],\"text\":\"hi\",\"self\":true}"
  assert_success
}

# bats test_tags=feature:assistant
@test "assistant guard: closing the assistant's own pane needs self=True" {
  panes
  export ASSISTANT_SELF_PANE="$PANE"
  hook mcp__assistant__assistant_layout "{\"action\":\"close\",\"target\":\"$PANE\"}"
  assert_failure 2
  assert_output --partial "is my own pane"
  hook mcp__assistant__assistant_layout "{\"action\":\"close\",\"target\":\"$PANE\",\"self\":true}"
  assert_success
}

# screen_pane <line>...: a second pane that shows these lines and stays open; sets P2 and waits for the last line
screen_pane() {
  printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/screen.txt"
  P2="$(tmux -S "$SOCK" split-window -d -P -F '#{pane_id}' -t "$PANE" "cat '$BATS_TEST_TMPDIR/screen.txt'; exec tail -f /dev/null")"
  wait_until 10 shows "$P2" "${!#}"
}
shows() { tmux -S "$SOCK" capture-pane -p -t "$1" | grep -qF -- "$2"; }
send_hook() { hook mcp__assistant__assistant_send "{\"pane_ids\":[\"$P2\"],$1}"; }
layout_hook() { hook mcp__assistant__assistant_layout "{\"action\":\"close\",\"target\":\"$1\"$2}"; }

# bats test_tags=feature:assistant
@test "assistant guard: a pet pane takes no text and is not closed by itself" {
  panes
  screen_pane "  a squid" "[f] feed   [p] pet"
  send_hook '"text":"hi"'
  assert_failure 2
  assert_output --partial "pets take no text"
  layout_hook "$P2" ''
  assert_failure 2
  assert_output --partial "close its window"
}

# bats test_tags=feature:assistant
@test "assistant guard: answering a judgement menu is blocked, quoting the question; plain text is not" {
  panes
  screen_pane "Claude Code v2.1.0" "Ready for me to move windows and start? (y/n)"
  send_hook '"answer":"y"'
  assert_failure 2
  assert_output --partial "is on a judgement call"
  assert_output --partial "Ready for me to move windows and start?"
  send_hook '"text":"hi"'
  assert_success
}

# bats test_tags=feature:assistant
@test "assistant guard: force on a running pane needs confirmed=True; on an idle shell it does not" {
  panes
  screen_pane "Claude Code v2.1.0" "  working (esc to interrupt)"
  layout_hook "$P2" ',"force":true'
  assert_failure 2
  assert_output --partial "force=True on"
  assert_output --partial "needs confirmed=True"
  layout_hook "$P2" ',"force":true,"confirmed":true'
  assert_success
  hook mcp__assistant__assistant_layout '{"action":"retile","force":true}'
  assert_failure 2
  assert_output --partial "force=True on the retile"
  layout_hook "$PANE" ',"force":true'
  assert_success
}

# bats test_tags=feature:assistant
@test "assistant server: it offers the seven assistant_ tools and sees the panes of this tmux server" {
  panes
  run python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("a", sys.argv[1]); a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
print(" ".join(sorted(a.mcp.tools)))
print(" ".join(d["id"] for d in a.list_panes()))
print([argv[0] for _, _, argv in a._proc_tree(a.list_panes()[0]["pane_pid"])][0])' "$REPO/assistant/mcp/server.py"
  assert_success
  assert_line "assistant_jobs assistant_launch assistant_layout assistant_panes assistant_projects assistant_schedule assistant_send"
  assert_line "$PANE"
  assert_line "bash"
}
